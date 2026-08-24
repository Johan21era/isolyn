# DOMINOES UI FIX --- NON-NEGOTIABLE REBUILD MANDATE

## STATUS: CRITICAL / REJECT CURRENT UI

The current Dominoes Stockfish UI is **not acceptable**.

Do not polish it incrementally. Do not preserve bad layout decisions
because they already exist in the code. Do not reinterpret this
specification as a list of suggestions. Do not run a visual-design
experiment. Do not invent an alternative aesthetic.

**You WILL replace the bad presentation layer with the structure and
behavior specified below.**

If an existing component, CSS rule, layout primitive, tile renderer,
spacing system, or interaction pattern conflicts with this document,
**the conflicting implementation is to be deleted or rewritten.**

The existing implementation is not the source of truth.

This document is.

------------------------------------------------------------------------

# 1. PRIMARY OBJECTIVE

Rebuild the game UI so that it communicates one thing immediately:

> **This is a polished dominoes game. The player can instantly
> understand the board, the playable ends, their hand, whose turn it is,
> the score, and what action is available.**

The reference image establishes the intended composition and information
hierarchy.

The color treatment in the reference image is **NOT** authoritative.

Everything else about the visual structure, proportions, tile
construction, hierarchy, spacing, orientation, and interaction model
**IS authoritative** unless explicitly overridden by a requirement
below.

------------------------------------------------------------------------

# 2. ABSOLUTE RULE: DOMINOES ARE SINGLE RECTANGLES

## THIS IS THE MOST IMPORTANT REQUIREMENT IN THIS DOCUMENT.

A domino tile **MUST be one continuous rectangle**.

It is **NOT** two independently rendered squares.

It is **NOT** two cards.

It is **NOT** two flex children with a visible gap.

It is **NOT** two adjacent boxes that merely happen to touch.

It is **NOT** two separate DOM elements positioned beside each other.

It is **ONE TILE CONTAINER**.

### Required geometry

For a horizontal domino:

``` text
┌───────────────────────────────┐
│             │                 │
│     pips    │       pips      │
│             │                 │
└───────────────────────────────┘
```

For a vertical domino:

``` text
┌───────────────┐
│     pips      │
│               │
├───────────────┤
│     pips      │
│               │
└───────────────┘
```

The center divider is a **line inside the same rectangle**.

There is **zero physical gap** between the two halves.

### Forbidden implementation

Do NOT implement:

``` text
<div class="half">...</div>
<div class="half">...</div>
```

with margin/gap between them.

Do NOT implement two independent tile backgrounds.

Do NOT allow the page background to appear between the two halves.

Do NOT allow separate border radii on the inner halves.

Do NOT allow the center seam to become a gap.

### Required implementation model

Use one tile element:

``` text
domino
├── top/left pip region
├── internal divider
└── bottom/right pip region
```

The tile has:

-   one outer background
-   one outer border
-   one outer radius
-   one shadow/elevation treatment
-   one bounding box
-   one interaction target
-   one selected state
-   one placement identity

The two pip regions are internal content only.

### Acceptance test

Zoom the interface to 200%.

If the user can visually interpret the domino as two separate cards,
**the implementation fails**.

If any background-colored line wider than the intended divider appears
between the two halves, **the implementation fails**.

If there is any CSS `gap`, margin, positioning offset, or separate
border treatment creating separation between the halves, **the
implementation fails**.

**Fix it. Do not rationalize it.**

------------------------------------------------------------------------

# 3. DOMINO TILE SPECIFICATION

Use a consistent canonical tile geometry.

## Base tile

For the primary desktop board:

-   horizontal tile target size: approximately `56px × 28px`
-   vertical tile target size: approximately `28px × 56px`
-   aspect ratio: exactly `2:1`
-   outer border radius: `4–6px`
-   outer border: `1px`
-   internal divider: `1px`
-   internal divider centered exactly at 50%
-   no gap between halves
-   no independent backgrounds for halves

The exact CSS dimensions may scale responsively, but the **2:1 geometric
relationship must remain intact**.

## Pips

Pips must be:

-   circular
-   consistent in diameter
-   optically centered
-   mathematically positioned according to a canonical domino pip grid
-   identical in rendering quality across every tile
-   never manually positioned differently from tile to tile

Use the conventional pip layouts for values `0–6`.

Do not approximate pip locations randomly.

Do not use text glyphs such as `•` as a substitute for actual pip
geometry if that produces inconsistent alignment.

## Center divider

The divider:

-   is inside the tile
-   is exactly centered
-   spans the internal height/width appropriate to the orientation
-   is visually subtle but clearly readable
-   never creates physical separation
-   never changes the tile's bounding box

## Tile silhouette

Every tile must visually read as:

**ONE PIECE OF MATERIAL.**

This requirement takes priority over every convenience of the current
implementation.

------------------------------------------------------------------------

# 4. BOARD MUST LOOK LIKE A DOMINO BOARD

The current board presentation is unacceptable if it resembles a
collection of floating rectangles in a debugging canvas.

The board must have a coherent visual plane.

The domino chain is the primary object.

The chain should occupy the central portion of the game viewport and
have enough breathing room around it to make the topology readable.

## Required hierarchy

``` text
┌─────────────────────────────────────────────────────────────┐
│ GAME HEADER                                                 │
│ turn / player / score / controls                            │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│                    DOMINO BOARD                             │
│                                                             │
│             ┌───┬───┬───┬───┐                               │
│             │   │   │   │   │                               │
│             └───┴───┴───┴───┘                               │
│                    │                                        │
│                    │                                        │
│                 ┌───┐                                       │
│                 │   │                                       │
│                 ├───┤                                       │
│                 │   │                                       │
│                 └───┘                                       │
│                                                             │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│ HAND / DRAW / ANALYZE                                       │
│                                                             │
│     [domino][domino][domino][domino][domino]...             │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│ OPPONENT / STATUS / SCORE                                   │
└─────────────────────────────────────────────────────────────┘
```

The exact responsive implementation may vary by viewport size, but **the
hierarchy may not**.

------------------------------------------------------------------------

# 5. DO NOT USE THE CURRENT GIANT EMPTY BOARD BOXES

The current UI contains excessive empty vertical slot structures that
make the board look like a developer visualization.

Delete them.

The board should not look like:

``` text
|       |       |       |       |
|       |       |       |       |
|  tile |  tile |  tile | tile  |
|       |       |       |       |
|       |       |       |       |
```

Those structural boxes are not the game.

They are implementation scaffolding leaking into the UI.

The player should see the **dominoes**, not their layout containers.

Containers should only exist where required for positioning and should
not visually compete with the pieces.

------------------------------------------------------------------------

# 6. BOARD POSITIONING

The reference composition uses a connected chain with horizontal runs
and vertical turns.

Preserve that fundamental visual language.

The board must support:

-   horizontal dominoes
-   vertical dominoes
-   turns/corners
-   branching/complex layouts if the game rules require them
-   clear physical adjacency
-   correct tile orientation
-   correct connection geometry

A domino placed vertically must rotate as a **single rectangle**.

It must not become two vertically stacked cards.

------------------------------------------------------------------------

# 7. TILE CONNECTIONS

When two dominoes are connected:

-   their endpoints must visually meet
-   there must be no arbitrary gap
-   the connection must feel physically intentional
-   tile edges must remain crisp
-   the board must not show invisible layout scaffolding

Default inter-tile spacing should be approximately:

`0–6px`

depending on whether the game rules/layout require a visual breathing
space.

Do not create large gaps.

Do not create inconsistent gaps.

Do not let one connection use 2px while another uses 12px.

Use one canonical spacing system.

------------------------------------------------------------------------

# 8. BOARD ENDS / PLAYABLE LOCATIONS

The active playable ends are critical.

Only valid playable ends should receive an active highlight.

Do not highlight every possible slot.

Do not illuminate empty layout containers.

Do not use ambiguous global highlighting.

The player must immediately understand:

> **"I can play here."**

Use a clear but restrained visual treatment:

-   outline
-   glow
-   endpoint marker
-   subtle animation only if necessary

Do not turn the entire board into a glowing neon mess.

The board remains the dominant visual object.

The legal move indicator is secondary but unmistakable.

------------------------------------------------------------------------

# 9. PLAYER HAND

The player hand must be presented as an actual hand of dominoes.

The current screenshot's dark, empty-looking slots are unacceptable.

Do not show a row of huge empty vertical containers.

Do not make the player wonder whether a tile failed to load.

The hand should visually resemble:

``` text
        ┌───┐ ┌───┐ ┌───┐ ┌───┐ ┌───┐
        │   │ │   │ │   │ │   │ │   │
        │   │ │   │ │   │ │   │ │   │
        └───┘ └───┘ └───┘ └───┘ └───┘
```

Every tile is a complete domino rectangle.

Tiles should be close enough to read as a hand, but not overlap unless
the responsive design explicitly requires it.

## Hand interaction

Selecting a tile must produce an obvious selected state.

The selected tile should:

-   remain a complete rectangle
-   receive a clean outline
-   optionally lift slightly
-   remain readable
-   not change its intrinsic geometry
-   not create layout jumps

Do not enlarge a selected tile so much that the entire hand reflows.

Do not cause adjacent tiles to jump.

------------------------------------------------------------------------

# 10. HAND ORDER AND VISUAL CONSISTENCY

Tiles must have:

-   identical dimensions
-   identical pip rendering
-   identical border treatment
-   identical divider geometry
-   identical radius
-   identical internal padding

Only the values and orientation should differ.

A `1|4` and a `6|6` must look like the exact same physical object with
different pip content.

------------------------------------------------------------------------

# 11. TOP HEADER

The header must be compact and information-dense.

It should communicate:

-   game mode
-   whose turn it is
-   player identity
-   score
-   opponent score
-   relevant game status
-   essential controls

Do not let tiny peripheral information compete with the board.

The game state should be immediately readable.

Suggested hierarchy:

``` text
1V1
Player 1's turn

[ Player 1 ]    [ SCORE ]    [ SCORE ]    [ Player 2 ]
```

The exact wording may follow the application's actual game state, but
the hierarchy must remain.

------------------------------------------------------------------------

# 12. SCORE DISPLAY

Scores must be visually distinct.

Use:

-   compact score containers
-   strong numerical typography
-   clear player association
-   consistent alignment

Do not bury the score in a corner.

Do not use oversized decorative elements that make the score look like
an unrelated notification.

------------------------------------------------------------------------

# 13. "DRAW" AND "ANALYZE"

The lower action area must clearly separate gameplay controls from the
hand.

`Draw` and `Analyze` should look like intentional controls.

They must not look like plain text accidentally placed next to icons.

Use:

-   icon
-   label
-   consistent hit area
-   hover/active state
-   disabled state where appropriate

The control row must not overpower the hand.

------------------------------------------------------------------------

# 14. INSTRUCTIONS

Contextual instructions such as:

> Tap a highlighted end to place.

must appear only when useful.

They should be visually secondary.

Use approximately:

-   `12–14px`
-   muted contrast
-   centered alignment where appropriate

Do not let instructional text compete with the board.

------------------------------------------------------------------------

# 15. REMOVE DEBUG-STYLE VISUAL LANGUAGE

The finished UI must not contain visual artifacts that make it feel like
an engineering tool.

Remove or redesign:

-   giant empty slots
-   unexplained outlines
-   invisible placeholders that become visible through contrast
-   arbitrary dark boxes
-   accidental borders
-   inconsistent tile containers
-   excessive empty regions
-   debugging labels
-   implementation-oriented terminology
-   visual scaffolding
-   placeholder states that look like broken content

If a player could reasonably ask:

> "Is that supposed to be there?"

then it probably should not be there.

------------------------------------------------------------------------

# 16. SPACING SYSTEM

Use a consistent spacing scale.

Recommended base unit:

`4px`

Use multiples of that unit wherever practical:

-   4px
-   8px
-   12px
-   16px
-   20px
-   24px
-   32px
-   40px

Do not randomly introduce values such as:

-   13px
-   17px
-   23px
-   31px

unless there is a documented geometric reason.

The UI should feel mathematically organized.

------------------------------------------------------------------------

# 17. RESPONSIVE BEHAVIOR

The desktop reference composition must be preserved at large viewport
sizes.

At smaller widths:

-   scale the board intelligently
-   preserve tile aspect ratios
-   preserve single-rectangle tile construction
-   preserve hand readability
-   prevent horizontal overflow
-   avoid crushing dominoes into unreadable sizes

If the hand cannot fit:

1.  reduce spacing
2.  reduce tile scale within defined limits
3.  allow controlled scrolling if necessary

Do NOT:

-   split dominoes
-   turn them into separate squares
-   create random wrapping
-   introduce arbitrary gaps
-   distort the 2:1 aspect ratio

------------------------------------------------------------------------

# 18. DOM / COMPONENT ARCHITECTURE

The UI should have a clean component model.

At minimum, conceptually:

``` text
GameScreen
├── GameHeader
│   ├── GameMode
│   ├── TurnIndicator
│   ├── PlayerScore
│   └── Controls
│
├── BoardArea
│   ├── BoardSurface
│   └── DominoTile[]
│
├── ActionBar
│   ├── DrawAction
│   └── AnalyzeAction
│
├── PlayerHand
│   └── DominoTile[]
│
└── StatusArea
```

The exact framework/component naming can follow the existing
application.

The critical point is that `DominoTile` must be a reusable canonical
component.

There should be **one source of truth for domino rendering**.

Do not create separate ad-hoc implementations for:

-   board tiles
-   hand tiles
-   selected tiles
-   vertical tiles
-   horizontal tiles

They should all use the same underlying tile component and only change
orientation/state.

------------------------------------------------------------------------

# 19. DOMINO TILE DATA MODEL

A tile should conceptually be represented as:

``` text
{
  left: 0..6,
  right: 0..6,
  orientation: horizontal | vertical,
  selected: boolean,
  playable: boolean,
  disabled: boolean
}
```

Do not encode the visual halves as separate game objects.

The game object is the domino.

The two values are properties of that domino.

------------------------------------------------------------------------

# 20. ORIENTATION

Orientation changes the entire tile.

Horizontal:

``` text
[left | right]
```

Vertical:

``` text
[left]
[----]
[right]
```

The visual divider rotates with the tile.

The tile remains one rectangle in both orientations.

------------------------------------------------------------------------

# 21. VISUAL PHYSICS

Dominoes should look like physical game pieces.

They need:

-   clear silhouette
-   slight elevation
-   crisp edges
-   consistent material appearance
-   readable pips
-   subtle depth

Do not overdo shadows.

Do not make them look like glowing UI widgets.

Do not make them look like buttons.

They are **game pieces**.

------------------------------------------------------------------------

# 22. TYPOGRAPHY

Use one coherent system font stack.

Recommended:

``` css
font-family:
  Inter,
  ui-sans-serif,
  system-ui,
  -apple-system,
  BlinkMacSystemFont,
  "Segoe UI",
  sans-serif;
```

Suggested hierarchy:

-   game title / mode: `14–16px`, semibold
-   primary status: `15–18px`, semibold
-   section labels: `13–14px`, semibold
-   body text: `13–14px`
-   instructional text: `12–13px`
-   score numbers: `16–20px`, semibold/bold

Typography must be restrained.

The game board, not decorative text, is the hero.

------------------------------------------------------------------------

# 23. COLOR

The reference screenshot's color palette is **not mandatory**.

Do not copy its colors blindly.

Choose the application's established color system.

However, the following contrast relationships ARE mandatory:

-   dominoes must be clearly distinguishable from the board
-   pip markings must be highly legible
-   active playable ends must be unmistakable
-   selected tiles must be unmistakable
-   disabled content must still remain recognizable as content
-   secondary UI must not overpower the board

Do not use color as the only indication of an interaction state.

------------------------------------------------------------------------

# 24. ACCESSIBILITY

The UI must preserve:

-   sufficient contrast
-   keyboard focus visibility where applicable
-   semantic buttons for actions
-   accessible labels
-   non-color-only state indicators
-   readable tile values

A selected tile must be visually distinguishable without requiring the
user to perceive a specific hue.

------------------------------------------------------------------------

# 25. ANIMATION

Animation is subordinate to gameplay.

Use only small, purposeful transitions.

Examples:

-   tile selection: `100–180ms`
-   playable-end highlight: subtle pulse or static glow
-   placement: short movement into position

Do NOT:

-   continuously animate the board
-   bounce dominoes
-   use excessive particle effects
-   make tiles wobble
-   introduce flashy transitions that obscure the game state

The board must remain calm.

------------------------------------------------------------------------

# 26. EXACT INFORMATION HIERARCHY

The visual priority must be:

### Priority 1

**Current board and legal moves**

### Priority 2

**Player hand**

### Priority 3

**Turn / score / player identity**

### Priority 4

**Gameplay actions**

### Priority 5

**Secondary information**

Nothing secondary should visually dominate the board.

------------------------------------------------------------------------

# 27. WHAT MUST BE DELETED FROM THE CURRENT DESIGN

Delete or completely replace any implementation responsible for:

-   disconnected domino halves
-   large vertical slot outlines
-   giant empty board columns
-   dark placeholder rectangles masquerading as tiles
-   excessive dead space
-   arbitrary tile spacing
-   inconsistent orientation
-   separate tile-half backgrounds
-   broken center seams
-   visually ambiguous selected states
-   weak hand presentation
-   debugging-style board scaffolding
-   unexplained containers
-   layouts that prioritize implementation structure over game
    readability

**Do not preserve them for compatibility if they produce the wrong UI.**

Refactor the implementation.

------------------------------------------------------------------------

# 28. REFERENCE COMPOSITION --- FOLLOW THIS

The provided reference establishes this composition:

``` text
┌──────────────────────────────────────────────────────────────┐
│                                                              │
│  GAME MODE        PLAYER / TURN       SCORE      CONTROLS    │
│                                                              │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│                                                              │
│                       BOARD                                  │
│                                                              │
│          ┌──┬──┬──┬──┬──┬──┐                                 │
│          │  │  │  │  │  │  │                                 │
│          └──┴──┴──┴──┴──┴──┘                                 │
│                     │                                        │
│                     │                                        │
│                  ┌────┐                                      │
│                  │    │                                      │
│                  ├────┤                                      │
│                  │    │                                      │
│                  └────┘                                      │
│                                                              │
│                                                              │
├──────────────────────────────────────────────────────────────┤
│  DRAW      ANALYZE                                           │
│                                                              │
│                      PLAYER HAND                             │
│          [domino][domino][domino][domino]...                 │
│                                                              │
├──────────────────────────────────────────────────────────────┤
│                    PLAYER / STATUS / SCORE                   │
└──────────────────────────────────────────────────────────────┘
```

The board should occupy the largest meaningful region.

The hand should be visually obvious.

The dominoes should be the visual language of the application.

------------------------------------------------------------------------

# 29. IMPLEMENTATION ORDER

Do not start by tweaking random CSS values.

Implement in this order:

## Step 1 --- Replace the domino renderer

Create the canonical single-rectangle domino.

Verify:

-   2:1 ratio
-   one outer rectangle
-   one internal divider
-   zero gap
-   correct pip layouts
-   horizontal orientation
-   vertical orientation

Do not continue until this is correct.

## Step 2 --- Rebuild board layout

Place the canonical domino component into the board.

Verify:

-   connected chain
-   turns
-   orientations
-   consistent spacing
-   legal-end highlighting

## Step 3 --- Rebuild player hand

Use the exact same tile component.

Verify:

-   tiles are immediately recognizable
-   selected state
-   consistent spacing
-   no empty fake slots

## Step 4 --- Rebuild header/status

Add:

-   player
-   turn
-   score
-   mode
-   controls

## Step 5 --- Rebuild action area

Add:

-   Draw
-   Analyze
-   instructions

## Step 6 --- Responsive pass

Test:

-   desktop
-   laptop
-   tablet-width
-   narrow viewport

## Step 7 --- Interaction pass

Test:

-   select tile
-   deselect tile
-   highlight legal end
-   place tile
-   invalid placement
-   draw
-   analyze
-   turn transition

## Step 8 --- Visual QA

Compare the resulting UI directly against the reference composition.

Do not compare the current implementation against itself.

------------------------------------------------------------------------

# 30. ACCEPTANCE CRITERIA

The redesign is **NOT DONE** until every condition below is true.

### Domino construction

-   [ ] Every domino is one continuous rectangle.
-   [ ] No domino consists of two independently rendered cards.
-   [ ] No visible gap exists between halves.
-   [ ] The center divider is internal.
-   [ ] The tile has one outer border.
-   [ ] The tile has one outer radius.
-   [ ] The tile has one bounding box.
-   [ ] Horizontal and vertical tiles preserve the 2:1 ratio.
-   [ ] Pip layouts are canonical and consistent.

### Board

-   [ ] Board dominoes form a coherent connected structure.
-   [ ] Horizontal and vertical orientations are correct.
-   [ ] Turns are visually clean.
-   [ ] Legal ends are obvious.
-   [ ] Invalid locations are not misleadingly highlighted.
-   [ ] Empty layout scaffolding is not visible.
-   [ ] Board is the primary visual focus.

### Hand

-   [ ] Player hand looks like a real collection of dominoes.
-   [ ] Every tile is immediately recognizable.
-   [ ] Selected tile has a clear state.
-   [ ] Selection does not cause disruptive layout shifts.
-   [ ] No fake empty slots dominate the hand.
-   [ ] Tiles use the same canonical renderer as board tiles.

### Layout

-   [ ] Header is compact.
-   [ ] Board occupies the main content area.
-   [ ] Hand is clearly separated from board.
-   [ ] Actions are clearly identifiable.
-   [ ] Score and turn information are readable.
-   [ ] Dead space has been aggressively reduced.
-   [ ] No major region looks unfinished.

### Quality

-   [ ] No debug-looking scaffolding remains.
-   [ ] No placeholder-looking dominoes remain.
-   [ ] No arbitrary visual inconsistencies remain.
-   [ ] No component visually contradicts the design system.
-   [ ] The application looks intentionally designed rather than
    generated from implementation constraints.

------------------------------------------------------------------------

# 31. FINAL DIRECTIVE

**DO NOT ASK WHETHER THIS DESIGN SHOULD BE INTERPRETED DIFFERENTLY.**

**DO NOT PROPOSE THREE ALTERNATIVES.**

**DO NOT "EXPLORE" A FEW VISUAL DIRECTIONS.**

**DO NOT PRESERVE THE CURRENT BAD UI JUST BECAUSE IT ALREADY EXISTS.**

**DO NOT MAKE THE DOMINO INTO TWO SQUARES.**

**DO NOT CREATE A GAP BETWEEN THE TWO HALVES.**

**DO NOT REINTRODUCE THE GIANT EMPTY SLOT SYSTEM.**

**DO NOT TURN THE BOARD INTO A DEBUG VISUALIZER.**

The reference establishes the intended composition.

The specifications establish the implementation constraints.

The domino must be a **single rectangle**.

The board must be the **primary visual object**.

The player's hand must be **immediately recognizable**.

The interface must look like a **finished dominoes game**, not an
engineering prototype.

If an existing implementation conflicts with these requirements:

> **DELETE THE CONFLICTING IMPLEMENTATION. REBUILD IT CORRECTLY.**

If the final result does not satisfy the acceptance criteria:

> **IT IS NOT A PARTIAL SUCCESS. IT IS A FAILED UI IMPLEMENTATION.**

**Erase the bad parts. Rebuild them. Verify them. Do not compromise on
the tile geometry.**
