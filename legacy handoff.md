# ISOLYN — LEGACY HANDOFF (read me before anything else)

**Who this is for:** a human who has never coded, OR an AI model that is
small, weak, and has no memory of anything. Both should be able to do useful,
safe work after reading only this file.

**Relationship to history:** the original `HANDOFF.md` was retired (deleted)
after every load-bearing fact inside it was extracted into §5 below, code
comments, `fix-log.md`, or `docs/`. Nothing important was lost — §5 is the
condensed survival of its rules, ambiguities, and hard-won lessons. This file
is now the SINGLE source of truth for status AND rules.

---

## 1. WHAT THIS PROJECT IS (plain words)

Isolyn is a Mac desktop game of **Albanian dominoes** (double-six set, 28
tiles). You play against other humans on the same screen today; a computer
opponent comes next.

**Plain:** tiles have two numbers each. You match numbers onto a growing line.
Run out of tiles = you win the round. Nobody can move = round locks, lighter
hand wins points. First to too many points loses the match.

**Technical:** C++20 engine (`isolyn` namespace) owns ALL game truth. A tiny
POD-only C bridge exposes it safely. A SwiftUI macOS app draws it. Three
strict layers, one direction of dependency:

```
SwiftUI app  ──import──▶  IsolynEngineBridge  ──links──▶  IsolynEngine (C++)
 (pretty face)             (safety wall, POD only)        (all the math/rules)
```

Nothing ever points backwards. The pretty layer never computes game truth;
it only asks the engine and displays answers.

---

## 2. CURRENT STATE — SCOREBOARD (all verified — §6 re-proves everything)

| Layer | Check | Result |
|---|---|---|
| C++ engine | 18 test programs | **362/362 checks pass**, zero warnings |
| Bridge | smoke suite | **58/58 checks pass** |
| Swift app | `swift test` | **35 tests: 0 failures, 1 honest skip** |
| Memory safety | AddressSanitizer + UBSan on everything (`./run_sanitize.sh address`) | **420 checks, zero findings** |
| Thread safety | ThreadSanitizer on threaded parts (`./run_sanitize.sh thread`) | **73 checks, zero findings** |
| Adversarial input | fuzz harness | 50,000 garbage-input runs, zero crashes |
| CI | GitHub Actions macOS runner (push/PR suites + weekly fuzz) | wired — `.github/workflows/ci.yml` |
| Version control | git → GitHub | private repo `Johan21era/isolyn`, branch `main`, clean |

**What you can DO with it right now:** open the app, pick 1v1 / 1v1v1 / 2v2,
play complete multi-round hot-seat matches with real scoring, reveals, forced
draws, passes, and an optional engine "Analyze" button that suggests moves.

**What you CANNOT do yet:** play against the computer (Phase 3), Training
puzzles (Phase 5), Sandbox position builder (Phase 4). Those are roadmap
items, not bugs.

---

## 3. FOLDER MAP (every item, one line each)

| Path | What it is |
|---|---|
| `Sources/IsolynEngine/` | The brain. C++ rules/math. 25 .cpp files + 26 headers in `include/`. **If a test fails, the bug is here.** |
| `Sources/IsolynEngineBridge/` | Safety wall between C++ and Swift. One header + one .cpp. Handles bad input, threading, ownership. |
| `Sources/IsolynApp/Game/` | The game screen (NEW, Phase 2). 6 Swift files. Everything visible during play. |
| `Sources/IsolynApp/Environment/` | Sky/time/weather backdrop. Purely decorative, fully tested separately. |
| `Sources/IsolynApp/Views|Components|Theme/` | Menus, buttons, colors. |
| `Tests/IsolynEngineTests/` | 18 C++ test programs (the 356 checks). Each is its own executable. |
| `Tests/IsolynEngineBridgeTests/` | SmokeTest (57 checks), SoakTest (memory), FuzzBridge + StandaloneFuzzDriver (garbage-input attacks). |
| `Tests/IsolynAppTests/` | Swift tests (28). Time-of-day logic + headless game-flow tests. |
| `run_tests.sh` | One command: build+run all engine tests. |
| `run_bridge_tests.sh` | One command: build+run the bridge suite. |
| `run_bridge_fuzz.sh` | Garbage-input attack runner (auto-falls back if libFuzzer missing). |
| `run_sanitize.sh` | Sanitizer battery: `address` (ASan+UBSan everywhere) / `thread` (TSan on threaded parts). |
| `clean.sh` | House-rule #7 enforcement: erases build residue, restores ~10 MB steady state. |
| `.github/workflows/ci.yml` | CI: all suites on push/PR, weekly fuzz job. |
| `core hardening roadmap.md` | Plan of record for the pre-UI-revival hardening session. |
| `isolyn current audit.md` | Live-platform audit (F-01…F-12 findings + resolution ledger in Appendix D). |
| `tree.md` | Regenerated file listing — must match reality (house rule #8). |
| `graphify-out/` | Code knowledge graph (HTML map + report). Owner says keep. Refresh via `graphify update . --force` (rule #8). |
| `docs/` | Five design docs (BRIDGE_*, FEATURE_SPECS, STRATEGY_NOTES, RELEASE_CHECKLIST). Read STRATEGY_NOTES.md before touching AI/heuristics. |
| `fix-log.md` | Every bug fixed recently, with proof anchors. |
| `Package.swift` | Build recipe for the whole package. |
| *(HANDOFF.md)* | Retired — its surviving content lives in §5. |
| `.gitignore` | Keeps machine junk out of git. Never delete. |

---

## 4. THE LAST BIG SESSION — WHAT / WHY / HOW / WHERE

Everything below is DONE and PUSHED. Full per-bug detail lives in
`fix-log.md`. Anchors in the last column are search strings: open the file,
Cmd+F, paste, land on the exact lines.

| # | WHAT was done | WHY | HOW | WHERE (file → search anchor) |
|---|---|---|---|---|
| 1 | Put project under git, pushed to private GitHub | Project had ZERO version control; owner lost work to a sandbox wipe once before. Un-reversible work is forbidden now. | `git init`, wrote `.gitignore`, committed, created private repo, generated SSH key, pushed | `.gitignore` exists; `git log` shows 6 commits |
| 2 | Fixed scripts so tests actually RUN on Mac | Tests linked against Apple's Security framework without linking it → every test died at link. "356 passing" was unprovable on this machine until fixed. | added `-framework Security` only when `uname` = Darwin | `run_tests.sh` → `PLATFORM_FLAGS` |
| 3 | Made test script survive Mac's missing `timeout` command | Linux-only tool; script falsely failed passing tests | helper falls back to direct run | `run_bridge_tests.sh` → `run_with_timeout` |
| 4 | Killed random test flake (suite failed ~1-in-7) | Tests assumed dealt player always has a move; ~13% of deals say no. Also first fix attempt spun forever in no-boneyard modes because "draw" succeeds while drawing nothing there. | new helper resolves blocked players EXACTLY like real play, switching to pass-turn when yard is dry | `SmokeTest.cpp` → `ensureCurrentPlayerCanMove` |
| 5 | Restored fuzzing on Xcode 26 | Apple stopped shipping libFuzzer for macOS | auto-detect + standalone driver feeding identical attack function under memory sanitizers | `StandaloneFuzzDriver.cpp` |
| 6 | **Sealed the biggest correctness hole:** finished rounds were still playable | After someone plays their last tile (win), OTHER players could keep playing — nothing said "round over, stop". | new error `RoundAlreadyOver`; all four mutating commands check it AFTER the duplicate-guard so double-taps still self-heal | `IsolynBridge.hpp` → `RoundAlreadyOver = 10` |
| 7 | **Built match scoring across rounds** (was designed-out pending a design; design now exists & ships) | Game could play ONE round then forget everything. Real dominoes is a race to a point threshold across many rounds. | bridge records a finished round into a running score tracker; team hands combine for 2v2; winner-of-round deals next | `IsolynBridge.hpp` → `bridge_match_record_round` ; Swift: `MatchCoordinator.swift` |
| 8 | Round-end reveal data exposed safely | Scoring needs everyone's leftover tile values, but only AT round end (that's when physical players flip hands over). Mid-game it stays hidden — enforced by zeros. | snapshot gains `finalHandValues[]`, populated only when outcome ≠ InProgress | `IsolynBridge.hpp` → `REVEAL-ON-END` |
| 9 | **Built the actual game screen** (biggest missing piece) | App could show menus but not play. Now: full board, rack, chain, drag-free tap placement, draws, passes, analysis drawer, reveal overlay, next-round dealing. | six new Swift files driven by one state-machine class reading real snapshots | `Sources/IsolynApp/Game/` (all six) |
| 10 | Chain renders honestly | Tile orientations aren't stored anywhere (engine derives them); display now derives them the same way, so drawn pips always physically touch | walk from left end flipping each tile to match neighbor | `ChainView.swift` → `displayTiles` |
| 11 | Wrote headless gameplay tests | UI can't be auto-tested here, but the brain can: tests deal REAL random games through the same code the screen uses | 3 XCTest cases incl. hunting rare blocked deals across 24 fresh games | `Tests/IsolynAppTests/GameViewModelTests.swift` |
| 12 | Slimmed folder 597 MB → 7 MB | Compiled leftovers (482 MB Swift cache + 108 MB sanitizer binaries) are junk, not project | deleted both dirs; they regenerate on demand | n/a (ops) |

**Core-hardening session (post-Phase-2, owner-directed pre-UI-revival):** full detail per fix in `fix-log.md` FIX-15…FIX-26 + OPS-04…06; plan of record in `core hardening roadmap.md`.

| # | WHAT was done | WHY | HOW | WHERE (anchor) |
|---|---|---|---|---|
| H1 | Closed the weather race (F-04) | UI writes raced loop reads on weatherSource/mode/cache | @MainActor manager + local source capture pre-await + NSLock-guarded LiveWeatherService cache | `EnvironmentManager.swift` → `FIX-15`; `LiveWeatherService.swift` → `cacheLock` |
| H2 | Analyses can no longer be abandoned mid-burn (F-10) | dropped searches ran to completion detached | .onDisappear teardown + documented await-or-cancel contract + single-funnel invalidate | `InteractiveGameBoardView.swift` → `FIX-16` |
| H3 | applyOpponentDraw made total (F-11) | NDEBUG divide-by-zero / negative-drift corruption | early-return guard replacing debug assert, test-first | `BeliefState.cpp` → `FIX-17` |
| H4 | Unknown analysis handle fails truthfully (F-07) | SessionClosed violated AnalysisResultDTO's own status set | BridgeFailure + header contract note + SmokeTest check (57→58) | `IsolynBridge.cpp` → `FIX-18` |
| H5 | Enum divergence observable; HandleTable comment true (F-08/F-12) | silent fallbacks masked future C++ enum evolution; fake clamp line misled | os_log faults in every @unknown default; no-op clamp removed | `EngineTypes.swift` → `bridgeDTOLogger` |
| H6 | CI + recorded sanitizer baseline | make drift structurally impossible; pin memory-safety post-fixes | ci.yml push/PR+weekly fuzz; run_sanitize.sh (420 ASan/UBSan checks + 73 TSan checks, zero findings) | `.github/workflows/ci.yml`, `run_sanitize.sh` |
| H7 | Hue slider fixed — tiles no longer snap to black (N-1) | Color-keyed hex cache never populated; S/B read as zero | cache deleted; pure hex↔HSB functions; 7 new tests (swift 28→35) | `DominoAppearance.swift` → `FIX-21` |
| H8 | Appearance drawer honesty + small truths (N-2/F-09/N-4/N-6) | edge controls decorative; formatter rebuilt each tick; 7-tile rack rendered blank; Info.plist warning | edge rendering wired under semanticEdge precedence; formatter cache; truthful digit for counts ≥7; plist excluded | `IsolynDominoTile.swift` → `FIX-22` |
| H9 | Hover-chain overlay finally dismissible (N-3); dead code decided | comments promised exit logic that never existed | grace-period dismissal + close button + dismiss-on-play; EnvironmentSettingsView now in ⌘, Settings scene | `HoverChainController.swift` → `FIX-26` |

**UI-rebuild session (owner mandate `dominoes_ui_fix_non_negotiable.md`, executed in its own §29 order):**

| # | WHAT was done | WHY | HOW | WHERE (anchor) |
|---|---|---|---|---|
| U1 | Canonical single-rectangle renderer | mandate §2/§3 law: exact 2:1 both orientations, 1pt divider @50%, chrome-less halves, native vertical | full rewrite preserving appearance-edge wiring + semanticEdge precedence | `IsolynDominoTile.swift` → `NON-NEGOTIABLE GEOMETRY LAW` |
| U2 | Snake-chain board | §4–§8: connected runs, perpendicular doubles, clean turns, ends marked ON board only where legal | `SnakeChainBoard` deterministic `.position` layout; corner end-caps w/ guaranteed 4pt clearance; `EndMarker` rings gated on real legality | `ChainAndZonesView.swift` → `SnakeChainBoard` |
| U3 | Real hand + §28 chrome | hand must read as dominoes, lift without reflow; header/actions/status hierarchy is law | identical canonical tiles in rack; compact header `[P1]SCORE[P2]`; capsule action controls; status strip | `HandRackView.swift`, `InteractiveGameBoardView.swift` |
| U4 | Step-7 QA catch fixed pre-exposure | first corner design overlapped next-row tiles by 11pt | corner re-specified as perpendicular row-end cap; markers ride row center-lines | commit `30f11ee` |
| U5 | Owner visual sign-off | §30's only owner-eye checkbox | live app review passed ("looks amazing") — all acceptance sections green | fix-log → `UI-QA` |

**Deliberate deviation, disclosed:** roadmap said drag-and-drop placement.
Shipped: tap-tile-then-tap-end instead. Same result, far fewer platform
risks, works with screen readers. Dragging = future polish, tracked.

---

## 5. CONTEXT FROM EARLY PRODUCTION (survival of the retired HANDOFF.md)

Everything below was scraped from the original handoff before deletion.
Code comments across the engine cite the ambiguity resolutions **by
number** — that numbering is preserved exactly, so "see ambiguity #7"
still resolves.

### 5.1 Governing documents (authority order — still binding)

1. **Master Prompt** — process/methodology document (phased approach).
2. **Rules Spec** — the LITERAL, FINISHED ruleset. Wins every conflict. Always.
3. **Concept Spec** — vision/philosophy. Authoritative ONLY where Rules Spec is silent.

**Explicit non-goals (binding):** no neural networks, no reinforcement
learning, no LLM training, no human-game-database training. Monte Carlo /
sampling is permitted ONLY as mathematically-justified hidden-information
handling (determinization sampling) — never as a replacement for
deterministic search with a real evaluation function. Never fabricate a
probability. Everything must be explainable.

### 5.2 The sandbox-loss lesson (why "commit often" is house law)

A prior era lost ALL unexported work when its temporary Linux sandbox reset
mid-session, without warning. The only survivor was a zip already handed to
the owner. Hence: commit after every meaningful batch; treat any workspace
as hostile. Git now makes this mechanical — the rule's spirit is "no
meaningful work may exist in only one place."

### 5.3 The twelve ambiguity resolutions (numbering = load-bearing)

1. **Opening fallback when no double held:** highest-value plain tile opens
   (Rules Spec explicit; Concept Spec's "no exceptions" loses to the literal
   finished ruleset).
2. **That fallback's tiebreak:** implemented SUM-based (so 5-4 beats 6-1).
   Every Spec example shares one high side, so sum-vs-high-side-first is
   genuinely unproven; flagged, isolated to one comparison, trivial to flip
   if the owner rules otherwise.
3. **1v1 one-domino ritual, third exit:** if the single mandated draw isn't
   playable, the ritual ends for that player and ordinary Forced Drawing
   takes over.
4. **Boneyard exists ONLY in 1v1.** 1v1v1 deals 9×3=27 plus removes 0-0 = 28
   (none left); 2v2 deals 7×4=28 (none left). Boneyard formulas handle empty
   yards with zero special-casing.
5. **Misdeal "8 dominoes" trigger** generalized to *any hand-size mismatch*
   vs the mode's expected count (literal text only fits 7-tile modes; a
   digital deal can't miscount anyway — matters for future constructed
   positions).
6. **1v1 doubles-cannot-close:** credit walks back through an entire run of
   consecutive doubles to the most recent non-double play. 1v1v1/2v2
   explicitly allow doubles to close. **OPEN:** if EVERY play of a round was
   a double, falls back to crediting the last player (neither doc speaks).
7. **THE BIG ONE:** the mandated opening tile is FIRST-ROUND-OF-MATCH ONLY.
   Later rounds: starter freely chooses any tile (chain starts empty).
   Caught by the owner walking their own real gameplay trace. This is why
   `dealFirstRound` vs `dealSubsequentRound` exist as separate functions.
8. **1v1 "One Domino Rule" (both players down to one tile) — EXPLICITLY NOT
   IMPLEMENTED.** Mechanics genuinely underspecified: with
   draw-one-then-play-one netting hand size back to one, how a Domino
   victory occurs *within* the ritual is unclear in both documents. Several
   readings considered; none clearly correct. Needs an owner conversation.
   Ordinary Mandatory Play + Forced Drawing correctly govern every other
   1v1 endgame state.
9. **2v2 team mapping:** `playerIndex % 2`; team 0 = {0,2}, team 1 = {1,3}.
   Inferred from "partners sit opposite" + turn-order convention.
   Confident enough to ship, not certain enough to call settled.
10. **Match winner among 3+ participants:** strictly-lowest score wins
    outright (convention for threshold games); docs silent on 1v1v1 endings.
    Flagged, not settled.
11. **"May not refuse to win/close"** restates ordinary Mandatory Play — it
    does NOT narrow the legal-move set. Players legitimately (often
    correctly) decline a visible win/close. Owner-confirmed with real-play
    reasoning. `MoveValidator` correctly does zero win/close filtering.
12. **CRITICAL TEST-WRITING LESSON:** every `BeliefState` must account for
    all 28 tiles. Any test constructing states for ProbabilityEngine must
    make hands + chain + boneyard sum to exactly 28 (minus mode-excluded
    tiles): build via `DominoTile::fromIndex(0..27)`, place tiles of interest
    where needed, PAD everything else into the believer's own hand (extra
    known tiles there never affect tracked behavior). Two real test failures
    were caused by violating this before it became law.

### 5.4 Engine rigor status (stated plainly — do NOT "fix" these)

- **BeliefState** constructor + `applyOpponentDraw`: EXACT — algebra-verified
  to preserve per-tile normalization AND per-location counts simultaneously.
- **`markTileKnown`:** DOCUMENTED APPROXIMATION (single-pass rescale; exact
  joint solution needs Sinkhorn-style iterative proportional fitting).
  `probability()` re-normalizes per-tile at query time, so individual tiles
  always sum to 1 even when aggregates drift slightly. Intentional;
  documented in the class header.
- **EvaluationEngine** operates on ONE concrete GameState and needs NO
  belief machinery — uncertainty averaging happens one level up in
  SearchEngine across determinizations. By design; do not re-couple.
- **Determinizer:** capacity-exact, marginal-probability-weighted samples —
  NOT exact draws from the true joint posterior. Standard and defensible for
  search averaging.
- **`probabilityHoldsAtLeast`:** Poisson-binomial DP treating tile
  memberships as independent — a standard approximation (true membership is
  correlated through hand-count constraints), ≤7 trials, computed exactly
  via DP rather than sampling.

### 5.5 Still-open design questions (unchanged by Phases 1–2)

- **One Domino Rule mechanics** (see 5.3 #8) — blocked on owner conversation.
- **Behavioral analysis** (hesitation / declined draws as evidence):
  `ProbabilityEngine.observe*()` seams exist; rigorous implementation needs a
  CALIBRATED likelihood model that doesn't exist yet — adding arbitrary
  adjustment numbers would violate the never-fabricate rule.
- **DifficultyModel mapping** — now owned by roadmap Phase 3 (owner
  confirmation granted via roadmap adoption).

### 5.6 Early production timeline (compressed; full narratives retired)

Foundation (61 files, 278 checks) → search stack (`Chain::fromKnownState`,
extended GameState ctor, Determinizer, SimulationEngine, SearchEngine —
including the hand-verified "avoid handing opponent the 4-6 Domino" puzzle)
→ UI shell + environment batches 1–7 (time phases, appearance curve, stars,
weather, settings, legibility scrim; one real test bug fixed: Singapore-tz
assertion claimed night where it's actually primeDay) → EntropySource
rewritten to per-draw OS CSPRNG (owner-supplied design; rejection-sampled
Fisher–Yates) → bridge designed, built, fuzzed (two compile bugs in an
independently-drafted bridge fixed, including a missing namespace brace that
would have given every public function internal linkage) → independent audit
(see `fix-log.md`) → Phases 1–2 (recent commits).

Full batch-by-batch narratives were retired with the old file on purpose;
everything load-bearing survives in code comments, `docs/`, `fix-log.md`,
and this section.


---

## 6. ✅ CHECK MY WORK — copy, paste, compare

Run all commands from inside the `Isolyn-current_4` folder (Terminal:
type `cd `, drag the folder onto the window, press Return).

First build takes minutes (compiler writes its workspace back — folder grows
temporarily; that's normal, see §4#12).

**PROOF 1 — Engine really passes 356**
```
./run_tests.sh
```
Last lines MUST read exactly:
```
TOTAL CHECKS PASSED: 362
TOTAL CHECKS FAILED: 0
Compile failures: none
Runtime failures: none
```
*Proves:* every rules-of-dominoes behavior claimed in docs is machine-checked. (Was 356 before the core-hardening session added F-11 regression checks.)

**PROOF 2 — Bridge really passes 57**
```
./run_bridge_tests.sh
```
Must end:
```
Executables run: 2
TOTAL CHECKS PASSED: 58
```
*Proves:* safety wall works — illegal moves rejected, hidden hands hidden,
finished rounds refuse further play, scores accumulate correctly.

**PROOF 3 — Swift app builds and passes**
```
swift test
```
Must contain a line like:
```
Executed 35 tests, with 1 skipped and 0 failures
```
(older toolchains word it slightly differently; key = **0 failures**). Was 28 tests before core hardening added the color-math suite.
*Proves:* time-of-day engine + headless game flow behave.

**PROOF 4 — Fuzzing works here**
```
./run_bridge_fuzz.sh 15
```
Must print `standalone fuzz: … executions, zero crashes` and exit Clean.
*Proves:* garbage input cannot crash the safety wall.

**PROOF 5 — Terminal guard exists (FIX‑07)**
macOS Finder/TextEdit: open
`Sources/IsolynEngineBridge/include/IsolynBridge.hpp`,
search (Cmd+F): `RoundAlreadyOver`
→ found near line 138, with comment mentioning audit F-03.
Then search `Tests/IsolynEngineBridgeTests/SmokeTest.cpp` for
`refuses a finished round` → 4 test lines exist.
*Proves:* the "play past the win" hole is closed AND regression-tested.

**PROOF 6 — Match scoring exists**
Search `Sources/IsolynEngineBridge/include/IsolynBridge.hpp` for
`bridge_match_record_round` → function declared (~line 309) with a long
comment block. Search `Tests/IsolynEngineBridgeTests/SmokeTest.cpp` for
`running scores across rounds` → live test drives TWO rounds and rejects a
duplicate recording.
*Proves:* multi-round matches are real, tested mechanics.

**PROOF 7 — Reveal data can't leak mid-game**
Same header, search `finalHandValues`. Comment says populated ONLY when
outcome ≠ InProgress, zeros otherwise. Cross-check C++ side:
`grep -n "cachedRoundOutcome != RoundOutcomeDTO::InProgress" Sources/IsolynEngineBridge/IsolynBridge.cpp`
→ appears inside snapshot building right above the populate loop.
*Proves:* hidden information stays hidden structurally.

**PROOF 8 — The game screen is wired (not vaporware)**
Search `Sources/IsolynApp/RootView.swift` for `GameBoardView` → routed.
Folder `Sources/IsolynApp/Game/` contains six .swift files totaling ~46 KB.
Search `GamePlaceholderView` anywhere in `Sources/` → **zero hits**
(deleted; menu path now leads somewhere real).
*Proves:* "click Start → play" is genuine.

**PROOF 9 — History is public-verifiable**
```
git log --oneline
```
Expect exactly:
```
0d63200 feat(game): playable hot-seat board (Phase 2)
0c6cc40 feat: match orchestration across rounds (Phase 1c)
577ad78 feat(bridge): RoundAlreadyOver terminal-state guard (audit F-03)
fd98300 fix: repair verification harness for macOS (audit F-02)
b79a3f4 chore: initialize repository with audited green baseline
cca7d42 Initial commit
```
And `git status` → clean tree.
*Proves:* every claim maps to a reviewable diff: `git show <hash>`.

**PROOF 10 — Nothing heavy hides in git**
```
du -sh .git
```
≈ 1 MB. The 597 MB incident was compiler residue OUTSIDE git (see fix-log
OPS‑03); `.gitignore` blocked it from day one — verify:
`cat .gitignore` lists `.build/`, `build/`.

---

## 7. HOUSE RULES (inherited from early production — still law)

1. **Never claim it works without running it.** Show the command output.
2. **Never invent probabilities or rules.** Ambiguity → flag it in comments +
   tell the owner. Guessing = forbidden.
3. **No placeholder code.** If it's not built, SAY so (docs above all do).
4. **Zip/commit after every meaningful chunk.** History lesson at top of
   §5.2 explains why this is survival, not preference.
5. **DifficultyModel needs owner confirmation before building.** Roadmap
   adoption counted as that confirmation once; re-confirm per-session anyway.
6. NEW (this session): **engine stays the only place game truth is computed.**
   Swift may display, never decide. If you feel tempted to add scoring math
   to Swift — stop; extend the bridge instead.
7. NEW (owner directive, core-hardening session): **test and script freely,
   but erase every artifact when the session or phase ends.** Run as many
   builds, tests, sanitizers, and Unix scripts as the work needs — then leave
   ZERO generated weight behind. `./clean.sh` removes `.build/`, `build/`,
   `.DS_Store` and nothing else; steady-state folder ≈ 10 MB. This rule exists
   because residue hit 597 MB twice (OPS-03) before being caught (OPS-07).
8. NEW (owner directive, same session): **fix-log.md, tree.md, and graphify
   must always match the exact project state at the end of every session or
   phase.** Concretely: append protocol-format entries to fix-log.md;
   regenerate tree.md from a fresh `tree` listing; run `graphify update . --force`
   so the code graph reflects reality. A stale map is a false map.

---

## 8. IF YOU ARE A WEAK AI (or cautious human): DO EXACTLY THIS

1. Run PROOFS 1–4 above. If any output differs → STOP, report the mismatch
   verbatim, change nothing.
2. Read `fix-log.md` top-to-bottom once. It is the map of recent mines.
3. Only then read code — starting with `Sources/IsolynEngine/include/*.hpp`
   comments (they explain intent better than any external doc).
4. Make ONE small change at a time. After each: rerun PROOFS 1–3. Green?
   `git add -A && git commit -m "clear description"` before the next change.
5. Never edit `Sources/IsolynEngine/` without also adding/updating a test in
   `Tests/IsolynEngineTests/`.
6. When unsure between two readings of any rule, choose neither — write the
   question down in §5's ambiguity-listing style and ASK THE OWNER.
7. Next planned work = Phase 3 of `../isolyn roadmap.md` (AI opponent via
   DifficultyModel). Its spec, acceptance ladder, and calibration harness
   requirements are already written there — follow them literally.

---

## 9. GLOSSARY (jargon → plain)

- **commit / git / push** — save-point / save-point system / upload save-points to GitHub
- **compile / build** — translate human-readable code into machine-executable form
- **test suite** — robot that automatically checks the program behaves as documented
- **sanitizer (ASan/TSan/UBSan)** — special builds that catch memory/threading crimes at runtime
- **fuzzing** — feeding millions of random/garbage inputs hunting crashes
- **actor (@MainActor)** — Swift lane ensuring only one thing touches data at a time
- **DTO / POD** — plain data envelope with no logic; safe to pass across the bridge
- **bridge** — the narrow guarded doorway between Swift world and C++ world
- **SPM (.build/)** — Swift Package Manager; its build folder is disposable cache
- **assert vs Release** — debug-mode tripwire that VANISHES in shipped builds; never trust it as the only guard (why FIX‑type guards live bridge-side)
- **anchor** — a unique search string used instead of line numbers, because line numbers rot but text persists

---

*End of legacy handoff. If Proofs 1–4 all pass on your machine, you are
standing on solid ground. Welcome to Isolyn.* 🎴
