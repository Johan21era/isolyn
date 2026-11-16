// The rulebook exam: score each engine mode on questions with objectively
// correct answers.
//
// `rules_audit.py` proves the engine implements every rule. This asks a harder
// question: does each difficulty tier *answer* rule-grounded questions correctly?
//
// Ground truth is never written by hand. For every position the exam enumerates
// the legal placements and computes by simulation which of them are correct:
//
//   WinNow      a placement empties the hand -> exactly those are right
//   WinWithDraw the same, with a voluntary draw on offer (R-15 vs R-02)
//   Defence     no winning move; right moves are those after which the opponent
//               cannot empty their hand (R-02 denial)
//
// A hand-authored answer would encode my assumptions. A simulated one encodes
// the rule the engine already implements, which is the standard being tested.
//
// Scoring is deliberately violent: correct = +1, wrong = 0, ILLEGAL = -5. One
// illegal move erases five correct answers, and the published score is
// 100 * max(0, correct - 5*illegal) / questions.
//
// Usage:
//   rulebook_test [--per-section 334] [--seed 7] [--modes 100,400,900,1600,2300,3000]

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <deque>
#include <iostream>
#include <random>
#include <sstream>
#include <string>
#include <vector>

#include "BeliefState.hpp"
#include "Chain.hpp"
#include "DifficultyModel.hpp"
#include "DominoTile.hpp"
#include "GameState.hpp"
#include "Move.hpp"
#include "MoveExecutor.hpp"
#include "MoveGenerator.hpp"
#include "MoveValidator.hpp"
#include "ProbabilityEngine.hpp"
#include "SearchEngine.hpp"

using namespace isolyn;

namespace {

enum class Kind {
    WinNow,
    WinWithDraw,
    Defence,
    SharpDefence,
    DefenceKnown,
    PoisonedWin,
    SafeWin
};

const char* kindName(Kind kind) {
    switch (kind) {
    case Kind::WinNow: return "win-now";
    case Kind::WinWithDraw: return "win+draw";
    case Kind::Defence: return "defence";
    case Kind::SharpDefence: return "sharp defence";
    case Kind::DefenceKnown: return "defence, all tiles known";
    case Kind::PoisonedWin: return "set-winning hand at 145 (R-06)";
    case Kind::SafeWin: return "win at 0 (R-06 control)";
    }
    return "?";
}

struct Setup {
    std::vector<std::vector<DominoTile>> hands;
    std::vector<DominoTile> boneyard;
    Chain chain;
};

Setup buildSetup(std::mt19937_64& rng, bool completeInfo = false) {
    std::vector<DominoTile> pool;
    for (int a = 0; a <= 6; ++a) {
        for (int b = a; b <= 6; ++b) pool.emplace_back(a, b);
    }
    std::shuffle(pool.begin(), pool.end(), rng);

    std::deque<DominoTile> played;
    const DominoTile first = pool.back();
    pool.pop_back();
    played.push_back(first);
    int leftEnd = first.low() < first.high() ? first.low() : first.high();
    int rightEnd = first.low() < first.high() ? first.high() : first.low();

    std::uniform_int_distribution<int> coin(0, 1);
    const int extra = 1 + coin(rng);
    for (int i = 0; i < extra; ++i) {
        const int want = coin(rng) ? leftEnd : rightEnd;
        bool found = false;
        for (std::size_t k = 0; k < pool.size(); ++k) {
            const DominoTile tile = pool[k];
            if (tile.low() != want && tile.high() != want) continue;
            pool.erase(pool.begin() + static_cast<std::ptrdiff_t>(k));
            const int other = tile.low() == want ? tile.high() : tile.low();
            if (want == leftEnd) {
                leftEnd = other;
                played.push_front(tile);
            } else {
                rightEnd = other;
                played.push_back(tile);
            }
            found = true;
            break;
        }
        if (!found) break;
    }

    std::uniform_int_distribution<int> handSize(1, 3);
    Setup setup;
    setup.hands.assign(2, {});

    if (completeInfo) {
        // Grow the chain until only a handful of tiles remain, then give the
        // opponent exactly one. With every tile visible their immediate win is
        // deducible, so a missed block is a mistake rather than a guess -- the
        // difference between measuring judgement and measuring clairvoyance.
        while (pool.size() > 6) {
            bool extended = false;
            for (std::size_t k = 0; k < pool.size(); ++k) {
                const DominoTile tile = pool[k];
                const bool atRight = tile.low() == rightEnd || tile.high() == rightEnd;
                const bool atLeft = tile.low() == leftEnd || tile.high() == leftEnd;
                if (!atRight && !atLeft) continue;
                pool.erase(pool.begin() + static_cast<std::ptrdiff_t>(k));
                if (atRight) {
                    rightEnd = tile.low() == rightEnd ? tile.high() : tile.low();
                    played.push_back(tile);
                } else {
                    leftEnd = tile.low() == leftEnd ? tile.high() : tile.low();
                    played.push_front(tile);
                }
                extended = true;
                break;
            }
            if (!extended) break;
        }
        setup.chain = Chain::fromKnownState(played, leftEnd, rightEnd);
        setup.hands[1].push_back(pool.back());
        pool.pop_back();
        while (!pool.empty()) {
            setup.hands[0].push_back(pool.back());
            pool.pop_back();
        }
        return setup;
    }

    setup.chain = Chain::fromKnownState(played, leftEnd, rightEnd);
    const int mine = handSize(rng);
    const int theirs = handSize(rng);
    for (int i = 0; i < mine && !pool.empty(); ++i) {
        setup.hands[0].push_back(pool.back());
        pool.pop_back();
    }
    for (int i = 0; i < theirs && !pool.empty(); ++i) {
        setup.hands[1].push_back(pool.back());
        pool.pop_back();
    }
    // Every one of the 28 tiles must be accounted for: chain + both hands +
    // boneyard. BeliefState asserts this, and rightly so -- a position that
    // loses tiles is not a position, and a question built on one would be
    // testing a state the engine can never actually meet.
    while (!pool.empty()) {
        setup.boneyard.push_back(pool.back());
        pool.pop_back();
    }
    return setup;
}

std::vector<Move> correctMoves(const GameState& state, Kind kind) {
    std::vector<Move> legal = MoveGenerator::generate(state, 0);
    std::vector<Move> correct;
    for (const Move& move : legal) {
        GameState trial = state;
        const auto applied = MoveExecutor::apply(trial, 0, move);
        const bool empties = trial.hand(0).empty();
        bool opponentWins = false;
        if (!empties) {
            trial.setCurrentPlayerIndex(1);
            std::array<Move, MoveGenerator::kMaxMoves> reply{};
            const std::size_t count = MoveGenerator::generateInto(trial, 1, reply);
            for (std::size_t i = 0; i < count; ++i) {
                GameState after = trial;
                MoveExecutor::apply(after, 1, reply[i]);
                if (after.hand(1).empty()) {
                    opponentWins = true;
                    break;
                }
            }
        }
        MoveExecutor::undo(trial, applied);

        if (kind == Kind::Defence || kind == Kind::SharpDefence ||
            kind == Kind::DefenceKnown) {
            if (!empties && !opponentWins) correct.push_back(move);
        } else if (empties) {
            correct.push_back(move);
        }
    }
    return correct;
}

// Everything neither in our hand nor on the board: the boneyard plus the
// opponent's tiles. With the opponent holding exactly one tile, a uniform prior
// over this pool is exactly right, which is what makes a Bayes baseline
// computable rather than a guess.
std::vector<DominoTile> unknownTiles(const GameState& state, int me) {
    std::vector<DominoTile> unknown;
    const auto& chain = state.chain().orderedTiles();
    for (int a = 0; a <= 6; ++a) {
        for (int b = a; b <= 6; ++b) {
            const DominoTile tile(a, b);
            bool excluded = false;
            for (const DominoTile& held : state.hand(me)) {
                if (held == tile) { excluded = true; break; }
            }
            if (!excluded) {
                for (const DominoTile& played : chain) {
                    if (played == tile) { excluded = true; break; }
                }
            }
            if (!excluded) unknown.push_back(tile);
        }
    }
    return unknown;
}

// Probability that the opponent's single hidden tile can be played on either end
// after this move. That is the exact chance of losing to an immediate win, so
// 1 - risk is what a perfect player maximises.
double bayesRisk(const GameState& state, const Move& move,
                 const std::vector<DominoTile>& unknown) {
    if (unknown.empty()) return 0.0;
    GameState trial = state;
    const auto applied = MoveExecutor::apply(trial, 0, move);
    const int left = trial.chain().leftEnd();
    const int right = trial.chain().rightEnd();
    MoveExecutor::undo(trial, applied);
    int playable = 0;
    for (const DominoTile& tile : unknown) {
        if (tile.low() == left || tile.high() == left ||
            tile.low() == right || tile.high() == right) {
            ++playable;
        }
    }
    return static_cast<double>(playable) / static_cast<double>(unknown.size());
}

// A position where the only legal placement empties the hand, so the hand is won
// the moment it is played. -1 means no set context (the ordinary sections).
Setup buildScoreSetup(std::mt19937_64& rng) {
    std::vector<DominoTile> pool;
    for (int a = 0; a <= 6; ++a) {
        for (int b = a; b <= 6; ++b) pool.emplace_back(a, b);
    }
    std::shuffle(pool.begin(), pool.end(), rng);
    std::uniform_int_distribution<int> pip(0, 6);

    auto take = [&pool](int a, int b) -> bool {
        const DominoTile tile(a, b);
        for (std::size_t i = 0; i < pool.size(); ++i) {
            if (pool[i] == tile) {
                pool.erase(pool.begin() + static_cast<std::ptrdiff_t>(i));
                return true;
            }
        }
        return false;
    };

    const int left = pip(rng);
    const int middle = pip(rng);
    const int right = pip(rng);
    if (!take(left, middle) || !take(middle, right)) return Setup{};

    int other = pip(rng);
    while (!take(left, other)) {
        other = pip(rng);
        if (pool.empty()) return Setup{};
    }

    Setup setup;
    std::deque<DominoTile> played{DominoTile(left, middle), DominoTile(middle, right)};
    setup.chain = Chain::fromKnownState(played, left, right);
    setup.hands.assign(2, {});
    setup.hands[0].push_back(DominoTile(left, other));

    // Give the opponent at least 8 points, so winning from 145 crosses 151.
    int total = 0;
    while (total < 8 && !pool.empty()) {
        setup.hands[1].push_back(pool.back());
        total += pool.back().low() + pool.back().high();
        pool.pop_back();
    }
    if (total < 8) return Setup{};

    while (!pool.empty()) {
        setup.boneyard.push_back(pool.back());
        pool.pop_back();
    }
    return setup;
}

struct Question {
    GameState state;
    Kind kind;
    std::vector<Move> correct;
    int myScore = -1;
    // Bayes baseline for the hidden-information defence questions: every legal
    // move's loss probability, and the best achievable safety (1 - min risk).
    std::vector<Move> legalMoves;
    std::vector<double> risks;
    double bestSafety = 1.0;
};

struct Tally {
    int correct = 0;
    int wrong = 0;
    int illegal = 0;
    int asked = 0;
};

std::string label(int strength) {
    const DifficultyProfile profile = DifficultyModel::profileForStrength(strength);
    std::ostringstream text;
    text << "s" << strength << " d" << profile.maxDepthPlies << "x"
         << profile.determinizationCount;
    return text.str();
}

} // namespace

int main(int argc, char** argv) {
    int perSection = 334;
    std::uint64_t seed = 7;
    // Control: with this off the score-aware sections are still asked, but the
    // engine is not told the set score. If the engine passes anyway the section
    // is measuring nothing.
    bool scoreAware = true;
    std::vector<int> modes{100, 400, 900, 1600, 2300, 3000, 5000, 10000};

    for (int i = 1; i < argc; ++i) {
        const std::string arg = argv[i];
        auto value = [&](int fallback) -> int {
            if (i + 1 >= argc) return fallback;
            return std::atoi(argv[++i]);
        };
        if (arg == "--no-score-context") scoreAware = false;
        else if (arg == "--per-section") perSection = value(perSection);
        else if (arg == "--seed") seed = static_cast<std::uint64_t>(value(static_cast<int>(seed)));
        else if (arg == "--modes") {
            modes.clear();
            std::string list = (i + 1 < argc) ? argv[++i] : "";
            std::stringstream stream(list);
            std::string item;
            while (std::getline(stream, item, ',')) {
                if (!item.empty()) modes.push_back(std::atoi(item.c_str()));
            }
        }
    }

    std::mt19937_64 rng(seed);
    std::vector<Question> questions;
    for (Kind kind : {Kind::WinNow, Kind::WinWithDraw, Kind::Defence, Kind::SharpDefence,
                      Kind::DefenceKnown}) {
        int gathered = 0;
        int attempts = 0;
        while (gathered < perSection && attempts < perSection * 800) {
            ++attempts;
            Setup setup = buildSetup(rng, kind == Kind::DefenceKnown);
            GameState state(GameMode::OneVsOne, setup.hands, setup.boneyard, setup.chain, {}, 0);
            const std::vector<Move> legal = MoveGenerator::generate(state, 0);
            if (legal.empty()) continue;
            std::vector<Move> correct = correctMoves(state, kind);
            if (correct.empty()) continue;
            // A question only discriminates if some legal move is wrong, and a
            // sharp question has at most one right answer to pick out of three
            // or more -- guessing must be punished, not rewarded.
            if (kind == Kind::Defence || kind == Kind::SharpDefence ||
                kind == Kind::DefenceKnown) {
                if (correct.size() >= legal.size()) continue;
                if (kind == Kind::SharpDefence &&
                    (correct.size() > 1 || legal.size() < 3)) continue;
            }

            Question question{state, kind, correct, -1, {}, {}, 1.0};
            if (state.hand(1).size() == 1) {
                const std::vector<DominoTile> unknown = unknownTiles(state, 0);
                double best = 2.0;
                for (const Move& move : legal) {
                    const double risk = bayesRisk(state, move, unknown);
                    question.legalMoves.push_back(move);
                    question.risks.push_back(risk);
                    best = std::min(best, risk);
                }
                question.bestSafety = 1.0 - (best > 1.0 ? 1.0 : best);
            }
            questions.push_back(question);
            ++gathered;
        }
    }

    // Score-aware sections: the same position judged twice. At 145 the win
    // crosses 151 and loses the set, so the only correct answer is not to take
    // it; at 0 the identical position must be won. The pair is the control that
    // stops an engine that simply refuses to win from passing.
    {
        int gathered = 0;
        int attempts = 0;
        while (gathered < perSection && attempts < perSection * 400) {
            ++attempts;
            Setup setup = buildScoreSetup(rng);
            if (setup.hands.size() != 2 || setup.hands[0].empty()) continue;
            GameState state(GameMode::OneVsOne, setup.hands, setup.boneyard, setup.chain, {}, 0);
            const std::vector<Move> legal = MoveGenerator::generate(state, 0);
            if (legal.empty()) continue;
            bool winsNow = false;
            for (const Move& move : legal) {
                GameState trial = state;
                const auto applied = MoveExecutor::apply(trial, 0, move);
                if (trial.hand(0).empty()) winsNow = true;
                MoveExecutor::undo(trial, applied);
            }
            if (!winsNow) continue;
            questions.push_back(Question{state, Kind::PoisonedWin, {}, 145, {}, {}, 1.0});
            questions.push_back(Question{state, Kind::SafeWin, {}, 0, {}, {}, 1.0});
            ++gathered;
        }
    }

    std::cout << "rulebook exam: " << questions.size() << " questions, seed " << seed
              << ", one question scores +1, a wrong answer 0, an illegal move -5\n\n";

    for (int mode : modes) {
        const DifficultyProfile profile = DifficultyModel::profileForStrength(mode);
        SearchEngine::Config config;
        config.maxDepthPlies = profile.maxDepthPlies;
        config.determinizationCount = profile.determinizationCount;
        config.useSelectiveSearch = profile.maxDepthPlies >= 24;

        std::mt19937_64 searchRng(seed + static_cast<std::uint64_t>(mode));
        Tally byKind[7];
        int illegalTotal = 0;
        int correctTotal = 0;
        // Bayes comparison, on the hidden-information defence questions only.
        double achievedSafety = 0.0;
        double bestSafety = 0.0;
        int bayesAsked = 0;

        for (const Question& question : questions) {
            SearchEngine::Config effective = config;
            // The draw is on offer only in the section that tests it.
            effective.maxVoluntaryDraws =
                question.kind == Kind::WinWithDraw ? SearchEngine::kUnlimitedVoluntaryDraws : 0;
            if (scoreAware && question.myScore >= 0) {
                effective.setScores = {question.myScore, 0};
                effective.raceTarget = 151;
                effective.maxVoluntaryDraws = SearchEngine::kUnlimitedVoluntaryDraws;
            }

            BeliefState belief = ProbabilityEngine::constructFromGameState(question.state, 0);
            const SearchDecision decision = SearchEngine::chooseBestMove(
                question.state, belief, GameMode::OneVsOne, effective, searchRng, nullptr);

            Tally& tally = byKind[static_cast<int>(question.kind)];
            ++tally.asked;
            const bool legal = MoveValidator::isLegal(question.state, 0, decision.move);
            if (!legal) {
                ++tally.illegal;
                ++illegalTotal;
                continue;
            }
            bool right = false;
            if (question.kind == Kind::PoisonedWin || question.kind == Kind::SafeWin) {
                // R-06 (rules version 2): crossing the target WINS the set, so
                // taking the hand is correct at 145 exactly as it is at 0.
                GameState trial = question.state;
                const auto applied = MoveExecutor::apply(trial, 0, decision.move);
                right = trial.hand(0).empty();
                MoveExecutor::undo(trial, applied);
            } else {
                right = std::find(question.correct.begin(), question.correct.end(),
                                  decision.move) != question.correct.end();
            }
            if (right) {
                ++tally.correct;
                ++correctTotal;
            } else {
                ++tally.wrong;
            }

            if (!question.risks.empty()) {
                ++bayesAsked;
                bestSafety += question.bestSafety;
                double chosenRisk = 1.0;
                for (std::size_t i = 0; i < question.legalMoves.size(); ++i) {
                    if (question.legalMoves[i] == decision.move) {
                        chosenRisk = question.risks[i];
                        break;
                    }
                }
                achievedSafety += 1.0 - chosenRisk;
            }
        }

        const int total = static_cast<int>(questions.size());
        const double raw = static_cast<double>(correctTotal - 5 * illegalTotal);
        const double score = std::max(0.0, 100.0 * raw / std::max(1, total));

        std::cout << label(mode) << "  score " << static_cast<int>(score) << "/100"
                  << "   correct " << correctTotal << "/" << total
                  << "   wrong " << (total - correctTotal - illegalTotal)
                  << "   illegal " << illegalTotal << "\n";
        for (int k = 0; k < 7; ++k) {
            const Tally& tally = byKind[k];
            if (tally.asked == 0) continue;
            const double section =
                100.0 * static_cast<double>(tally.correct) / static_cast<double>(tally.asked);
            std::cout << "    " << kindName(static_cast<Kind>(k)) << ": "
                      << static_cast<int>(section) << "% of " << tally.asked
                      << " (wrong " << tally.wrong << ", illegal " << tally.illegal << ")\n";
        }
        if (bayesAsked > 0) {
            const double achieved = 100.0 * achievedSafety / bayesAsked;
            const double best = 100.0 * bestSafety / bayesAsked;
            std::cout << "    safety vs Bayes: achieved " << static_cast<int>(achieved)
                      << "% of " << bayesAsked << "   best achievable "
                      << static_cast<int>(best) << "%   gap "
                      << static_cast<int>(best - achieved) << " points\n";
        }
        std::cout << "\n";
    }
    return 0;
}
