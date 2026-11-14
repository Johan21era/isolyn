# IsolynV2.0 — The Rulebook

> **Status: normative, tier 0 (2026-11-14).** This document defines the game.
> Everything else in the repository — engine, bridge, app, tests, comments — is
> judged against it. Where code and this document disagree, **the code is
> wrong**.

## 0. Why this document exists

Until now there was no rulebook in this repository. The rules had been imported
from two external documents ("Rules Spec" and "Concept Spec") that were never
committed, and survived only as twelve ambiguity resolutions in
[`history/legacy-handoff.md`](../history/legacy-handoff.md) §5.3. The
consequence was structural, not accidental: the test suite was written by
reading the code, so every test agreed with the implementation, including its
mistakes. A blank tile worth zero points survived that way for months — no rule
said it was worth ten, so no test could fail.

That is the failure this document exists to make impossible.

## 1. How a rule is made binding

Each rule has an ID, a status, the code that enforces it, and **the one
assertion that fails when the rule is broken**. `scripts/rules_audit.py` reads
this table and refuses the build when:

- an ID is duplicated, skipped, or malformed;
- an `ENFORCED` or `VARIANT` rule has no assertion, or its assertion anchor does
  not resolve to a real file and a real test section;
- an `ENFORCED` rule names code that does not exist;
- a `GAP` or `OPEN` rule is not also listed under
  [Known gaps](#known-gaps-must-shrink-never-grow) — a hole in the rules may be
  visible, but it may not be silent.

**To change a rule:** edit this document first, then its assertion, then the
code. A change that edits only the code is, by definition, a bug — it makes the
implementation disagree with the rules on purpose.

**Status vocabulary**

| Status | Meaning |
|---|---|
| `ENFORCED` | Implemented, and an assertion fails if it stops being true. |
| `VARIANT` | A deliberate house variant, not a rules-spec rule. Same enforcement as `ENFORCED`. |
| `GAP` | We know the rule, and the app does not yet implement it. Must appear in Known gaps. |
| `OPEN` | The rule itself is undecided and needs an owner ruling. Must appear in Known gaps. |

## 2. The rules

| ID | Rule | Status | Enforced by | Asserted by |
|---|---|---|---|---|
| R-01 | The first round of a match is opened by the highest double held by any player. Any double, including the double blank, outranks every non-double. | ENFORCED | `Sources/IsolynEngine/RulesEngine.cpp` | `Tests/IsolynEngineTests/RulesEngineTests.cpp :: RulesEngine: highest double opens` |
| R-02 | If no player holds a double, the highest-value plain tile opens, value being the sum of pips. What to do when two tiles tie on that sum is unruled; the implementation opens with the first found. | ENFORCED | `Sources/IsolynEngine/RulesEngine.cpp` | `Tests/IsolynEngineTests/RulesEngineTests.cpp :: no doubles anywhere, highest value opens` |
| R-03 | Only the first round of a match has a mandated opening tile. Every later round starts with an empty chain, and the starter plays any legal tile. | ENFORCED | `Sources/IsolynEngine/MatchController.cpp` | `Tests/IsolynEngineTests/MatchControllerTests.cpp :: dealSubsequentRound leaves the chain empty` |
| R-04 | 1v1 deals 7 tiles to each player. The boneyard holds 14 tiles, of which 12 are drawable and the last 2 are locked. | ENFORCED | `Sources/IsolynEngine/Dealer.cpp` | `Tests/IsolynEngineTests/BoneyardTests.cpp :: 14-tile boneyard has 12 drawable` |
| R-05 | 1v1v1 deals 9 tiles to each player and removes the double blank from play entirely. There is no boneyard. | ENFORCED | `Sources/IsolynEngine/Dealer.cpp` | `Tests/IsolynEngineTests/DealerTests.cpp :: 1v1v1 hand size, 0-0 removal, empty boneyard` |
| R-06 | 2v2 deals 7 tiles to each player and has no boneyard. Teams are players 0 and 2 against players 1 and 3. | ENFORCED | `Sources/IsolynEngine/Dealer.cpp` | `Tests/IsolynEngineTests/DealerTests.cpp :: 2v2 hand and boneyard sizes` |
| R-07 | A deal is a Misdeal, and is redealt, when any hand has the wrong size, or when a 1v1 deal contains five or more doubles. | ENFORCED | `Sources/IsolynEngine/Dealer.cpp` | `Tests/IsolynEngineTests/DealerTests.cpp :: Misdeal -- five or more doubles, 1v1 only` |
| R-08 | A tile is legal exactly when one of its faces matches an open end of the chain. An empty chain accepts any tile of the player's hand, on either side. | ENFORCED | `Sources/IsolynEngine/MoveValidator.cpp` | `Tests/IsolynEngineTests/MoveSystemTests.cpp :: an empty chain accepts any hand tile, any side` |
| R-09 | Playing a double leaves both open ends at that double's pip value. | ENFORCED | `Sources/IsolynEngine/Chain.cpp` | `Tests/IsolynEngineTests/ChainTests.cpp :: attaching a double to a matching end keeps that end's value unchanged` |
| R-10 | Mandatory play: a player holding any legal move may not pass. | GAP | `Sources/IsolynEngine/MatchController.cpp` | `endTurnWithNoPlay` advances the turn with no check that the player was stuck. |
| R-11 | A player with no legal move draws until a playable tile appears or the boneyard is exhausted, then the turn passes with no play. | ENFORCED | `Sources/IsolynEngine/MatchController.cpp` | `Tests/IsolynEngineTests/MatchControllerTests.cpp :: resolveForcedDraw draws until a playable tile is found` |
| R-12 | The opener may not draw. An empty chain must be led with a tile. | ENFORCED | `Sources/IsolynEngine/MatchController.cpp` | `Tests/IsolynEngineTests/MatchControllerTests.cpp :: the opener may not draw into an empty chain` |
| R-13 | The boneyard's last two tiles stay locked until every other tile has been drawn. | ENFORCED | `Sources/IsolynEngine/Boneyard.cpp` | `Tests/IsolynEngineTests/BoneyardTests.cpp :: the locked pair becomes visible once drawableCount hits zero` |
| R-14 | Playing your last tile ends the round immediately. That player goes out. | ENFORCED | `Sources/IsolynEngine/MatchController.cpp` | `Tests/IsolynEngineTests/MatchControllerTests.cpp :: playTurn detects Domino victory when a player empties their hand` |
| R-15 | Once a round has ended, no further play or draw is accepted. | ENFORCED | `Sources/IsolynEngineBridge/IsolynBridge.cpp` | `Tests/IsolynEngineBridgeTests/SmokeTest.cpp :: submit_move refuses a finished round` |
| R-16 | The round closes when no player has a legal move and the boneyard cannot supply one. | ENFORCED | `Sources/IsolynEngine/MatchController.cpp` | `Tests/IsolynEngineTests/MatchControllerTests.cpp :: playTurn detects a Close when no player anywhere has a legal move` |
| R-17 | In 1v1 a double can never close a round: credit walks back through any run of consecutive doubles to the most recent non-double. | ENFORCED | `Sources/IsolynEngine/RulesEngine.cpp` | `Tests/IsolynEngineTests/RulesEngineTests.cpp :: 1v1 walks back through a whole run of doubles` |
| R-18 | In 1v1v1 and 2v2, doubles may close: the last player to move is credited. | ENFORCED | `Sources/IsolynEngine/RulesEngine.cpp` | `Tests/IsolynEngineTests/RulesEngineTests.cpp :: determineCloser -- doubles CAN close outside 1v1` |
| R-19 | Domino scoring: the player who went out adds nothing; every other participant adds the full point value of their remaining hand. | ENFORCED | `Sources/IsolynEngine/RulesEngine.cpp` | `Tests/IsolynEngineTests/RulesEngineTests.cpp :: 1v1 Domino: winner 0, opponent's full hand (22) added` |
| R-20 | Close scoring: the lowest hand adds nothing and every participant above it adds their own value. Participants tied at the lowest all add nothing. | ENFORCED | `Sources/IsolynEngine/RulesEngine.cpp` | `Tests/IsolynEngineTests/RulesEngineTests.cpp :: 1v1 Close, tied at 10: no points awarded to either side` |
| R-21 | A hand's point value is the sum of its pips, except the double blank, which is worth ten. | ENFORCED | `Sources/IsolynEngine/include/DominoTile.hpp` | `Tests/IsolynEngineTests/RulesEngineTests.cpp :: the double blank is worth ten points` |
| R-22 | 2v2 scores teams rather than players: the two partners' remaining values are combined into one value before scoring. | ENFORCED | `Sources/IsolynEngine/RulesEngine.cpp` | `Tests/IsolynEngineTests/RulesEngineTests.cpp :: 2v2 team combination: 20+6=26` |
| R-23 | A match ends when a score reaches or exceeds its threshold: 101 in 1v1 and 1v1v1, 151 in 2v2. | ENFORCED | `Sources/IsolynEngine/RulesEngine.cpp` | `Tests/IsolynEngineTests/RulesEngineTests.cpp :: hasReachedMatchLossThreshold -- reaches OR exceeds` |
| R-24 | The match winner is the participant holding the strictly lowest score when the match ends. | ENFORCED | `Sources/IsolynEngine/ScoreSystem.cpp` | `Tests/IsolynEngineTests/ScoreSystemTests.cpp :: winningParticipant is whoever has the strictly lowest score` |
| R-25 | The winner of a round — the Domino winner, or whoever was credited with the close — starts the next round. | ENFORCED | `Sources/IsolynEngine/RulesEngine.cpp` | `Tests/IsolynEngineTests/RulesEngineTests.cpp :: determineNextRoundStarter -- pass-through` |
| R-26 | The 1v1 One Domino Rule: when both players hold exactly one tile, each draws one before attempting to finish, continuing until someone wins, the boneyard is exhausted, or a player must draw more than one tile. | OPEN | Not implemented. | See Known gaps. |
| R-27 | A round in which every play was a double, and which closes, has no non-double to credit. | OPEN | `Sources/IsolynEngine/RulesEngine.cpp` falls back to crediting the last player. | See Known gaps. |
| R-28 | Voluntary draw is a house variant: a player may draw once from a non-empty chain, and the engine performs it only when the caller opts in. It is off by default. | VARIANT | `Sources/IsolynEngine/SearchEngine.cpp` | `Tests/IsolynEngineTests/SearchEngineTests.cpp :: voluntary drawing stays out of the tree by default and is a legal action when enabled` |

## Known gaps (must shrink, never grow)

Every `GAP` and `OPEN` rule is listed here. `scripts/rules_audit.py` fails if an
entry here names a rule that does not exist, or if a gap rule is missing from
this list.

### R-10 — Mandatory play is not enforced by the engine

`MatchController::endTurnWithNoPlay` advances the turn unconditionally. The rule
is currently upheld only because every caller happens to check
`currentPlayerHasLegalMove()` first. Any new caller — a sandbox, a loaded
position, a future protocol — can pass while holding a playable tile. Closing
this needs the controller to refuse the call, with the refusal surfaced through
the bridge as a status the app can show, not an `assert` that release builds
discard.

### R-26 — The One Domino Rule is not implemented

Deliberate. Both source documents describe a repeating draw-one-then-play-one
cycle while both players hold a single tile, and neither explains how a Domino
victory can occur inside it. Several readings were worked through; none was
clearly intended. Needs an owner ruling before code.

### R-27 — All-doubles closes are unruled

Both documents are silent. The engine credits whoever played last rather than
crashing or guessing further. This is a documented fallback, not a settled rule.

## 3. Rules that used to live only in code

- **R-21 (double blank = 10)** was discovered by the owner's live play on
  2026-11-14, not by a test: the appraisal summed pips, and the blank has none.
  Both the displayed hand value and the awarded points were wrong, and the one
  check that crossed the seam recomputed the same wrong sum — two copies of one
  mistake agreeing with each other. The assertion named in R-21 is the one that
  would have caught it.
