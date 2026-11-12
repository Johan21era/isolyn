# Isolyn UI/UX Overhaul — The Table

**Status:** design charter / Phase 0, with the responsive shell and the
Offsuit-minimal table and motion/reveal pass landed

**Scope:** the three engine-backed modes — Duel (1v1), Three-Way (1v1v1),
Partners (2v2) — plus the entry/lobby surfaces that lead into them.
**Not in this pass:** implementing Training or Sandbox puzzles, new engine
features, new game rules, or changing the bridge ABI.

This document deliberately supersedes the *composition* rules in
`dominoes_ui_fix_non_negotiable.md`. The tile-construction laws in that
document remain non-negotiable: one continuous rectangle, exact 2:1 geometry,
an internal divider, canonical pips, and one interaction target per tile. The
old five-row dashboard is what we are replacing.

---

## 0. Design correction — Offsuit-minimal (2026-11-12)

The owner supplied a mobile poker reference (*Offsuit*) and made the target
explicit: **erase everything until the play surface has that level of
simplicity.** This correction supersedes §3–§8 wherever those sections call
for cards, panels, mode wireframes, seat cards, score chips, telemetry, or
multiple simultaneous controls. The tile laws and the engine/bridge
constraints still stand.

What the play surface must be:

- A true black field, edge to edge. No atmospheric background, elevated
  panel, border, or divider competes with the pieces.
- One quiet player row: small identity mark, name, score, and hand count.
  A centered strip immediately below it shows every seat other than the
  requesting player as a row of identical face-down backs, one per tile,
  labelled by seat. Keeping this outside the avatar cells preserves the
  symmetry of the 1v1 seats while an opponent's hand grows. The set only ever
  receives the snapshot's hand size, never tile identities, so the row can
  show that an opponent went from six to seven pieces after a draw without
  revealing what the new piece is. The acting seat is the only seat at full
  brightness.
- Dominoes face up and stay upright. No rotation, skew, perspective, or
  face-down treatment. They are the largest objects on screen: **48pt
  half-axis hand tiles, 38pt half-axis table tiles**, still exact 2:1.
- The chain centers on its visible domino geometry, never on endpoint tap
  targets. Playable ends are a thin ivory tick just outside the end tile —
  dim when available, slightly brighter only for a selected legal tile. No
  brass rings, pip badges, pulses, or filled circles on the board.
- Unplayable dominoes keep their full ivory face. They lose the playable
  outline; they are never faded or blacked out. Disabled-button styling must
  not dim them either.
- One primary action lane at the bottom: Draw when drawing is legal, Pass
  when the turn is forced, with Analyze as a small secondary control.
- A single short status chip, like the reference's `Pair` chip. No turn
  banner, mode label, score cards, opponent-count strip, reset-view button,
  or clock.
- The board is the center. The hand is the foreground. Nothing else gets a
  card or a container.
- Match setup follows the same language: black field, one title, three compact
  mode choices, an inline opponent control, and one Start action, centered
  vertically at every supported window size. No atmospheric stars, eyebrow
  labels, long card copy, or wooden/brown panels.
- The number-family inspector is explicit, not ambient. Auto-hover is **off
  by default** and is only a persisted Settings option. The default trigger is
  **right-click while over a domino**; Settings can swap that to middle click
  or an extra mouse button. Left click is reserved for play and is never
  offered as an inspection trigger. The inspector is a small **360pt black
  card** at the top right with one seven-domino family row, not a full-width
  brown panel.

### Motion and the end-of-round contract

- The table never jumps from one engine state to the next without a beat.
  Computer turns open with a short think pause; forced draws and the decision
  to play are separated by small waits. This is presentation pacing, not an
  engine delay, and it must remain cancellable.
- A draw is physical: face-down dominoes lift off the **actual draw pile**
  and travel to the hand or the acting seat, with a lifted arc and a quiet
  landing. Hand tiles rise into place and board tiles settle with a quiet
  spring. No confetti, screen shake, or new chrome.
- The 1v1 draw pile is a real table object, not a counter and not a stack.
  All remaining tiles lie face down in one straight row. The two permanently
  closed tiles occupy the left end behind a thin rail; the open draw end is
  the right edge. A draw removes the rightmost tile, so the row shrinks toward
  the closed pair while its left edge stays fixed. The closed pair remains
  face down for the whole round; the engine's late identity reveal is strategy
  data, never a reason to turn physical table tiles face up. The row shows the
  exact number of **drawable** tiles and labels the two ends `CLOSED` and
  `DRAW N`. Three-Way and Partners deal the complete set, so they show no
  pile. The existing `Draw`/`Pass` control stays in the action lane; the pile
  never replaces it.
- Consecutive forced draws keep overlapping flights alive instead of replacing
  one another, so every draw gets its own departure. The pile compresses a
  few points as each tile leaves and settles back with a restrained spring.
  On the same snapshot update, the acting opponent's face-down hand row gains
  a back (or loses one on a play), so a draw is visible as a change in the
  physical hand even when the face itself stays hidden.
- Hidden information stays hidden until the round is terminal. The only
  identity reveal is the end-of-round hand reveal: the bridge exposes the
  actual remaining tiles only when `roundOutcome != inProgress`, and the
  round-end card turns them face up, seat by seat, after a deliberate pause.
  The winner's empty hand is shown as `Went out`; a closed round shows every
  counted hand. Animation must never become a side channel for opponent tiles.
- The round-end card stages its headline, hands, score deltas, and next-round
  action rather than appearing as a static table. Opponent pieces are the
  point of this screen; do not reduce it to pip totals again.


The mode-native wireframes in §5 are retained only as a record of the earlier
direction. Do not use them to reintroduce chrome. Mode identity now comes
from the player row and the engine's seat/team state, not from a dashboard.

---

## 1. Verdict

The current screens are a competent engineering harness presented as a game.
They are not a product yet.

The board is the only distinctive object, but it is rendered at 26pt half-axis
(52×26pt) while the surrounding chrome, technical labels, and empty space take
more attention. A first-time player cannot answer these questions at a glance:

- Which mode am I playing, and what is the shape of the table?
- Which seat is mine, which seats are partners, and who acts next?
- What is the score for my team versus the other team?
- What just happened on the board?
- How do I leave, pause, or get help?

The fix is not a new coat of paint. The information architecture, the mode
layouts, and the interaction model all need replacement.

---

## 2. What exists today

### Entry and mode selection

- `EntryView` is a wordmark, one Play button, and two dead-end links
  (`Training`, `Sandbox`) that open `ComingSoonView`.
- `ModeSelectorView` offers three equal cards, a Hot Seat/Computer segmented
  control, a strength menu, and a Start button. It never previews the actual
  seating or turn order of the selected mode.
- `MatchFormat` is a presentation-only enum. It is mapped correctly to the
  engine elsewhere, but it carries no player/seat/team identity.
- The environment sky/weather is a continuous background behind every screen.
  The game screen then paints opaque ebony over it, so the atmospheric world
  disappears exactly when the player enters a match.

### Game screen

`InteractiveGameBoardView` is a vertical stack: header, board, action bar,
hand, status strip.

- Header: `1V1 · VS COMPUTER`, `Player 2's turn`, two score chips, and a clock.
  It reads like telemetry, not a match broadcast.
- Board: the snake chain is correct and is the strongest existing system, but
  the tiles are too small. Playable ends are marked by 34pt rings; the player
  must select a hand tile and then find and click the correct ring.
- Action bar: Draw, Analyze, Reset View, Pass. Analyze is an always-visible
  engineering feature; Reset View is a camera utility, not a game action.
- Hand: a single HStack of 34pt-half-axis tiles. It is readable, but it is not
  a hand *tray*: no grouping, no last-move relationship, no drag affordance.
- Status: `P1 5`-style opponent counts, a centered hint, and a painted-over
  120pt spacer used to fake centering. This is the debug-language problem in
  miniature.
- There is no pause, no menu, no exit, no rules/help, no move history, and no
  last-move highlight.
- `RoundEndOverlay` is a generic centered modal. It says "Player N" even in
  2v2 and shows values, but not the running match story.
- Appearance settings are reached through a floating paintbrush at the right
  edge, which reads as a developer tool.

### Mode-specific gaps

| Mode | What the UI says now | What the player needs |
|---|---|---|
| Duel | Two generic score chips | A clear head-to-head table, opponent identity, turn exchange |
| Three-Way | Three score chips after the match starts | Three visible seats, turn order, who is next, independent scores |
| Partners | "TEAM A / TEAM B" text | Partner identity, team lanes, team score, partner hand count |

### Data and test coverage

- `GameSnapshot` exposes the board, hand, hand sizes, scores, legal moves, and
  outcome, but not play history or the last move. A first pass can track the
  last submitted move in `GameViewModel`; a move list needs a bridge addition
  later.
- There is no round number in the UI state. It can be tracked locally.
- App tests cover engine/session behavior and board layout, but not seat
  presentation, navigation, or visual states. The overhaul should add pure
  presentation-model tests rather than brittle pixel tests.

---

## 3. Product direction: The Table

**One sentence:** Isolyn should feel like sitting at a beautifully made
domino table with three distinct table shapes, not like operating a game
engine.

### Principles

1. **The pieces are the interface.** The board and hand are the largest,
   warmest, highest-contrast objects. Chrome recedes.
2. **Every mode has a spatial identity.** Duel is a line, Three-Way is a
   triangle, Partners is two sides of a table. The layout itself explains the
   mode.
3. **The active seat is unmistakable.** Color is never the only signal; an
   active seat also has a label, a marker, and motion.
4. **One primary action.** Draw, pass, or place is the obvious next action.
   Analyze is a coach, not a permanent toolbar button.
5. **No dead ends.** Back, pause, rules, and exit are always reachable.
6. **Physical calm.** Small, purposeful motion. No bouncing, confetti, or
   decorative particles in the play surface.
7. **Honest UI.** Do not show a setting the engine cannot honor, a mode that
   cannot start, or a score that is not real.

### Keep

- `IsolynDominoTile` geometry and pip renderer.
- `SnakeChainLayout` serpentine placement, auto-fit, and camera bounds.
- `BoardCamera`, `GestureArbiter`, `HoverChainController`.
- `GameViewModel` engine orchestration, `EngineSession`, `MatchCoordinator`.
- `AppearanceManager` and custom domino appearances.
- `EnvironmentView` as the world outside the table.

### Replace

- `ModeSelectorView` and `ModeCard`.
- The `InteractiveGameBoardView` composition.
- `HandRackView` as a bare row.
- `RoundEndOverlay`.
- The floating brush control and the action-bar Analyze/Reset View hierarchy.
- The header/status strip information architecture.

---

## 4. Screen flow

```text
Entry
  ├─ Play ──────────────► Match Lobby
  ├─ Practice ──────────► Training / Sandbox (honest in-development sheet)
  ├─ How to Play ───────► Rules sheet
  └─ Settings ──────────► Settings sheet

Match Lobby
  ├─ choose mode ───────► mode preview + seating diagram
  ├─ choose opponent ───► Pass & Play / vs Computer
  ├─ choose strength ───► only when vs Computer
  └─ Start Match ───────► Game Table

Game Table
  ├─ Menu (Esc) ────────► Resume / Rules / Appearance / Exit to Lobby
  ├─ Coach ─────────────► analysis sheet, never a permanent toolbar item
  ├─ Round end ─────────► Round Scorecard
  └─ Match end ─────────► Match Result

Round Scorecard ────────► Next Round / Match Result
Match Result ───────────► Rematch / Change Mode / Lobby
```

The environment world remains visible in Entry and Lobby. Entering a match
transitions to a dedicated table surface: the environment recedes to the room
around the table, and the play surface becomes a warm, low-contrast felt. This
keeps the product's atmosphere without letting weather compete with the board.

---

## 5. Mode-native game layouts

All modes share the same shell:

- **Match header:** back/menu, mode name, round, scoreboard, settings.
- **Table stage:** the board plus seat cards, with the current actor marked.
- **Hand dock:** the player's hand, contextual instruction, and action dock.
- **Coach:** an optional sheet for engine analysis.
- **Menu:** pause, rules, appearance, exit.

### Duel (1v1)

```text
┌──────────────────────────────────────────────────────────────┐
│ ←   DUEL · ROUND 1                  YOU 0   :   0 RIVAL   ☰  │
├──────────────────────────────────────────────────────────────┤
│                     [ RIVAL · 5 tiles ]                      │
│                                                              │
│                ╭──────── table ────────╮                     │
│                │      chain here       │                     │
│                ╰───────────────────────╯                     │
│                                                              │
│  [ YOU · 5 tiles ]                             [ DRAW ]      │
├──────────────────────────────────────────────────────────────┤
│  YOUR HAND     [6-5] [4-3] [2-1] ...        [ PASS ]        │
└──────────────────────────────────────────────────────────────┘
```

- Opponent card top center, your seat anchored bottom left.
- Score is a single head-to-head line, not two unrelated chips.
- The hand is the widest bottom object; the action dock sits at its right.
- The board feels like a shared table, not a canvas between two toolbars.

### Three-Way (1v1v1)

```text
┌──────────────────────────────────────────────────────────────┐
│ ←   THREE-WAY · ROUND 1       2 ── 3 ── 1        ☰          │
├──────────────────────────────────────────────────────────────┤
│  [ RIVAL A · 4 ]                              [ RIVAL B · 6 ]│
│                                                              │
│                 ╭─────── table ───────╮                      │
│                 │      chain here     │                      │
│                 ╰─────────────────────╯                      │
│                                                              │
│  [ YOU · 3 ]                                  [ DRAW ]       │
├──────────────────────────────────────────────────────────────┤
│  YOUR HAND     [6-5] [4-3] [2-1] ...        [ PASS ]        │
└──────────────────────────────────────────────────────────────┘
```

- Three seat cards physically surround the table: two rivals above, you below.
- A turn-order ribbon (`2 → 3 → 1`) shows the cycle and highlights the actor.
- Each seat card carries its own score and hand count; no `P1 5` strip.
- Three-Way must never look like a 1v1 with an extra score chip.

### Partners (2v2)

```text
┌──────────────────────────────────────────────────────────────┐
│ ←   PARTNERS · ROUND 1       TEAM A 0   :   0 TEAM B    ☰   │
├──────────────────────────────────────────────────────────────┤
│  TEAM A                         TABLE                TEAM B  │
│  ┌──────────┐                                      ┌────────┐│
│  │ YOU   5  │           ╭────────────╮             │ RIVAL A││
│  │ PARTNER 4│           │ chain here │             │ 6      ││
│  └──────────┘           ╰────────────╯             │ RIVAL B││
│                                                     │ 5      ││
│  [ YOUR HAND ]                                      └────────┘│
│  [6-5] [4-3] ...                                  [ DRAW ]    │
└──────────────────────────────────────────────────────────────┘
```

- Team A is always the human's team, anchored left/bottom.
- Partner is explicitly labeled and visually linked to the human seat.
- Team B seats share a distinct team accent and are grouped on the right.
- Team score is the primary score; individual hand counts remain visible.
- At narrow widths, the two rails collapse into a top seat strip with team
  grouping preserved.

### Seat card

Every mode uses the same component:

- seat accent bar / avatar monogram;
- name (`You`, `Partner`, `Rival A`, `Rival B`, or hot-seat player name);
- role (`You`, `Partner`, `Opponent`);
- hand count;
- score;
- state: `Playing`, `Waiting`, `Thinking`, `Out`;
- non-color state marker (dot, label, or icon).

The card is the single source of player truth. No other `P1`/`P2` labels.

---

## 6. Visual system

### Palette

Keep the existing bone/ebony/brass identity, but give the play surface a
material of its own.

| Token | Value | Use |
|---|---|---|
| `felt` | `#0B1512` | table surface |
| `feltRaised` | `#12201C` | seat cards / hand tray |
| `bone` | `#F2E9D8` | dominoes, primary text |
| `ink` | `#14110D` | pips, text on brass |
| `brass` | `#C9A25A` | primary action / active turn |
| `brassMuted` | `#8C6F3E` | inactive accent |
| `jade` | `#67B7A6` | Team A / partner link |
| `terracotta` | `#D47A5E` | Team B / opposing team |
| `danger` | `#D65C5C` | rejected/invalid |
| `textMuted` | bone at 56% | secondary labels |
| `line` | bone at 12% | rails and separators |

No team color is applied to the domino faces themselves. Team identity lives
in the seat rails, table edge, and scoreboard, so the pieces remain canonical.

### Typography

- Display: SF Pro Display semibold, 44–56pt, only on entry/result.
- H1: 30–34pt, mode/result titles.
- H2: 20–24pt, round scorecards.
- Title: 16–18pt, seat names.
- Body: 14–15pt.
- Label: 10–11pt, uppercase tracking 1.5.
- Numeric: SF Pro, monospaced digits, 20–28pt for scores.

No text below 11pt in the play surface.

### Spacing and shape

- Spacing scale: 4, 8, 12, 16, 24, 32, 40.
- Radii: 8 (chips), 12 (seat cards), 18 (table), 28 (capsule).
- Elevation: table inner shadow, seat cards one step above felt, modals above.
- Use one-pixel rails and dividers, not heavy borders.

### Domino scale

- Board: `tileShortAxis = 32` (64×32), up from 26.
- Hand: `tileShortAxis = 38` (76×38), up from 34.
- Perpendicular doubles use the same 4pt visual gap as flat tiles. The chain
  advances by the actual half-widths of adjacent tiles, not a full horizontal
  cell, so a vertical double does not leave half a cell of dead air around it.
- End markers: 40pt, with a larger hit target.
- Selected lift: 8pt, render-only; no reflow.
- Last move: semantic edge plus a short settle animation.
- On small windows, scale the board before shrinking the hand.

---

## 7. Interaction model

### Selection and placement

- Click/tap a tile to select it. Legal ends are highlighted on the board.
- Click/tap a legal end to place it.
- Click the selected tile again to deselect.
- If exactly one legal placement exists, clicking the selected tile again
  places it.
- Drag a hand tile directly onto a legal end. The tile lifts out of the rack
  and follows the pointer; a release inside an end target plays it, while a
  release anywhere else leaves the tile selected for the tap path. Pointer
  updates are isolated from board layout so the drag stays smooth.
- Double-click a hand tile to play it without choosing an end when the choice
  is genuinely equivalent: it has one legal side, or both open ends show the
  same number and the tile fits both. In the matching-end case the engine-
  equivalent side is chosen at random. When the two open ends differ, a
  double-click never guesses at a strategic left/right choice.
- End targets are forgiving, not pixel tests: a **96pt invisible hit box**
  plus **32pt of drop padding** around each end, with the nearest end winning
  when the zones overlap. Dropping on the end domino itself should count.
- Invalid drop/click: tile returns with a red/brass semantic flash and a
  one-line reason. Never an alert dialog for a normal illegal move.

### Turn changes

- Active seat card updates immediately; previous actor fades to waiting.
- A short table-edge sweep or seat marker animation communicates the handoff.
- AI: "Thinking" label plus a spinner in the seat card; controls disabled, not
  hidden.
- Hot-seat: a subtle "Pass to Player N" transition card before the next hand is
  shown, so hidden information is never exposed accidentally.

### Actions

- Primary contextual action:
  - playable hand: `Select a domino`;
  - blocked, drawable yard: `Draw`;
  - blocked, dry yard: `Pass`;
  - AI turn: `Computer is thinking`.
- `Draw` and `Pass` live in the hand dock, not in a detached toolbar.
- `Analyze` moves to the menu/Coach sheet. It is not in the primary action row.
- `Reset View` moves to the menu. Camera reset should not compete with play.
- `Esc` opens the game menu. The menu contains Resume, Rules, Appearance,
  Restart Match (with confirmation), and Exit to Lobby.

### Keyboard and accessibility

- `1`–`7` select a hand tile; Left/Right choose an end; Return plays.
- `D` draw, `P` pass, `Esc` menu, `?` rules.
- Every interactive element has a visible focus ring and an accessible label.
- Active/playable/selected states include a non-color cue.
- Respect Reduce Motion; disable table/seat sweeps and pulse effects.
- VoiceOver announces the mode, active seat, score, hand count, selected tile,
  and available ends.

---

## 8. Component map

New or refactored SwiftUI surfaces:

```text
Sources/IsolynApp/DesignSystem/
  IsolynTokens.swift          colors, type, spacing, motion
  TableSurface.swift          felt table, rail, inner shadow
  SeatAccent.swift            per-seat/team presentation

Sources/IsolynApp/Match/
  MatchConfiguration.swift    format + opponent + AI level + defaults
  MatchLobbyView.swift        replaces ModeSelectorView
  ModePreview.swift           seat diagram / mini table
  RulesSheet.swift            concise rules + controls

Sources/IsolynApp/Game/
  GameTableView.swift         replaces InteractiveGameBoardView composition
  Presentation/
    SeatPresentation.swift    pure seat/team/role/turn models
    GamePresentation.swift    mode-aware derived state
  Components/
    MatchHeaderView.swift
    SeatCardView.swift
    TurnRibbonView.swift
    HandDockView.swift        replaces HandRackView
    ActionDockView.swift
    ContextHintView.swift
    CoachSheet.swift
    GameMenuView.swift
    RoundScorecardView.swift  replaces RoundEndOverlay
    MatchResultView.swift
```

Keep and parameterize:

- `IsolynDominoTile` — canonical renderer.
- `ChainAndZonesView` / `SnakeChainLayout` — board geometry; add a board style
  parameter for tile size and last-move edge, rather than changing formulas.
- `BoardCamera`, `GestureArbiter`, `HoverChain` resolver/model — the visual
  inspector is manual now; its trigger contract is in §0.
- `AppearanceManager` / `SettingsDrawer` — move behind the menu; keep the
  customization engine.

Not new dependencies. No custom fonts. No third-party UI framework.

---

## 9. State and data changes

### `AppState`

Replace the tuple route with:

```swift
enum Screen: Equatable {
    case entry
    case lobby
    case game(MatchConfiguration)
    case comingSoon(String)
}
```

`MatchConfiguration` contains only real, supported choices:

- `format: MatchFormat`
- `opponent: OpponentMode`
- `aiLevel: AILevel`
- default human seat = 0 (engine invariant)
- 2v2: partner seat is computer-controlled when `opponent == .computer`

Do not add match length, scoring target, or player-name fields until the
engine can actually honor them.

### Presentation models

Add pure, testable models:

- `SeatIdentity`: index, name, role (`you`, `partner`, `opponent`), team,
  control (`human`, `computer`), accent.
- `SeatState`: current, waiting, thinking, out.
- `GamePresentation`: mode title, seat list, team scores, active seat, next
  seat, turn order, primary action, hint.

Tests cover:

- 1v1: two seats, one opponent.
- 1v1v1: three seats, 0 → 1 → 2 order.
- 2v2: four seats, team assignment 0/2 vs 1/3, partner labeled correctly.
- hot-seat vs computer seat control.
- score mapping: participants for 1v1/1v1v1, teams for 2v2.
- round/match-end transitions.

### Last move and round number

`GameSnapshot` does not carry play history. For the first UI pass:

- `GameViewModel` records `lastMove` and `lastMoverSeat` on successful human
  and AI submissions.
- `GameViewModel` tracks `roundNumber`, incrementing on `dealNextRound`.
- Clear last move on a new round.
- A real move list / replay is a later bridge/engine addition, not part of the
  first visual pass.

### Board sizing

`SnakeChainLayout` currently exposes static constants. Parameterize the tile
short axis and marker diameter through a `BoardStyle` value while keeping the
layout formulas, camera bounds, and tests intact. Hand and board should scale
from the same token source.

---

## 10. Implementation phases

### Phase 0 — Audit and direction lock (this document)

- Inventory current screens, state, and constraints.
- Choose the table-first direction.
- Define mode layouts, component map, and acceptance criteria.
- The separate responsive-shell slice landed first: shared centered content,
  adaptive padding, centered entry/lobby/game bands, and a centered board
  bounding box. The mode-native composition in the phases below is still the
  main overhaul.

### Phase 1 — Foundation and shell

- Add `IsolynTokens`, `TableSurface`, `SeatAccent`.
- Add `MatchConfiguration` and the new `AppState` route.
- Add `GamePresentation` / `SeatPresentation` with unit tests.
- Add a minimal `GameTableView` shell around the existing board and hand.
- Exit criteria: app builds and every existing game action still works through
  the old board/hand components.

### Phase 2 — Match lobby

- Replace `ModeSelectorView` with `MatchLobbyView`.
- Add mode previews that show seat count, teams, and turn order.
- Keep opponent/strength choices honest; no unsupported settings.
- Add `RulesSheet` and clear Back behavior.
- Exit criteria: every mode can be started and returned from without dead ends.

### Phase 3 — Duel reference table

- Build the 1v1 layout: header, opponent card, table stage, hand dock, action
  dock, context hint.
- Raise board and hand tile sizes.
- Add last-move highlight, legal-end affordance, and invalid-move feedback.
- Add game menu and exit confirmation.
- Exit criteria: complete 1v1 human and computer games; no regressions in
  selection, draw, pass, analysis, round end, or rematch.

### Phase 4 — Three-Way

- Add three seat cards, turn ribbon, and mode-specific score layout.
- Validate current/next seat across the 0 → 1 → 2 cycle.
- Validate hot-seat handoff and hidden-information behavior.
- Exit criteria: full three-player round and match with correct scoring.

### Phase 5 — Partners

- Add team rails, partner identity, team scoreboard, and team-colored edges.
- Preserve human seat 0 / partner seat 2 relationships.
- Collapse rails to a top strip at narrow widths.
- Exit criteria: full 2v2 round and match; partner AI never stalls.

### Phase 6 — End states and guidance

- Replace `RoundEndOverlay` with `RoundScorecardView`.
- Add match result with running totals and Rematch / Change Mode.
- Add first-run rules/onboarding entry points.
- Add keyboard shortcuts and VoiceOver labels.
- Exit criteria: a new player can start, play, finish, and start again without
  external instructions.

### Phase 7 — Visual and accessibility QA

- Test 900×620, 1080×720, 1440×900.
- Test all modes, both opponent controls, 1/3/7-tile hands, blocked/draw/pass,
  selected/deselected, round end, match end, reduced motion, increased contrast.
- Verify no `P1`/`P2` telemetry, no dead ends, no alert-based illegal moves.
- Profile the table for animation hitches; no engine changes should be needed.

---

## 11. Acceptance criteria

The overhaul is not done until all of these are true:

- A new player can identify the mode, their seat, the active seat, both scores,
  their hand, and the primary action within three seconds.
- Duel, Three-Way, and Partners are visually and spatially distinct.
- Every mode supports pass-and-play and vs-computer without changing the table
  model.
- The board is the largest visual object; the hand is the second.
- No raw `P1`/`P2` opponent strip, `VS COMPUTER`, `HOT SEAT`, or `P1 5` labels
  remain in the play surface.
- No technical `boneyard` wording in player-facing copy; use "draw pile" or
  contextual "Draw".
- A selected tile, a legal end, the active seat, and the last move each have a
  non-color cue.
- Every action is reachable by mouse and keyboard.
- Menu, rules, appearance, and exit are reachable from every game screen.
- Round and match endings show the actual hands, actual scores, and actual next
  starter for the current mode.
- The app builds at the existing 900×620 minimum, and the board never clips or
  becomes unreachable.
- Existing engine, bridge, and view-model tests remain green. New presentation
  tests cover seat/team/turn mapping.

---

## 12. Risks and boundaries

- **Hidden information:** hot-seat handoff must not flash the next player's
  hand. Use a deliberate pass-device transition before the next snapshot.
- **2v2 partner control:** the engine currently requires the partner seat to be
  computer-controlled in single-human mode. The UI must label the partner
  honestly; do not imply a human partner.
- **No fake configuration:** the engine has no match-length or custom scoring
  target. Do not add those controls yet.
- **No new dependencies:** SwiftUI only. Keep the app native and light.
- **No engine rewrite:** this is a presentation/state composition pass. If a
  screen needs data the bridge does not expose, track it locally for the first
  pass or add the bridge surface deliberately later.
- **Tile geometry remains law:** the new table may change scale, surface, and
  surrounding composition, but never the single-rectangle domino construction.

---

## 13. Immediate next slice

Start with **Phase 1 + Phase 3 (Duel)** rather than touching all three modes at
once. Duel is the smallest complete table, and it will validate the header,
seat card, board surface, hand dock, action dock, menu, and round scorecard.
Once those components are stable, Three-Way and Partners become layout
compositions over the same primitives.

The first code review should answer one question: does the Duel table already
feel like a game a person would choose to sit at? If not, do not scale the same
composition to the other two modes.
