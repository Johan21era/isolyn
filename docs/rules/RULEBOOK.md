# IsolynV2.0 — The Rulebook

> **Status: normative, tier 0 (2026-11-14).** Dictated by the owner on
> 2026-11-14 and transcribed here. This is the game. The engine, the bridge, the
> app, the tests and every other document are judged against it. Where code
> disagrees with this page, **the code is wrong**, and the disagreement is
> recorded as a gap until the code is fixed.

## 0. Provenance

The rules had never been written down in this repository. On 2026-11-14 the
owner dictated the ruleset from memory and answered six questions about the
places where the dictation contradicted itself. This page is the result. It
replaces every earlier rules description; the twelve ambiguity resolutions in
[`history/legacy-handoff.md`](../history/legacy-handoff.md) §5.3 are superseded
wherever they disagree with it.

The answers that settled the conflicts, in the owner's words:

> "if i have 40 points in my hand, and you win the hand... you're in the lead by
> 40, so i would explain it as 'it's 40-0 for john'."

> "the double blank counts as zero when it is paired with any other piece in
> play for who's holding it. if it is alone, it counts as 10."

> "the winner adds his opponent's pieces to his score. if it's 50-50, and you
> catch me with 43 points in my hand, it's now 93-50."

## 1. How a rule binds

Each rule carries an ID, a status, the code that enforces it, and the single
assertion that fails when the rule is broken. `scripts/rules_audit.py` refuses
the build when an enforced rule has no assertion, when an assertion does not
resolve to real text in a real test, when named code does not exist, when IDs
are duplicated or skipped, or when a declared gap is missing from Known gaps.

**To change a rule:** change this document first, then its assertion, then the
code. A change that edits only the code is a bug.

| Status | Meaning |
|---|---|
| `ENFORCED` | Implemented, with an assertion that fails if it stops being true. |
| `GAP` | The rule is settled; the app does not implement it yet. Must be listed in Known gaps. |
| `BY_HAND` | A rule of conduct between people. It is recorded here because it is part of the game, and deliberately not modelled in software. |

## 2. Vocabulary

- A **hand** is one deal, won either by emptying your hand or by closing.
- A **set** is a race to the target score: 151, or 101 in 1v1 by agreement.
- A **game** is the series of sets, won by taking three sets or four, whichever
  was chosen before play.

## 3. The rules

### A. Winning a hand and scoring it

| ID | Rule | Status | Enforced by | Asserted by |
|---|---|---|---|---|
| R-01 | There are three modes: 1v1, 1v1v1 and 2v2. | ENFORCED | `Sources/IsolynEngine/include/GameMode.hpp` | `Tests/IsolynEngineTests/MatchControllerTests.cpp :: dealFirstRound also works for 1v1v1 and 2v2` |
| R-02 | A hand is won in one of two ways: a standard win, by emptying your hand; or a close, where the hand is closed and the tallied points are compared. | ENFORCED | `Sources/IsolynEngine/MatchController.cpp` | `Tests/IsolynEngineTests/MatchControllerTests.cpp :: playTurn detects Domino victory when a player empties their hand` |
| R-03 | In 1v1 the higher hand loses the hand. The winner — the lower hand — is credited with the loser's total; the loser's score does not move. A standard win pays the same way: the winner adds the opponent's remaining pieces. A tie awards nobody, and the closer still starts the next hand. | ENFORCED | `Sources/IsolynEngine/RulesEngine.cpp` | `Tests/IsolynEngineTests/RulesEngineTests.cpp :: 1v1 Close: 24 vs 9 -> the lower hand (9) takes the 24` |
| R-04 | In 1v1v1 every player is for himself. The lowest hand adds nothing and every other hand adds its own total: closing with 6 against 12 and 41 scores 0-12-41. The closer pays too when his hand is above the lowest — 41 against 6 and 12 scores 0-6-41 — and closing exempts nobody. | ENFORCED | `Sources/IsolynEngine/RulesEngine.cpp` | `Tests/IsolynEngineTests/RulesEngineTests.cpp :: the closer is not exempt` |
| R-05 | In 2v2 the two partners' remaining values are combined into one team total, and the losing team's total is credited to the winners. A 0-6 with a partner's 6-4 is 16; losing to 21 pays the opponents 21. | ENFORCED | `Sources/IsolynEngine/RulesEngine.cpp` | `Tests/IsolynEngineTests/RulesEngineTests.cpp :: 2v2: lower combined (26) takes the opponent team's 27` |
| R-06 | A set is won at 151 points, which means reaching 151 loses the set. In 1v1 the two players may agree, before the game, to play the whole game to 101 instead; that choice covers every set. In 1v1v1 and 2v2, 151 is locked. | GAP | `Sources/IsolynEngine/include/RulesEngine.hpp` now locks all three modes at 151; the 101 option has no way to be chosen. | Needs the pre-game option. |
| R-07 | A game is won by taking three sets (3-0, 3-1, 3-2) or four sets (4-0 through 4-3). The two players agree the format before the game; scores reset to zero at the start of each set, and every set opens with the double-six ritual exactly as the game's first hand does. | ENFORCED | `Sources/IsolynEngineBridge/IsolynBridge.cpp` (`MatchStateImpl` set wins and reset), `Sources/IsolynApp/Engine/MatchCoordinator.swift` (format and next-set deal) | `Tests/IsolynEngineBridgeTests/SmokeTest.cpp :: set wins accumulate exactly one per completed set` |

### B. Dealing and opening

| ID | Rule | Status | Enforced by | Asserted by |
|---|---|---|---|---|
| R-08 | 1v1 deals 7 tiles to each player, leaving 14 in the boneyard. | ENFORCED | `Sources/IsolynEngine/Dealer.cpp` | `Tests/IsolynEngineTests/DealerTests.cpp :: 1v1 hand and boneyard sizes` |
| R-09 | 1v1v1 deals 9 tiles to each player, and the double blank is thrown out of the game for the entire duration of the mode. There is no boneyard. | ENFORCED | `Sources/IsolynEngine/Dealer.cpp` | `Tests/IsolynEngineTests/DealerTests.cpp :: 1v1v1 hand size, 0-0 removal, empty boneyard` |
| R-10 | 2v2 deals 7 tiles to each player, with no boneyard. | ENFORCED | `Sources/IsolynEngine/Dealer.cpp` | `Tests/IsolynEngineTests/DealerTests.cpp :: 2v2 hand and boneyard sizes` |
| R-11 | The first hand of a game is opened by the double six; failing that the double five, and so on down through the doubles. Doubles outrank every plain tile, so a double two opens before a 6-4. If nobody holds a double, the biggest plain tile opens. | ENFORCED | `Sources/IsolynEngine/RulesEngine.cpp` | `Tests/IsolynEngineTests/RulesEngineTests.cpp :: any double outranks every non-double` |
| R-12 | Only the first hand of a set has a mandated opening tile; that ritual restarts at the top of every set. Every later hand begins with an empty board. | ENFORCED | `Sources/IsolynApp/Engine/MatchCoordinator.swift` (nextRoundStartsSet -> createFirstRound), `Sources/IsolynEngine/MatchController.cpp` (dealFirstRound) | `Tests/IsolynEngineBridgeTests/SmokeTest.cpp :: every set opens with the double-six ritual, exactly like the game's first hand (R-12)` |
| R-13 | The player who wins or closes a hand starts the next one, and opens it with a tile of his choosing. Closing earns the start even when closing lost him the hand: in 1v1v1 the closer starts the next hand even when he held the highest total, and in every mode the closer starts regardless of the score. | ENFORCED | `Sources/IsolynEngine/MatchController.cpp` | `Tests/IsolynEngineTests/MatchControllerTests.cpp :: dealSubsequentRound leaves the chain empty` |

### C. Drawing

| ID | Rule | Status | Enforced by | Asserted by |
|---|---|---|---|---|
| R-14 | The player who starts a hand may never make the first draw of that hand — zero exceptions. Thereafter anyone may draw freely, including while holding a playable tile; that is the only restriction on drawing. | ENFORCED | `Sources/IsolynEngine/MatchController.cpp` | `Tests/IsolynEngineTests/MatchControllerTests.cpp :: the opener may not draw into an empty chain` |
| R-15 | Once the first draw has happened, a player may draw as many times as he likes in a turn, and on every turn after. | GAP | The analysis path caps a turn at one voluntary draw (`maxVoluntaryDraws = 1`). | Remove the cap. |
| R-16 | A player with no playable tile on either end must draw until he holds a playable tile or the boneyard is empty, then his turn ends without a play. | ENFORCED | `Sources/IsolynEngine/MatchController.cpp` | `Tests/IsolynEngineTests/MatchControllerTests.cpp :: resolveForcedDraw draws until a playable tile is found` |
| R-17 | Two boneyard tiles are locked. They are never drawn and never shown, except that a player who reaches exactly one tile while no other boneyard tiles remain may look at both privately — for his own recalibration, or not at all. The look is available every time those conditions are met, not once per hand. Looking changes nothing; they stay locked and the opponent never sees them. If only those two remain and nobody can play, the hand is an ordinary close. | ENFORCED | `Sources/IsolynEngine/GameState.cpp` (`privateLockedPair`), `Sources/IsolynEngineBridge/IsolynBridge.cpp` (seat-scoped read-only query), `Sources/IsolynApp/Game/Board/InteractiveGameBoardView.swift` (private overlay) | `Tests/IsolynEngineTests/GameStateTests.cpp :: R-17 private look returns the locked pair only to a one-tile hand with no drawable tiles` |
| R-18 | When both players hold exactly one tile and the boneyard still has pieces, each must take one piece when his turn starts, even if he could win right there. As soon as one player holds more than one piece, the other is released from that obligation: he may play his single tile instantly and does not have to draw. | ENFORCED | `Sources/IsolynEngine/GameState.cpp` (`enforceOneDominoRule`), `Sources/IsolynEngine/MatchController.cpp` (turn transition), `Sources/IsolynEngine/SearchEngine.cpp` (search nodes) | `Tests/IsolynEngineTests/GameStateTests.cpp :: One Domino Rule: both hands on one tile force a draw at turn start (1v1 only)` |

### D. Scoring a hand

| ID | Rule | Status | Enforced by | Asserted by |
|---|---|---|---|---|
| R-19 | A hand is worth the sum of its pips, except the double blank: held with any other tile it counts zero, and alone it counts ten. The rulebook's own tally: 4-3, 0-0 and 2-1 is 10. | ENFORCED | `Sources/IsolynEngine/RulesEngine.cpp` | `Tests/IsolynEngineTests/RulesEngineTests.cpp :: the rulebook's tally: 4-3 + 0-0 + 2-1 = 10` |
| R-20 | A standard win, with the hand emptied, pays exactly like a close: the winner adds the opponent's remaining total. 50-50 with the opponent caught holding 43 becomes 93-50. | ENFORCED | `Sources/IsolynEngine/RulesEngine.cpp` | `Tests/IsolynEngineTests/RulesEngineTests.cpp :: 1v1 Domino: the winner's empty hand is credited with the opponent's 22` |

### E. Conduct at the table

| ID | Rule | Status | Enforced by | Asserted by |
|---|---|---|---|---|
| R-21 | In 2v2, direct description of a hand is forbidden, but three exchanges are legal: asking a partner "how heavy are you" before a close and hearing "light" or "heavy"; agreeing which partner starts a later hand; and declaring "missing" — holding many of a number but not its double — or how many of a number one holds. | BY_HAND | Nothing: this is conduct between the people at the table. | Owner decision (2026-11-14): record the rule, leave the code untouched. |
| R-22 | In 1v1v1 a player who reaches 151 is out of the set. The two survivors continue that same set as a 1v1, keeping the points they already hold — 151-86-98 leaves 86 and 98 playing on under standard 1v1 rules — and the first of those two to reach 151 loses the set. The last man standing wins it. | GAP | Not implemented: no set structure exists at all. | Elimination and the carried-points duel. |

## Known gaps (must shrink, never grow)

Every `GAP` rule appears here. `scripts/rules_audit.py` fails if one is missing,
or if an entry names a rule that does not exist.

### R-06 — Choosing 101 instead of 151 in 1v1

The engine now locks all three modes at 151, which is correct for 1v1v1 and 2v2
and the default for 1v1. Offering 101 needs a decision at the start of a game
and a way to carry it into the score check; no UI or bridge field exists for it.

### R-15 — Unlimited draws in a turn

`Config::maxVoluntaryDraws` is 1, so the search and the app's own draw action
allow a single voluntary draw per turn. The rulebook allows any number once the
first draw of the hand has happened.

### R-22 — The 1v1v1 elimination

A 1v1v1 set does not end when the first player reaches 151; that player is out
and the other two play on as a 1v1 inside the same set, carrying their existing
points. Sets now exist, so this is no longer blocked: a 1v1v1 set currently ends
at 151 with the lowest score taking it, instead of eliminating the threshold-
crosser and continuing 1v1.

R-21 is no longer a gap: the owner ruled that table talk stays between the
players, and software does not police or mediate it.
