#include "Dealer.hpp"
#include "DominoSet.hpp"
#include "EvaluationEngine.hpp"
#include "MatchController.hpp"
#include "ProbabilityEngine.hpp"
#include "RulesEngine.hpp"
#include "SearchEngine.hpp"

#include <algorithm>
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
        << "  --opponent-depth N      depth for the B side (default: --depth)\n"
        << "  --opponent-determinizations N\n"
        << "                          samples for the B side (default: --determinizations)\n"
        << "  --time-ms N             per-move search budget; 0 = unlimited (default 0)\n"
        << "  --workers N             search worker threads for A; 0 = auto (default 0)\n"
        << "  --opponent-workers N    worker threads for B; 0 = auto (default 0)\n"
        << "  --aggregation P         root rule for A: mean|maximin|trimmed|wincount\n"
        << "  --opponent-aggregation P  root rule for B (default: mean)\n"
        << "  --voluntary-draw N      voluntary draws per turn allowed for A (default 0)\n"
        << "  --opponent-voluntary-draw N  same for B (default 0)\n"
        << "  --weights LIST           evaluation overrides, e.g. tempo=0,blocking=2\n"
        << "  --opponent-weights LIST   evaluation overrides for B\n"
        << "  --seed N                deterministic deal/search seed (default 1)\n"
        << "  --mode MODE             1v1 | 1v1v1 | 2v2 (default 1v1)\n"
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
        std::shuffle(pool.begin(), pool.end(), rng);

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

GameSummary playOneRound(const Options& options,
                         GameMode mode,
                         std::uint64_t gameIndex,
                         std::vector<MoveRow>& rows) {
    std::mt19937_64 rng(options.seed + gameIndex * 0x9E3779B97F4A7C15ULL);
    std::vector<int> initialHands;
    MatchController controller = createFirstRound(mode, rng, initialHands);

    SearchEngine::Config configA;
    configA.maxDepthPlies = options.depth;
    configA.determinizationCount = options.determinizations;
    configA.timeLimitMs = options.timeMs;
    configA.endgameTileLimit = 8;
    configA.workerThreads = options.workers;
    configA.rootAggregation = options.aggregation;
    configA.maxVoluntaryDraws = options.voluntaryDraws;
    configA.weights = options.weights;

    SearchEngine::Config configB;
    configB.maxDepthPlies = options.opponentDepth;
    configB.determinizationCount = options.opponentDeterminizations;
    configB.timeLimitMs = options.timeMs;
    configB.endgameTileLimit = 8;
    configB.workerThreads = options.opponentWorkers;
    configB.rootAggregation = options.opponentAggregation;
    configB.maxVoluntaryDraws = options.opponentVoluntaryDraws;
    configB.weights = options.opponentWeights;

    // Alternate which physical side gets the A configuration so a one-sided
    // first-player advantage does not masquerade as a strength difference.
    const bool aIsFirstSide = (gameIndex % 2 == 0);
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
        if (arg == "--games" || arg == "--depth" || arg == "--determinizations" ||
            arg == "--opponent-depth" || arg == "--opponent-determinizations" ||
            arg == "--time-ms" || arg == "--workers" || arg == "--opponent-workers" ||
            arg == "--aggregation" || arg == "--opponent-aggregation" ||
            arg == "--voluntary-draw" || arg == "--opponent-voluntary-draw" ||
            arg == "--weights" || arg == "--opponent-weights" ||
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
                                   arg == "--voluntary-draw" || arg == "--opponent-voluntary-draw";
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
            continue;
        }
        std::cerr << "unknown argument: " << arg << "\n";
        usage(std::cerr);
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
              << "  output: " << outputPath << "\n";

    writeHeader(out);

    int completed = 0;
    int incomplete = 0;
    std::uint64_t totalDecisions = 0;
    for (int game = 0; game < options.games; ++game) {
        std::vector<MoveRow> rows;
        const GameSummary summary = playOneRound(options, mode, static_cast<std::uint64_t>(game), rows);
        writeRows(out, static_cast<std::uint64_t>(game), options.seed, mode, summary, rows);
        totalDecisions += static_cast<std::uint64_t>(summary.decisions);
        if (summary.outcome == RoundOutcomeKind::InProgress) ++incomplete;
        else ++completed;
        if ((game + 1) % 10 == 0 || game + 1 == options.games) {
            std::cout << "  finished " << (game + 1) << "/" << options.games
                      << " rounds (" << totalDecisions << " decisions)\n";
        }
    }

    std::cout << "wrote " << outputPath << "\n"
              << "  completed rounds: " << completed << "\n"
              << "  incomplete rounds: " << incomplete << "\n"
              << "  decisions: " << totalDecisions << "\n";
    return incomplete == 0 ? 0 : 1;
}
