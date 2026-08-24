#pragma once

namespace isolyn {

// The three supported game modes (Rules Spec Sec. 2 / Concept Spec "Game
// Modes"). Its own tiny header rather than living inside Dealer or
// RulesEngine -- every subsystem from Dealer through ScoreSystem through
// the eventual UI needs to know which mode is in play, and none of them
// should have to depend on Dealer just to get this type.
enum class GameMode {
    OneVsOne,
    OneVsOneVsOne,
    TwoVsTwo
};

} // namespace isolyn
