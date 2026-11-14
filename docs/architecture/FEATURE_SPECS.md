# Feature Specifications — Training Mode and Sandbox Mode

> **Status: product intent, unimplemented (verified 2026-11-13).** Neither mode
> exists: both entry points render "This part of Isolyn hasn't been built yet"
> (`EntryView.swift:51,54`). `PositionConstructor` and `ExplanationEngine` have
> zero implementation. This is the specification those builds must satisfy —
> not a description of the current app.

> Captured from detailed feature requirements given well ahead of the UI
> layer being built. Same purpose as STRATEGY_NOTES.md: this is real,
> specific product intent that would otherwise have to be re-derived or
> re-explained once the Swift/SwiftUI layer actually starts, possibly
> many sessions from now. Kept in a separate file deliberately -- this is
> UX/feature specification, not game-domain strategy knowledge.

## Training Mode

A puzzle mode, not a strength-ladder mode. Core loop:

- A position is randomly generated, mid-game (not a fresh deal), in any
  of the three game modes (1v1, 1v1v1, 2v2) -- the app generates hands,
  scores, and full game state consistent with being partway through a
  real match.
- There is a single correct move (or an acceptable correct set) for that
  position, which the app must actually know with confidence -- this
  makes Training mode a downstream consumer of SearchEngine (to
  determine the correct answer) and ExplanationEngine (not yet built),
  not something buildable on EvaluationEngine alone.
- User selects game mode and puzzle difficulty before a puzzle is
  generated.

### Wrong-move handling
- The attempted piece is highlighted red and shakes, then is returned to
  the player's hand -- the move is rejected, not silently allowed.
- A text explanation appears in a box in the middle of the screen,
  explaining WHY the move was wrong and what it would have led to had it
  actually been played in a real game -- a real consequence explanation,
  not just "incorrect."

### Correct-move handling
- Same middle-screen text box, explaining why the move is correct and
  its consequences.
- Explanation register, both cases: "very simple but deep... contextual
  reasoning" -- accessible plain language carrying real domain insight,
  not a shallow restatement. Squarely ExplanationEngine's job once it
  exists, and needs whatever it produces to be genuinely tunable for a
  "simple but deep" register, not a dump of evaluation numbers.

### Visual design
- Described explicitly as: as if Apple themselves designed it --
  extremely simple, clean, minimal. A direct design-language target for
  whichever future SwiftUI view implements this (a
  TrainingModeView/PuzzleView, not yet named in the file plan).

## Sandbox Mode

Distinct from Training -- no puzzle, no single "correct answer" to find.

- Freely generate/construct a custom position (not necessarily a random
  deal) and play against the engine from there. This is
  PositionConstructor's job (already named in the file plan, not yet
  built) -- position setup needs to support arbitrary, user-specified
  starting states, not just Dealer's random deals.
- A live, "duplicate engine" evaluation display runs alongside play --
  an eval-bar/number style readout, continuously updated.
  EvaluationEngine's existing breakdown-based design (mobility/blocking/
  expectedValue/closingOpportunity as separate, inspectable components,
  not one opaque number) is a direct fit for this and shouldn't need
  rework to serve it.
- Move-by-move analysis of the user's own play: what a given move leads
  to, presumably compared against what the engine would have preferred
  -- another ExplanationEngine consumer.
- Engine strength for the opponent should be user-selectable --
  DifficultyModel territory (not yet built).

## Cross-cutting implications worth flagging now

- Both modes need position CONSTRUCTION beyond Dealer's random full
  deal -- Training needs "a plausible mid-game state," Sandbox needs
  "whatever the user specifies." PositionConstructor is the shared
  answer to both, worth prioritizing accordingly once UI work starts
  rather than treating it as minor infrastructure.
- Both modes are fundamentally explanation-consumers. ExplanationEngine's
  design should be driven by these two concrete use cases (a rejected
  move's consequence; a live position's "why") rather than designed in
  the abstract first.
- "Puzzle difficulty" (Training) and "engine strength" (Sandbox/general
  play) are related but not obviously identical concepts -- worth
  treating as a real open question for DifficultyModel's eventual design
  rather than assuming they're the same dial.
