#include "MatchController.hpp"
#include "MoveExecutor.hpp"
#include "MoveGenerator.hpp"
#include "MoveValidator.hpp"
#include "RulesEngine.hpp"
#include <cassert>
#include <utility>

namespace isolyn {

MatchController MatchController::dealFirstRound(GameMode mode, EntropySource& entropy) {
    return MatchController(mode, Dealer::deal(mode, entropy));
}

MatchController MatchController::dealSubsequentRound(GameMode mode, EntropySource& entropy, int startingPlayerIndex) {
    DealResult dealt = Dealer::deal(mode, entropy);
    GameState state(mode, dealt.hands, dealt.boneyard);
    state.setCurrentPlayerIndex(startingPlayerIndex);
    return MatchController(std::move(state));
}

MatchController::MatchController(GameMode mode, DealResult dealt)
    : m_mode(mode), m_state(mode, dealt.hands, dealt.boneyard) {
    auto opening = RulesEngine::determineOpeningPlay(dealt.hands);
    // Side is irrelevant for an opening play -- GameState::playTile
    // ignores it and opens the chain regardless (same convention used
    // throughout Move System).
    m_state.playTile(opening.openingPlayerIndex, opening.openingTile, GameState::ChainSide::Left);
    m_state.setCurrentPlayerIndex((opening.openingPlayerIndex + 1) % m_state.playerCount());
}

MatchController::MatchController(GameState state)
    : m_mode(state.mode()), m_state(std::move(state)) {}

bool MatchController::currentPlayerHasLegalMove() const {
    return MoveGenerator::hasAnyLegalMove(m_state, m_state.currentPlayerIndex());
}

bool MatchController::canVoluntaryDraw() const {
    // The opener faces an empty chain, so they always hold a legal lead.
    // Drawing there is not a rules action: the opener must play.
    return !m_state.chain().isEmpty() && m_state.boneyard().drawableCount() > 0;
}

DominoTile MatchController::voluntaryDraw() {
    assert(canVoluntaryDraw() &&
           "the opener must play a tile; a draw requires a non-empty chain");
    return m_state.drawTile(m_state.currentPlayerIndex());
}

std::vector<DominoTile> MatchController::resolveForcedDraw() {
    assert(!currentPlayerHasLegalMove() &&
           "resolveForcedDraw should only be called when the current player has no legal move");
    int player = m_state.currentPlayerIndex();
    std::vector<DominoTile> drawn;
    while (!MoveGenerator::hasAnyLegalMove(m_state, player) && m_state.boneyard().drawableCount() > 0) {
        drawn.push_back(m_state.drawTile(player));
    }
    return drawn;
}

RoundOutcome MatchController::playTurn(const Move& move) {
    int player = m_state.currentPlayerIndex();
    assert(MoveValidator::isLegal(m_state, player, move) &&
           "playTurn requires an already-legal move; validate before calling");
    MoveExecutor::apply(m_state, player, move);

    if (m_state.hand(player).empty()) {
        return RoundOutcome{RoundOutcomeKind::DominoVictory, player};
    }

    advanceToNextPlayer();
    return checkForClose();
}

RoundOutcome MatchController::endTurnWithNoPlay() {
    advanceToNextPlayer();
    return checkForClose();
}

void MatchController::advanceToNextPlayer() {
    int next = (m_state.currentPlayerIndex() + 1) % m_state.playerCount();
    m_state.setCurrentPlayerIndex(next);
}

RoundOutcome MatchController::checkForClose() const {
    if (MoveGenerator::isPositionClosed(m_state)) {
        int closer = RulesEngine::determineCloser(m_mode, m_state.playHistory());
        return RoundOutcome{RoundOutcomeKind::Closed, closer};
    }
    return RoundOutcome{RoundOutcomeKind::InProgress, -1};
}

} // namespace isolyn
