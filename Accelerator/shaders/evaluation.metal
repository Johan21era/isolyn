#include <metal_stdlib>
using namespace metal;

struct EvalParams {
    uint positionCount;
    uint playerCount;
    uint componentCount;
};

kernel void isolyn_evaluate_batch(
    device const float* features [[buffer(0)]],
    device float* values [[buffer(1)]],
    constant EvalParams& params [[buffer(2)]],
    uint gid [[thread_position_in_grid]])
{
    const uint total = params.positionCount * params.playerCount;
    if (gid >= total) return;
    const uint position = gid / params.playerCount;
    const uint player = gid % params.playerCount;
    const uint base = (position * params.playerCount + player) * params.componentCount;
    float sum = 0.0f;
    for (uint component = 0; component < params.componentCount; ++component) {
        sum += features[base + component];
    }
    values[gid] = sum;
}

struct PositionRow {
    uint handMasks[4];
    int leftEnd;
    int rightEnd;
    uint currentPlayer;
    uint playerCount;
    uint mode;
    uint closed;
    uint closerPlayer;
    uint roundScores[4];
};

struct EvalPositionParams {
    uint positionCount;
    uint playerCount;
};

constant int kTileHigh[28] = {
    0,
    1, 1,
    2, 2, 2,
    3, 3, 3, 3,
    4, 4, 4, 4, 4,
    5, 5, 5, 5, 5, 5,
    6, 6, 6, 6, 6, 6, 6,
};

constant int kTileLow[28] = {
    0,
    0, 1,
    0, 1, 2,
    0, 1, 2, 3,
    0, 1, 2, 3, 4,
    0, 1, 2, 3, 4, 5,
    0, 1, 2, 3, 4, 5, 6,
};

constant uint kFaceMask[7] = {
    0x0020844bu, 0x00410896u, 0x00821138u, 0x010423c0u,
    0x02087c00u, 0x041f8000u, 0x0fe00000u,
};

inline uint tileHigh(uint index) {
    return uint(kTileHigh[index]);
}

inline uint tileLow(uint index) {
    return uint(kTileLow[index]);
}

inline int handValue(uint mask) {
    int total = 0;
    for (uint i = 0; i < 28; ++i) {
        if ((mask & (1u << i)) != 0) {
            total += int(tileLow(i) + tileHigh(i));
        }
    }
    return total;
}

inline int mobility(uint mask, int left, int right) {
    if (left < 0) {
        return int(popcount(mask));
    }
    // A tile matching both ends contributes two placements, exactly as the
    // former per-tile scan did. Two bit tests replace 28 scalar iterations.
    return int(popcount(mask & kFaceMask[left]) +
               popcount(mask & kFaceMask[right]));
}

inline bool hasImmediateThreat(uint mask, int left, int right) {
    if (popcount(mask) != 1) return false;
    if (left < 0) return true;
    return (mask & (kFaceMask[left] | kFaceMask[right])) != 0;
}

// Computes one EvaluationEngine total per player for each compact position.
// The host only supplies visible state facts; all eight heuristic components
// are calculated here, in the same order and with the same weights as the C++
// reference implementation.
kernel void isolyn_evaluate_positions(
    device const PositionRow* positions [[buffer(0)]],
    device float* values [[buffer(1)]],
    constant EvalPositionParams& params [[buffer(2)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid >= params.positionCount) return;

    const PositionRow row = positions[gid];
    const uint playerCount = params.playerCount;
    const uint base = gid * playerCount;
    const uint mode = row.mode;

    int handValues[4] = { 0, 0, 0, 0 };
    int mobilities[4] = { 0, 0, 0, 0 };
    bool threats[4] = { false, false, false, false };
    int emptyPlayer = -1;

    for (uint p = 0; p < playerCount; ++p) {
        const uint mask = row.handMasks[p];
        if (mask == 0) {
            emptyPlayer = int(p);
            break;
        }
        handValues[p] = handValue(mask);
        mobilities[p] = mobility(mask, row.leftEnd, row.rightEnd);
        threats[p] = hasImmediateThreat(mask, row.leftEnd, row.rightEnd);
    }

    // A terminal Domino position short-circuits all positional heuristics.
    if (emptyPlayer >= 0) {
        for (uint p = 0; p < playerCount; ++p) {
            const bool onWinningSide = (mode == 2)
                ? ((p & 1u) == (uint(emptyPlayer) & 1u))
                : (p == uint(emptyPlayer));
            values[base + p] = onWinningSide ? 0.0f : -float(handValue(row.handMasks[p]));
        }
        return;
    }

    for (uint p = 0; p < playerCount; ++p) {
        int opponentMobility = 0;
        for (uint q = 0; q < playerCount; ++q) {
            if (q != p) opponentMobility += mobilities[q];
        }

        float winThreat = 0.0f;
        if (mode == 2) {
            const uint otherTeam = (p & 1u) ^ 1u;
            if (threats[p] || threats[p ^ 2u]) winThreat += 1000.0f;
            if (threats[otherTeam] || threats[otherTeam ^ 2u]) winThreat -= 1000.0f;
        } else {
            if (threats[p]) winThreat += 1000.0f;
            for (uint q = 0; q < playerCount; ++q) {
                if (q != p && threats[q]) winThreat -= 1000.0f;
            }
        }

        // Pip control is the same count as mobility when the chain is open;
        // reuse the already-computed value instead of rescanning the hand.
        const float pipControl = (row.leftEnd >= 0)
            ? 0.5f * float(mobilities[p])
            : 0.0f;

        float closingOpportunity = 0.0f;
        if (row.closed != 0) {
            const uint participant = (mode == 2) ? (p & 1u) : p;
            const uint closer = (mode == 2) ? (row.closerPlayer & 1u) : row.closerPlayer;
            closingOpportunity = -float(row.roundScores[participant]) +
                                 (participant == closer ? 5.0f : 0.0f);
        }

        float tempo = 0.0f;
        if (mode == 2) {
            if ((row.currentPlayer & 1u) == (p & 1u)) tempo = 1.0f;
        } else if (row.currentPlayer == p) {
            tempo = 1.0f;
        }

        float teamSupport = 0.0f;
        if (mode == 2) {
            teamSupport = 0.25f * float(mobilities[p] + mobilities[p ^ 2u]);
        }

        const float total =
            float(mobilities[p]) -
            float(opponentMobility) -
            float(handValues[p]) +
            closingOpportunity +
            winThreat +
            0.5f * pipControl +
            0.1f * tempo +
            0.25f * teamSupport;
        values[base + p] = total;
    }
}
