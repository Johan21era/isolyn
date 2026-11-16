#include "Dealer.hpp"
#include "DominoSet.hpp"
#include "EvaluationEngine.hpp"
#include "MatchController.hpp"
#include "ProbabilityEngine.hpp"
#include "RulesEngine.hpp"
#include "ScoreSystem.hpp"
#include "SearchEngine.hpp"
#include "StableRandom.hpp"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <random>
#include <string>
#include <string_view>
#include <vector>

using namespace isolyn;

namespace {

struct Options {
    int games = 200;
    int depth = 4;
    int determinizations = 20;
    int opponentDepth = 4;
    int opponentDeterminizations = 20;
    int timeMs = 0;
    int workers = 0;
    int opponentWorkers = 0;
    RootAggregation aggregation = RootAggregation::Mean;
    RootAggregation opponentAggregation = RootAggregation::Mean;
    int voluntaryDraws = 0;
    int opponentVoluntaryDraws = 0;
    // Sequential testing. 0 disables it and the run plays a fixed --games.
    // A "pair" is one round with A on each seat, so the test only ever looks
    // at balanced samples.
    // Total tiles left in all hands at which the search stops guessing and
    // solves the sampled world exactly. 0 disables the solver.
    int endgameTileLimit = 8;
    int opponentEndgameTileLimit = 8;
    // Two-tier root decision band: moves within this many evaluation units of
    // the best sampled value are treated as equal and ranked by the real
    // position's positional score instead. 0 keeps the plain argmax.
    double tieBreakBand = 0.0;
    double opponentTieBreakBand = 0.0;
    // Set-level play. 0 keeps the historical round-only mode; 3 or 4 plays
    // best-of-(2N-1) matches under the real ScoreSystem.
    int setsToWin = 0;
    int setTarget = 151;
    int roundsPerMatch = 300;
    int sprtPairs = 0;
    int sprtElo0 = 0;   // H0: the true difference is at most this
    int sprtElo1 = 5;   // H1: the true difference is at least this
    // Transposition-table key. "closer" drops history the search cannot see,
    // so positions reached by different move orders share an entry.
    bool compactTtKey = false;
    bool opponentCompactTtKey = false;
    // Two-regime evaluation: a second weight vector for quiet positions.
    bool conditionalWeights = false;
    bool opponentConditionalWeights = false;
    EvaluationWeights positionalWeights{};
    EvaluationWeights opponentPositionalWeights{};
    EvaluationWeights weights{};
    EvaluationWeights opponentWeights{};
    std::uint64_t seed = 1;
    std::string output = "lab/data/selfplay.csv";
    std::string mode = "1v1";
};

struct MoveRow {
    int moveIndex = 0;
    int player = 0;
    int tileLow = 0;
    int tileHigh = 0;
    int side = 0;
    int depthReached = 0;
    std::uint64_t nodes = 0;
    std::uint64_t ttHits = 0;
    bool exactEndgame = false;
    EvaluationBreakdown evaluation;
};

struct GameSummary {
    std::vector<int> initialHands;
    std::vector<int> finalHands;
    std::vector<int> participantSides;
    std::vector<int> participantScores;
    int participantCount = 0;
    int aDepth = 4;
    int aDeterminizations = 20;
    int bDepth = 4;
    int bDeterminizations = 20;
    int decidingPlayer = -1;
    RoundOutcomeKind outcome = RoundOutcomeKind::InProgress;
    int decisions = 0;
};

void usage(std::ostream& out) {
    out << "IsolynV2.0 self-play generator\n"
        << "Usage: selfplay [options]\n"
        << "  --games N               rounds to play (default 200)\n"
        << "  --depth N               max iterative-deepening depth (default 4)\n"
        << "  --determinizations N    hidden-world samples per move (default 20)\n"
        << "  --opponent-depth N      depth for the B side (default: 4, NOT --depth)\n"
        << "  --opponent-determinizations N\n"
        << "                          samples for the B side (default: 20, NOT --determinizations)\n"
        << "  --time-ms N             per-move search budget; 0 = unlimited (default 0)\n"
        << "  --workers N             search worker threads for A; 0 = auto (default 0)\n"
        << "  --opponent-workers N    worker threads for B; 0 = auto (default 0)\n"
        << "  --aggregation P         root rule for A: mean|maximin|trimmed|wincount\n"
        << "  --opponent-aggregation P  root rule for B (default: mean)\n"
        << "  --voluntary-draw N      voluntary draws per turn allowed for A (default 0)\n"
        << "  --opponent-voluntary-draw N  same for B (default 0)\n"
        << "  --conditional-weights   evaluate A in two regimes (off by default)\n"
        << "  --positional-weights LIST  A's weights when no immediate win exists\n"
        << "  --opponent-conditional-weights   same for B\n"
        << "  --opponent-positional-weights LIST  B's quiet-position weights\n"
        << "  --endgame-limit N       exact-solve when this many tiles remain, A (default 8)\n"
        << "  --opponent-endgame-limit N  same for B (default 8)\n"
        << "  --tie-break-band X      A: rank moves within X of the best by the real\n"
        << "                          position's positional score (default 0 = off)\n"
        << "  --opponent-tie-break-band X  same for B\n"
        << "  --tt-key K              transposition key for A: full | closer (default full)\n"
        << "  --opponent-tt-key K     transposition key for B (default full)\n"
        << "  --weights LIST           evaluation overrides, e.g. tempo=0,blocking=2\n"
        << "  --opponent-weights LIST   evaluation overrides for B\n"
        << "  --seed N                deterministic deal/search seed (default 1)\n"
        << "  --mode MODE             1v1 | 1v1v1 | 2v2 (default 1v1)\n"
        << "  --sets-to-win N         play best-of matches to N sets (3 or 4); 0 = rounds\n"
        << "  --set-target N          points that win a set (default 151; 101 is 1v1 only)\n"
        << "  --rounds-per-match N    safety cap on rounds in one match (default 300)\n"
        << "  --sprt-pairs N          stop as soon as the evidence decides; N pairs is the cap\n"
        << "  --sprt-elo0 N           H0 bound in Elo for the sequential test (default 0)\n"
        << "  --sprt-elo1 N           H1 bound in Elo for the sequential test (default 5)\n"
        << "  --output PATH           CSV output path (default lab/data/selfplay.csv)\n"
        << "  --check                 verify the linked engine and exit 0\n"
        << "  --help                  show this help\n";
}

bool parseInt(std::string_view text, int& value, bool allowZero = false) {
    try {
        std::size_t consumed = 0;
        int parsed = std::stoi(std::string(text), &consumed);
        if (consumed != text.size() || parsed < (allowZero ? 0 : 1)) return false;
        value = parsed;
        return true;
    } catch (...) {
        return false;
    }
}

bool parseSeed(std::string_view text, std::uint64_t& value) {
    if (text.empty() || text.front() == '-') return false;
    try {
        std::size_t consumed = 0;
        unsigned long long parsed = std::stoull(std::string(text), &consumed);
        if (consumed != text.size()) return false;
        value = static_cast<std::uint64_t>(parsed);
        return true;
    } catch (...) {
        return false;
    }
}

// "name=value,name=value" overrides for EvaluationWeights. Names match the
// EvaluationBreakdown fields, so an ablation and its record use one vocabulary.
bool applyWeightList(std::string_view list, EvaluationWeights& weights) {
    std::size_t start = 0;
    while (start <= list.size()) {
        const std::size_t comma = list.find(',', start);
        const std::string_view item = list.substr(
            start, comma == std::string_view::npos ? std::string_view::npos : comma - start);
        if (!item.empty()) {
            const std::size_t eq = item.find('=');
            if (eq == std::string_view::npos) return false;
            const std::string_view name = item.substr(0, eq);
            double value = 0.0;
            try {
                std::size_t used = 0;
                const std::string text(item.substr(eq + 1));
                value = std::stod(text, &used);
                if (used != text.size()) return false;
            } catch (...) {
                return false;
            }
            if (name == "mobility") weights.mobility = value;
            else if (name == "blocking") weights.blocking = value;
            else if (name == "expectedValue") weights.expectedValue = value;
            else if (name == "closingOpportunity") weights.closingOpportunity = value;
            else if (name == "winThreat") weights.winThreat = value;
            else if (name == "pipControl") weights.pipControl = value;
            else if (name == "tempo") weights.tempo = value;
            else if (name == "teamSupport") weights.teamSupport = value;
            else return false;
        }
        if (comma == std::string_view::npos) break;
        start = comma + 1;
    }
    return true;
}

bool parseAggregation(std::string_view text, RootAggregation& policy) {
    if (text == "mean") { policy = RootAggregation::Mean; return true; }
    if (text == "maximin") { policy = RootAggregation::Maximin; return true; }
    if (text == "trimmed") { policy = RootAggregation::TrimmedMean; return true; }
    if (text == "wincount") { policy = RootAggregation::WinCount; return true; }
    return false;
}

bool parseMode(std::string_view text, GameMode& mode) {
    if (text == "1v1") {
        mode = GameMode::OneVsOne;
        return true;
    }
    if (text == "1v1v1") {
        mode = GameMode::OneVsOneVsOne;
        return true;
    }
    if (text == "2v2") {
        mode = GameMode::TwoVsTwo;
        return true;
    }
    return false;
}

const char* modeName(GameMode mode) {
    switch (mode) {
        case GameMode::OneVsOne: return "1v1";
        case GameMode::OneVsOneVsOne: return "1v1v1";
        case GameMode::TwoVsTwo: return "2v2";
    }
    return "unknown";
}

const char* outcomeName(RoundOutcomeKind outcome) {
    switch (outcome) {
        case RoundOutcomeKind::InProgress: return "in_progress";
        case RoundOutcomeKind::DominoVictory: return "domino";
        case RoundOutcomeKind::Closed: return "closed";
    }
    return "unknown";
}

int handValueOf(const GameState& state, int player) {
    return RulesEngine::handPoints(state.hand(player));
}

// Reproducible deal: the engine's production Dealer deliberately uses OS
// CSPRNG, which is correct for play but useless for calibration. This
// mirrors Dealer::deal's pool/then-hand layout while taking the caller's
// seeded RNG, and still asks Dealer::isMisdeal for the rules check.
DealResult dealSeeded(GameMode mode, std::mt19937_64& rng) {
    const int playerCount = Dealer::playerCountForMode(mode);
    const int handSize = Dealer::handSizeForMode(mode);

    DealResult result;
    do {
        const auto& all = DominoSet::allTiles();
        std::vector<DominoTile> pool(all.begin(), all.end());
        for (const DominoTile& excluded : Dealer::excludedTilesForMode(mode)) {
            pool.erase(std::remove(pool.begin(), pool.end(), excluded), pool.end());
        }
        stable_random::shuffle(pool, rng);

        result.hands.assign(static_cast<std::size_t>(playerCount), {});
        auto cursor = pool.begin();
        for (int player = 0; player < playerCount; ++player) {
            result.hands[static_cast<std::size_t>(player)].assign(cursor, cursor + handSize);
            cursor += handSize;
        }
        result.boneyard.assign(cursor, pool.end());
    } while (Dealer::isMisdeal(mode, result.hands));

    return result;
}

MatchController createFirstRound(GameMode mode, std::mt19937_64& rng,
                                 std::vector<int>& initialHands) {
    DealResult dealt = dealSeeded(mode, rng);
    initialHands.clear();
    for (const auto& hand : dealt.hands) {
        int value = 0;
        for (const DominoTile& tile : hand) value += tile.value();
        initialHands.push_back(value);
    }
    GameState state(mode, dealt.hands, dealt.boneyard);
    const auto opening = RulesEngine::determineOpeningPlay(dealt.hands);
    state.playTile(opening.openingPlayerIndex, opening.openingTile, GameState::ChainSide::Left);
    state.setCurrentPlayerIndex((opening.openingPlayerIndex + 1) % state.playerCount());
    return MatchController(std::move(state));
}

// --- Sequential testing (SPRT) -------------------------------------------
//
// A fixed game count pays full price for every experiment, including the ones
// whose answer is already unambiguous. A sequential test stops as soon as the
// evidence crosses a decision boundary, so a clear effect costs a fraction of
// the rounds while both error rates stay bounded.
//
// Model: a round scores 1 (A wins), 0.5 (drawn/closed) or 0 (A loses). The LLR
// accumulates against two Bernoulli hypotheses -- the score A would need
// against an equal opponent for a difference of elo0 and elo1. Counting a draw
// as half a win is the standard simplification; it treats each round as if it
// carried independent variance and so slightly understates the true sample
// variance, which makes a verdict arrive sooner rather than later. That is a
// known limitation of this instrument, documented rather than hidden.
double eloToScore(double elo) {
    return 1.0 / (1.0 + std::pow(10.0, -elo / 400.0));
}

// Score for the A side in one round, read from the scores the rules engine
// already computed. Sides are assigned by the caller's seat alternation, so
// this is a comparison of participants, not of physical seats.
double roundScoreForSideA(const GameSummary& summary) {
    double a = -1.0;
    double b = -1.0;
    for (std::size_t i = 0; i < summary.participantSides.size(); ++i) {
        const int side = summary.participantSides[i];
        const double score = summary.participantScores[i];
        if (side == 0) a = score;
        else if (side == 1) b = score;
    }
    if (a < 0.0 || b < 0.0) return 0.5; // no attributable winner: treat as drawn
    if (a > b) return 1.0;
    if (a < b) return 0.0;
    return 0.5;
}

struct SprtState {
    double logP = 0.0; // ln(p1 / p0)
    double logQ = 0.0; // ln((1 - p1) / (1 - p0))
    double llr = 0.0;
    double lower = 0.0;
    double upper = 0.0;

    explicit SprtState(int elo0, int elo1) {
        const double p0 = eloToScore(static_cast<double>(elo0));
        const double p1 = eloToScore(static_cast<double>(elo1));
        logP = std::log(p1 / p0);
        logQ = std::log((1.0 - p1) / (1.0 - p0));
        // Wald bounds for alpha = beta = 0.05: accept H1 above ln(19), H0
        // below -ln(19).
        const double alpha = 0.05;
        const double beta = 0.05;
        lower = std::log(beta / (1.0 - alpha));
        upper = std::log((1.0 - beta) / alpha);
    }

    void observe(double score) {
        llr += score * logP + (1.0 - score) * logQ;
    }

    // +1 = H1 accepted, -1 = H0 accepted, 0 = still undecided.
    int verdict() const {
        if (llr >= upper) return 1;
        if (llr <= lower) return -1;
        return 0;
    }
};

GameSummary playOneRound(const Options& options,
                         GameMode mode,
                         std::uint64_t dealSeed,
                         bool aIsFirstSide,
                         std::vector<MoveRow>& rows) {
    std::mt19937_64 rng(dealSeed);
    std::vector<int> initialHands;
    MatchController controller = createFirstRound(mode, rng, initialHands);

    SearchEngine::Config configA;
    configA.maxDepthPlies = options.depth;
    configA.determinizationCount = options.determinizations;
    configA.timeLimitMs = options.timeMs;
    configA.endgameTileLimit = options.endgameTileLimit;
    configA.workerThreads = options.workers;
    configA.rootAggregation = options.aggregation;
    configA.maxVoluntaryDraws = options.voluntaryDraws;
    configA.positionalBand = options.tieBreakBand;
    configA.useSelectiveSearch = options.depth >= 24;
    configA.weights = options.weights;
    configA.positionalWeights = options.positionalWeights;
    configA.useConditionalWeights = options.conditionalWeights;
    configA.transpositionKeyMode = options.compactTtKey
        ? GameState::TranspositionKeyMode::CloserSummary
        : GameState::TranspositionKeyMode::FullHistory;

    SearchEngine::Config configB;
    configB.maxDepthPlies = options.opponentDepth;
    configB.determinizationCount = options.opponentDeterminizations;
    configB.timeLimitMs = options.timeMs;
    configB.endgameTileLimit = options.opponentEndgameTileLimit;
    configB.workerThreads = options.opponentWorkers;
    configB.rootAggregation = options.opponentAggregation;
    configB.maxVoluntaryDraws = options.opponentVoluntaryDraws;
    configB.positionalBand = options.opponentTieBreakBand;
    configB.useSelectiveSearch = options.opponentDepth >= 24;
    configB.weights = options.opponentWeights;
    configB.positionalWeights = options.opponentPositionalWeights;
    configB.useConditionalWeights = options.opponentConditionalWeights;
    configB.transpositionKeyMode = options.opponentCompactTtKey
        ? GameState::TranspositionKeyMode::CloserSummary
        : GameState::TranspositionKeyMode::FullHistory;

    // The caller alternates which physical side gets the A configuration, so a
    // one-sided first-player advantage cannot masquerade as a strength
    // difference. In match mode it is fixed for the whole match.
    auto sideForPlayer = [&](int player) {
        if (mode == GameMode::TwoVsTwo) {
            const int team = RulesEngine::teamIndexForPlayer(player);
            return team == (aIsFirstSide ? 0 : 1) ? 0 : 1;
        }
        return player == (aIsFirstSide ? 0 : 1) ? 0 : 1;
    };
    auto configForSide = [&](int side) -> const SearchEngine::Config& {
        return side == 0 ? configA : configB;
    };

    RoundOutcome outcome{RoundOutcomeKind::InProgress, -1};
    int decisionCount = 0;
    int drawPlayer = -1;
    int drawsThisTurn = 0;

    for (int turn = 0; turn < 500; ++turn) {
        if (!controller.currentPlayerHasLegalMove()) {
            if (controller.state().boneyard().drawableCount() > 0) {
                controller.resolveForcedDraw();
            }
            if (!controller.currentPlayerHasLegalMove()) {
                outcome = controller.endTurnWithNoPlay();
                if (outcome.kind != RoundOutcomeKind::InProgress) break;
                continue;
            }
        }

        const int player = controller.currentPlayerIndex();
        if (player != drawPlayer) {
            drawPlayer = player;
            drawsThisTurn = 0;
        }
        const int side = sideForPlayer(player);
        const SearchEngine::Config& searchConfig = configForSide(side);

        // Once the per-turn draw budget is spent, the engine is asked with the
        // option disabled so it returns a placement it can legally play.
        SearchEngine::Config placeOnly = searchConfig;
        placeOnly.maxVoluntaryDraws = 0;
        const SearchEngine::Config& effective =
            drawsThisTurn < searchConfig.maxVoluntaryDraws ? searchConfig : placeOnly;

        const GameState& state = controller.state();
        BeliefState belief = ProbabilityEngine::constructFromGameState(state, player);
        const SearchDecision decision = SearchEngine::chooseBestMove(
            state, belief, mode, effective, rng, nullptr);
        const EvaluationBreakdown evaluation = EvaluationEngine::evaluate(mode, state, player);

        MoveRow row;
        row.moveIndex = decisionCount++;
        row.player = player;
        // A draw has no tile; -1 marks it so draw frequency stays auditable.
        row.tileLow = decision.isDraw ? -1 : decision.move.tile.low();
        row.tileHigh = decision.isDraw ? -1 : decision.move.tile.high();
        row.side = decision.isDraw
                       ? -1
                       : (decision.move.side == GameState::ChainSide::Left ? 0 : 1);
        row.depthReached = decision.depthReached;
        row.nodes = decision.nodesVisited;
        row.ttHits = decision.transpositionHits;
        row.exactEndgame = decision.exactEndgame;
        row.evaluation = evaluation;
        rows.push_back(row);

        if (decision.isDraw && controller.canVoluntaryDraw()) {
            controller.voluntaryDraw();
            ++drawsThisTurn;
            continue; // the draw does not end the turn; the same player acts again
        }

        drawsThisTurn = 0;
        outcome = controller.playTurn(decision.move);
        if (outcome.kind != RoundOutcomeKind::InProgress) break;
    }

    GameSummary summary;
    summary.initialHands = initialHands;
    summary.outcome = outcome.kind;
    summary.decidingPlayer = outcome.decidingPlayerIndex;
    summary.decisions = decisionCount;
    summary.aDepth = options.depth;
    summary.aDeterminizations = options.determinizations;
    summary.bDepth = options.opponentDepth;
    summary.bDeterminizations = options.opponentDeterminizations;

    const GameState& state = controller.state();
    for (int p = 0; p < state.playerCount(); ++p) {
        summary.finalHands.push_back(handValueOf(state, p));
        summary.participantSides.push_back(sideForPlayer(p));
    }

    std::vector<int> participantValues;
    if (mode == GameMode::TwoVsTwo) {
        auto t0 = RulesEngine::playersOnTeam(0);
        auto t1 = RulesEngine::playersOnTeam(1);
        participantValues.push_back(RulesEngine::combineTeamValue(
            handValueOf(state, t0.first), handValueOf(state, t0.second)));
        participantValues.push_back(RulesEngine::combineTeamValue(
            handValueOf(state, t1.first), handValueOf(state, t1.second)));
    } else {
        for (int p = 0; p < state.playerCount(); ++p) {
            participantValues.push_back(handValueOf(state, p));
        }
    }
    summary.participantScores = RulesEngine::computeRoundScores(participantValues);
    summary.participantCount = static_cast<int>(summary.participantScores.size());
    return summary;
}

void writeHeader(std::ofstream& out) {
    out << "game,seed,mode,config_a_depth,config_a_determinizations,"
           "config_b_depth,config_b_determinizations,"
           "participant_side0,participant_side1,participant_side2,participant_side3,"
           "move,player,tile_low,tile_high,side,"
           "depth_reached,nodes,tt_hits,exact_endgame,"
           "eval_total,mobility,blocking,expected_value,closing_opportunity,"
           "win_threat,pip_control,tempo,team_support,"
           "initial_hand0,initial_hand1,initial_hand2,initial_hand3,"
           "final_hand0,final_hand1,final_hand2,final_hand3,"
           "participant_count,participant_score0,participant_score1,participant_score2,participant_score3,"
           "outcome,deciding_player\n";
}

void writeRows(std::ofstream& out,
               std::uint64_t gameIndex,
               std::uint64_t seed,
               GameMode mode,
               const GameSummary& summary,
               const std::vector<MoveRow>& rows) {
    for (const MoveRow& row : rows) {
        out << gameIndex << ','
            << seed << ','
            << modeName(mode) << ','
            << summary.aDepth << ','
            << summary.aDeterminizations << ','
            << summary.bDepth << ','
            << summary.bDeterminizations << ',';
        for (int p = 0; p < 4; ++p) {
            out << (p < static_cast<int>(summary.participantSides.size()) ? summary.participantSides[static_cast<std::size_t>(p)] : 0)
                << ',';
        }
        out << row.moveIndex << ','
            << row.player << ','
            << row.tileLow << ','
            << row.tileHigh << ','
            << row.side << ','
            << row.depthReached << ','
            << row.nodes << ','
            << row.ttHits << ','
            << (row.exactEndgame ? 1 : 0) << ','
            << row.evaluation.total << ','
            << row.evaluation.mobility << ','
            << row.evaluation.blocking << ','
            << row.evaluation.expectedValue << ','
            << row.evaluation.closingOpportunity << ','
            << row.evaluation.winThreat << ','
            << row.evaluation.pipControl << ','
            << row.evaluation.tempo << ','
            << row.evaluation.teamSupport << ',';

        for (int p = 0; p < 4; ++p) {
            out << (p < static_cast<int>(summary.initialHands.size()) ? summary.initialHands[static_cast<std::size_t>(p)] : 0)
                << ',';
        }

        for (int p = 0; p < 4; ++p) {
            out << (p < static_cast<int>(summary.finalHands.size()) ? summary.finalHands[static_cast<std::size_t>(p)] : 0)
                << ',';
        }
        out << summary.participantCount << ',';
        for (int p = 0; p < 4; ++p) {
            out << (p < static_cast<int>(summary.participantScores.size()) ? summary.participantScores[static_cast<std::size_t>(p)] : 0)
                << ',';
        }
        out << outcomeName(summary.outcome) << ','
            << summary.decidingPlayer << '\n';
    }
}

// --- Set-level play -------------------------------------------------------
//
// The round harness above scores one hand and stops. A real game is a race to
// 151 points (R-06) inside a best-of-(2N-1) match, so this layer replays the
// round generator and feeds each hand's participant scores through the same
// ScoreSystem the bridge uses. Nothing about round play changes; only the
// accounting around it.
struct MatchSummary {
    int rounds = 0;
    int incompleteRounds = 0;
    int winnerParticipant = -1;
    int winnerSide = -1;
    int setsA = 0;
    int setsB = 0;
    long long pointsA = 0;
    long long pointsB = 0;
    std::vector<int> setWins;
    std::vector<long long> points;
    std::uint64_t decisions = 0;
};

MatchSummary playOneMatch(const Options& options,
                          GameMode mode,
                          std::uint64_t matchIndex,
                          std::ofstream& roundsOut) {
    const int participantCount =
        mode == GameMode::TwoVsTwo ? 2 : Dealer::playerCountForMode(mode);
    const bool aIsFirstSide = (matchIndex % 2 == 0);
    const std::uint64_t baseSeed =
        options.seed + matchIndex * 0x9E3779B97F4A7C15ULL;

    // Mirrors playOneRound's sideForPlayer: in 2v2 a participant IS a team.
    auto sideOfParticipant = [&](int participant) {
        return participant == (aIsFirstSide ? 0 : 1) ? 0 : 1;
    };

    MatchSummary match;
    match.setWins.assign(static_cast<std::size_t>(participantCount), 0);
    match.points.assign(static_cast<std::size_t>(participantCount), 0);

    ScoreSystem scores(mode, participantCount, options.setTarget);

    for (int round = 0; round < options.roundsPerMatch && match.winnerParticipant < 0; ++round) {
        std::vector<MoveRow> rows;
        const std::uint64_t dealSeed =
            baseSeed + static_cast<std::uint64_t>(round) * 0xD1B54A32D192ED03ULL;
        const GameSummary summary = playOneRound(options, mode, dealSeed, aIsFirstSide, rows);
        writeRows(roundsOut, matchIndex, options.seed, mode, summary, rows);

        ++match.rounds;
        match.decisions += static_cast<std::uint64_t>(summary.decisions);
        if (summary.outcome == RoundOutcomeKind::InProgress) {
            ++match.incompleteRounds;
            continue;
        }

        for (std::size_t i = 0; i < summary.participantScores.size(); ++i) {
            match.points[i] += summary.participantScores[i];
            if (sideOfParticipant(static_cast<int>(i)) == 0) {
                match.pointsA += summary.participantScores[i];
            } else {
                match.pointsB += summary.participantScores[i];
            }
        }

        scores.applyRoundScores(summary.participantScores);
        if (!scores.hasMatchEnded()) continue;

        const int winner = scores.winningParticipant();
        match.setWins[static_cast<std::size_t>(winner)]++;
        if (sideOfParticipant(winner) == 0) ++match.setsA;
        else ++match.setsB;

        if (match.setWins[static_cast<std::size_t>(winner)] >= options.setsToWin) {
            match.winnerParticipant = winner;
            match.winnerSide = sideOfParticipant(winner);
        } else {
            scores = ScoreSystem(mode, participantCount, options.setTarget);
        }
    }
    return match;
}

} // namespace

int main(int argc, char** argv) {
    Options options;
    GameMode mode = GameMode::OneVsOne;

    for (int i = 1; i < argc; ++i) {
        std::string_view arg = argv[i];
        if (arg == "--help" || arg == "-h") {
            usage(std::cout);
            return 0;
        }
        if (arg == "--check") {
            std::cout << "selfplay: linked real engine; ok\n";
            return 0;
        }
        if (arg == "--conditional-weights") {
            options.conditionalWeights = true;
            continue;
        }
        if (arg == "--opponent-conditional-weights") {
            options.opponentConditionalWeights = true;
            continue;
        }
        if (arg == "--tie-break-band" || arg == "--opponent-tie-break-band") {
            if (i + 1 >= argc) {
                std::cerr << "missing value for " << arg << "\n";
                return 2;
            }
            const std::string text = argv[++i];
            double parsed = 0.0;
            try {
                std::size_t used = 0;
                parsed = std::stod(text, &used);
                if (used != text.size()) {
                    std::cerr << "invalid value for " << arg << ": " << text << "\n";
                    return 2;
                }
            } catch (...) {
                std::cerr << "invalid value for " << arg << ": " << text << "\n";
                return 2;
            }
            if (arg == "--tie-break-band") options.tieBreakBand = parsed;
            else options.opponentTieBreakBand = parsed;
            continue;
        }
        if (arg == "--games" || arg == "--depth" || arg == "--determinizations" ||
            arg == "--opponent-depth" || arg == "--opponent-determinizations" ||
            arg == "--time-ms" || arg == "--workers" || arg == "--opponent-workers" ||
            arg == "--aggregation" || arg == "--opponent-aggregation" ||
            arg == "--voluntary-draw" || arg == "--opponent-voluntary-draw" ||
            arg == "--sprt-pairs" || arg == "--sprt-elo0" || arg == "--sprt-elo1" ||
            arg == "--sets-to-win" || arg == "--set-target" || arg == "--rounds-per-match" ||
            arg == "--tt-key" || arg == "--opponent-tt-key" ||
            arg == "--endgame-limit" || arg == "--opponent-endgame-limit" ||
            arg == "--weights" || arg == "--opponent-weights" ||
            arg == "--positional-weights" || arg == "--opponent-positional-weights" ||
            arg == "--seed" || arg == "--mode" || arg == "--output") {
            if (i + 1 >= argc) {
                std::cerr << "missing value for " << arg << "\n";
                return 2;
            }
            std::string_view value = argv[++i];
            if (arg == "--output") {
                options.output = std::string(value);
                continue;
            }
            if (arg == "--mode") {
                if (!parseMode(value, mode)) {
                    std::cerr << "invalid mode: " << value << " (expected 1v1, 1v1v1, or 2v2)\n";
                    return 2;
                }
                options.mode = std::string(value);
                continue;
            }
            if (arg == "--weights" || arg == "--opponent-weights") {
                EvaluationWeights target = EvaluationWeights{};
                if (!applyWeightList(value, target)) {
                    std::cerr << "invalid weights: " << value
                              << " (expected name=value pairs, e.g. tempo=0,blocking=2)\n";
                    return 2;
                }
                if (arg == "--weights") options.weights = target;
                else options.opponentWeights = target;
                continue;
            }
            if (arg == "--positional-weights" || arg == "--opponent-positional-weights") {
                EvaluationWeights target = EvaluationWeights{};
                if (!applyWeightList(value, target)) {
                    std::cerr << "invalid positional weights: " << value << "\n";
                    return 2;
                }
                if (arg == "--positional-weights") options.positionalWeights = target;
                else options.opponentPositionalWeights = target;
                continue;
            }
            if (arg == "--tt-key" || arg == "--opponent-tt-key") {
                if (value != "full" && value != "closer") {
                    std::cerr << "invalid tt key: " << value << " (expected full or closer)\n";
                    return 2;
                }
                const bool compact = value == "closer";
                if (arg == "--tt-key") options.compactTtKey = compact;
                else options.opponentCompactTtKey = compact;
                continue;
            }
            if (arg == "--aggregation" || arg == "--opponent-aggregation") {
                RootAggregation policy = RootAggregation::Mean;
                if (!parseAggregation(value, policy)) {
                    std::cerr << "invalid aggregation: " << value
                              << " (expected mean, maximin, trimmed, or wincount)\n";
                    return 2;
                }
                if (arg == "--aggregation") options.aggregation = policy;
                else options.opponentAggregation = policy;
                continue;
            }
            if (arg == "--seed") {
                if (!parseSeed(value, options.seed)) {
                    std::cerr << "invalid seed: " << value << "\n";
                    return 2;
                }
                continue;
            }
            int parsed = 0;
            const bool allowZero = arg == "--time-ms" || arg == "--workers" ||
                                   arg == "--opponent-workers" ||
                                   arg == "--voluntary-draw" || arg == "--opponent-voluntary-draw" ||
                                   arg == "--sprt-pairs" || arg == "--sprt-elo0" ||
                                   arg == "--endgame-limit" || arg == "--opponent-endgame-limit" ||
                                   arg == "--sets-to-win";
            if (!parseInt(value, parsed, allowZero)) {
                std::cerr << "invalid value for " << arg << ": " << value << "\n";
                return 2;
            }
            if (arg == "--games") options.games = parsed;
            else if (arg == "--depth") options.depth = parsed;
            else if (arg == "--determinizations") options.determinizations = parsed;
            else if (arg == "--opponent-depth") options.opponentDepth = parsed;
            else if (arg == "--opponent-determinizations") options.opponentDeterminizations = parsed;
            else if (arg == "--time-ms") options.timeMs = parsed;
            else if (arg == "--workers") options.workers = parsed;
            else if (arg == "--opponent-workers") options.opponentWorkers = parsed;
            else if (arg == "--voluntary-draw") options.voluntaryDraws = parsed;
            else if (arg == "--opponent-voluntary-draw") options.opponentVoluntaryDraws = parsed;
            else if (arg == "--sprt-pairs") options.sprtPairs = parsed;
            else if (arg == "--sprt-elo0") options.sprtElo0 = parsed;
            else if (arg == "--sprt-elo1") options.sprtElo1 = parsed;
            else if (arg == "--sets-to-win") options.setsToWin = parsed;
            else if (arg == "--set-target") options.setTarget = parsed;
            else if (arg == "--rounds-per-match") options.roundsPerMatch = parsed;
            else if (arg == "--endgame-limit") options.endgameTileLimit = parsed;
            else if (arg == "--opponent-endgame-limit") options.opponentEndgameTileLimit = parsed;
            continue;
        }
        std::cerr << "unknown argument: " << arg << "\n";
        usage(std::cerr);
        return 2;
    }

    if (options.setsToWin != 0 && options.setsToWin != 3 && options.setsToWin != 4) {
        std::cerr << "--sets-to-win must be 3 or 4 (0 = round mode)\n";
        return 2;
    }
    if (options.setTarget != 151 &&
        !(mode == GameMode::OneVsOne && options.setTarget == 101)) {
        std::cerr << "--set-target must be 151, or 101 in 1v1\n";
        return 2;
    }
    if (options.setsToWin > 0 && options.sprtPairs > 0) {
        std::cerr << "--sprt-pairs is round-scoped; do not combine it with --sets-to-win\n";
        return 2;
    }

    const std::filesystem::path outputPath(options.output);
    if (!outputPath.parent_path().empty()) {
        std::filesystem::create_directories(outputPath.parent_path());
    }
    std::ofstream out(outputPath);
    if (!out) {
        std::cerr << "could not open output: " << outputPath << "\n";
        return 2;
    }

    std::cout << "IsolynV2.0 self-play\n"
              << "  games: " << options.games << "\n"
              << "  mode: " << options.mode << "\n"
              << "  depth: " << options.depth << "\n"
              << "  determinizations: " << options.determinizations << "\n"
              << "  opponent depth: " << options.opponentDepth << "\n"
              << "  opponent determinizations: " << options.opponentDeterminizations << "\n"
              << "  time-ms: " << options.timeMs << "\n"
              << "  seed: " << options.seed << "\n"
              << "  output: " << outputPath << "\n"
              << "  A conditional: " << (options.conditionalWeights ? "on" : "off")
              << " (positional tempo " << options.positionalWeights.tempo
              << ", mobility " << options.positionalWeights.mobility << ")\n"
              << "  B conditional: " << (options.opponentConditionalWeights ? "on" : "off")
              << " (positional tempo " << options.opponentPositionalWeights.tempo
              << ", mobility " << options.opponentPositionalWeights.mobility << ")\n";

    if (options.setsToWin > 0) {
        const std::filesystem::path roundsPath = std::string(outputPath) + ".rounds.csv";
        std::ofstream roundsOut(roundsPath);
        if (!roundsOut) {
            std::cerr << "could not open rounds output: " << roundsPath << "\n";
            return 2;
        }
        writeHeader(roundsOut);
        out << "match,seed,mode,sets_to_win,target,rounds,incomplete,"
               "winner_participant,winner_side,sets_a,sets_b,points_a,points_b,"
               "set_wins_0,set_wins_1,set_wins_2,set_wins_3,"
               "points_0,points_1,points_2,points_3\n";

        int matchesA = 0;
        int matchesB = 0;
        int unfinished = 0;
        long long totalRounds = 0;
        std::uint64_t matchDecisions = 0;

        for (int matchIndex = 0; matchIndex < options.games; ++matchIndex) {
            const MatchSummary summary = playOneMatch(
                options, mode, static_cast<std::uint64_t>(matchIndex), roundsOut);

            out << matchIndex << ',' << options.seed << ',' << modeName(mode) << ','
                << options.setsToWin << ',' << options.setTarget << ','
                << summary.rounds << ',' << summary.incompleteRounds << ','
                << summary.winnerParticipant << ',' << summary.winnerSide << ','
                << summary.setsA << ',' << summary.setsB << ','
                << summary.pointsA << ',' << summary.pointsB;
            for (int p = 0; p < 4; ++p) {
                out << ',' << (p < static_cast<int>(summary.setWins.size())
                                   ? summary.setWins[static_cast<std::size_t>(p)] : 0);
            }
            for (int p = 0; p < 4; ++p) {
                out << ',' << (p < static_cast<int>(summary.points.size())
                                   ? summary.points[static_cast<std::size_t>(p)] : 0);
            }
            out << '\n';

            totalRounds += summary.rounds;
            matchDecisions += summary.decisions;
            if (summary.winnerSide == 0) ++matchesA;
            else if (summary.winnerSide == 1) ++matchesB;
            else ++unfinished;

            if ((matchIndex + 1) % 5 == 0 || matchIndex + 1 == options.games) {
                std::cout << "  finished " << (matchIndex + 1) << "/" << options.games
                          << " matches (" << totalRounds << " rounds, "
                          << matchDecisions << " decisions)" << std::endl;
            }
        }

        std::cout << "wrote " << outputPath << " (matches) and " << roundsPath
                  << " (moves)\n"
                  << "  matches: " << options.games << "\n"
                  << "  A match wins: " << matchesA << "\n"
                  << "  B match wins: " << matchesB << "\n"
                  << "  unfinished: " << unfinished << "\n"
                  << "  rounds: " << totalRounds
                  << " (mean " << (options.games > 0
                          ? static_cast<double>(totalRounds) / options.games : 0.0)
                  << " per match)\n"
                  << "  decisions: " << matchDecisions << "\n";
        return unfinished == 0 ? 0 : 1;
    }

    writeHeader(out);

    int completed = 0;
    int incomplete = 0;
    std::uint64_t totalDecisions = 0;

    // Sequential testing replaces the fixed count when requested. Evidence is
    // observed per round but only acted on at pair boundaries, so every
    // decision the test makes rests on an equal number of A-first and
    // B-first rounds.
    const bool useSprt = options.sprtPairs > 0;
    if (useSprt && options.sprtElo1 <= options.sprtElo0) {
        std::cerr << "--sprt-elo1 must be greater than --sprt-elo0\n";
        return 2;
    }
    if (useSprt && options.mode == "1v1v1") {
        std::cerr << "--sprt-pairs does not apply to 1v1v1: only two of the three "
                     "seats map to A or B, so a round has no single score for A.\n";
        return 2;
    }
    const int totalGames = useSprt ? options.sprtPairs * 2 : options.games;
    SprtState sprtState(options.sprtElo0, options.sprtElo1);
    double sprtScoreSum = 0.0;
    int gamesPlayed = 0;
    int sprtVerdict = 0;

    for (int game = 0; game < totalGames; ++game) {
        std::vector<MoveRow> rows;
        const GameSummary summary = playOneRound(
            options, mode,
            options.seed + static_cast<std::uint64_t>(game) * 0x9E3779B97F4A7C15ULL,
            game % 2 == 0, rows);
        writeRows(out, static_cast<std::uint64_t>(game), options.seed, mode, summary, rows);
        totalDecisions += static_cast<std::uint64_t>(summary.decisions);
        if (summary.outcome == RoundOutcomeKind::InProgress) ++incomplete;
        else ++completed;
        ++gamesPlayed;

        if (useSprt) {
            const double score = roundScoreForSideA(summary);
            sprtScoreSum += score;
            sprtState.observe(score);
            if ((gamesPlayed % 2 == 0) || gamesPlayed == totalGames) {
                sprtVerdict = sprtState.verdict();
                std::cout << "  sprt after " << gamesPlayed << " rounds: score "
                          << std::fixed << std::setprecision(4)
                          << (sprtScoreSum / static_cast<double>(gamesPlayed))
                          << ", LLR " << sprtState.llr << std::endl;
                if (sprtVerdict != 0) break;
            }
        }

        if ((game + 1) % 10 == 0 || game + 1 == totalGames) {
            // Flush each progress line: the launcher publishes shard progress by
            // reading this log while the process is still writing to it.
            std::cout << "  finished " << (game + 1) << "/" << options.games
                      << " rounds (" << totalDecisions << " decisions)" << std::endl;
        }
    }

    std::cout << "wrote " << outputPath << "\n"
              << "  completed rounds: " << completed << "\n"
              << "  incomplete rounds: " << incomplete << "\n"
              << "  decisions: " << totalDecisions << "\n";

    if (useSprt) {
        const double meanScore =
            gamesPlayed > 0 ? sprtScoreSum / static_cast<double>(gamesPlayed) : 0.0;
        std::cout << "  sequential test: H0 " << options.sprtElo0 << " Elo vs H1 "
                  << options.sprtElo1 << " Elo, alpha=beta=0.05, cap " << totalGames
                  << " rounds\n"
                  << "  rounds played: " << gamesPlayed << "\n"
                  << "  score for A: " << std::fixed << std::setprecision(4) << meanScore
                  << "\n"
                  << "  LLR: " << sprtState.llr << "  bounds: [" << sprtState.lower << ", "
                  << sprtState.upper << "]\n";
        if (sprtVerdict > 0) {
            std::cout << "  verdict: H1 accepted - A is at least " << options.sprtElo1
                      << " Elo stronger at alpha=beta=0.05\n";
        } else if (sprtVerdict < 0) {
            std::cout << "  verdict: H0 accepted - no difference of " << options.sprtElo1
                      << " Elo detected at alpha=beta=0.05\n";
        } else {
            std::cout << "  verdict: inconclusive - round cap reached\n";
        }
    }

    return incomplete == 0 ? 0 : 1;
}
