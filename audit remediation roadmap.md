# ISOLYN AUDIT REMEDIATION ROADMAP

**Purpose:** fix every finding from the ox-alpha full-read audit (findings **OA-1…OA-5**, delivered 2026‑08‑25) so the tree is measurement-honest, doc-honest, analytically correct, and geometrically resilient before any feature work resumes.
**Companion to:** `isolyn roadmap.md` (feature roadmap — UNCHANGED, still governs Phases 3–7 feature work; this document contains ZERO features) · `legacy handoff.md` (house rules — ALL binding) · `fix-log.md` (protocol-format entries land here per fix) · `isolyn current audit.md` (the prior audit whose findings are already fully resolved — nothing in this document re-opens F-series items).
**Baseline (verified live this session, on-target macOS):** `run_tests.sh` → **362/362**, zero warnings · `run_bridge_tests.sh` → **58/58** (caveat: SoakTest contributes 0 checks on macOS — that is OA-1) · `swift build` → **zero warnings** · `swift test` → **35 tests, 1 honest skip, 0 failures** · git clean · folder restored steady-state via `clean.sh`.
**Owner directive:** descending workload per phase. Heavy lifting exhausted by Phase 3; Phases 4–6 shrink to sweeps, conversations, and paperwork. Total budget ≈ one working day.

---

## SCOPE BOUNDARY (read first)

This roadmap contains **zero new gameplay features and zero visual redesign**. Everything here makes existing code correct, measurable, honest, or resilient:

| Category | Included | Excluded |
|---|---|---|
| Measurement | OA-1 (macOS soak test is a silent no-op) | New test frameworks |
| Correctness | OA-3 (resolver probability math overstates fidelity) | Any rules/engine change |
| Resilience | OA-4 (long chains exceed board/camera bounds — closes mandate §17 compliance) | Visual redesign of the signed-off board |
| Honesty | OA-2 (stale "never compiled" caveats now proven false) | Rewriting history — annotate, never falsify |
| Decisions | OA-5 (ambiguity #6/#8, approximation acceptance, weights sequencing) | Implementing #8 before the owner rules |
| Process | Tagging the first fully-machine-verified baseline | Feature work of any kind |

AI/DifficultyModel, Sandbox, Training, packaging execution remain governed by `isolyn roadmap.md` and come after this document is done. When this closes, the only remaining work in the entire project is that feature roadmap — exactly the "easy work and niche features" end-state the owner asked for.

---

## DEPENDENCY LOGIC (why this order and no other)

```
P1 ──► P4    P4's doc updates CITE P1's recorded macOS soak numbers
 │            (a doc claiming "soak verified on macOS" written before
 │            P1 lands would itself be a claimed-vs-real divergence —
 │            the exact thing this project hunts).
 └──► P2 ──► P3
       │      P2 builds the GameSnapshot TEST SEAM (internal-init access);
       │      P3's new resolver test suite consumes that same seam.
       │      Building it twice, or in P3 first, wastes the ordering.
P5 ──► P6    closeout tags/syncs whatever P5's rulings produced.
```

Sizing is strictly descending within that skeleton: P1 carries the only genuine systems-programming lift; P2 carries layout math + a visual-QA loop; P3 is one function + its new test file; P4 is annotated doc edits; P5 is a conversation captured in writing; P6 is commands.

---

## STEP 0 — HYGIENE GATE *(minutes — do before anything else)*

1. Re-pin the baseline verbatim (house rule §8.1): `./run_tests.sh` → 362/362 · `./run_bridge_tests.sh` → 58/58 · `swift build` zero warnings · `swift test` → 35/0-failures/1-skip. If ANY differs → STOP, report mismatch verbatim, change nothing.
2. `git status` must be clean. Commit this roadmap file itself first (`docs: adopt audit remediation roadmap`) so every subsequent diff maps to a reviewable intent.
3. Note for closeout: adding this file made `tree.md` stale by exactly one entry — rule-8 sync is scheduled as P6's job, not skipped.

---

## PHASE 1 — MEASUREMENT TRUTH: THE SOAK TEST MUST ACTUALLY MEASURE ON MACOS *(~30% — heaviest; the only systems-code lift)*

**Objective:** OA-1. `Tests/IsolynEngineBridgeTests/SoakTest.cpp` reads RSS exclusively from `/proc/self/status` (Linux-only). On macOS — the SHIPPING platform, and the only platform CI runs on — `currentRssKb()` returns −1, the test prints `[inconclusive]`, exits 0, and `run_bridge_tests.sh` counts it as a passing executable contributing zero checks. The "12,000 cycles, flat memory" claim is therefore currently unreproducible on the machine everyone actually uses. Every other claim in this project survived live re-verification; this one didn't, and the fix is known.

### 1a. Darwin RSS reader
- File: `Tests/IsolynEngineBridgeTests/SoakTest.cpp` (anchor: `currentRssKb`).
- Add a `#elif defined(__APPLE__)` branch using Mach task introspection: `mach_task_self()` + `task_info(MACH_TASK_BASIC_INFO)` → `resident_size` bytes → KB. Keep the `/proc/self/status` path for Linux unchanged. On any other platform, return −1 as today.
- Include-note: `<mach/mach.h>` behind the Apple guard; no new link flags required (libSystem).

### 1b. Make "couldn't measure" loud instead of silently green
- Today an inconclusive run exits 0 and prints one quiet line — indistinguishable from a pass in a scrolled log.
- Post-fix behavior: inconclusive STILL exits 0 (never false-fail an exotic environment) but prints a `*** WARNING: RSS measurement unavailable on this platform — leak signal ABSENT from this run ***` banner that greps loudly. On Linux + macOS — the two platforms this project has ever run on — inconclusive should simply never happen again; if it does, something platform-shaped changed and the log must scream.

### 1c. Verify the measurement is REAL before trusting it
- Run the soak on macOS (`./run_bridge_tests.sh`, then a manual 2,000-cycle run) and confirm: real KB values print, warmup-vs-end deltas behave sanely, and the 500 B/cycle threshold verdict is computed from actual numbers.
- Cross-check against an independent detector: one ASan run of SmokeTest + SoakTest (`./run_sanitize.sh address`) — ASan's leak checker is the second opinion that the flat curve isn't hiding anything.
- Record both outputs verbatim in the fix-log entry — they are the receipts P4 will cite.

### Exit criteria (all of Phase 1)
- `grep -n "__APPLE__" Tests/IsolynEngineBridgeTests/SoakTest.cpp` finds the Mach branch; `/proc` path intact for Linux.
- macOS `./run_bridge_tests.sh` output shows SoakTest printing real VmRSS numbers and a computed growth-per-cycle figure — pasted verbatim into `fix-log.md`.
- Engine suite untouched-green (362/362); bridge suite green with the soak NOW CONTRIBUTING A REAL VERDICT.
- One commit: `fix(soak): darwin RSS measurement — macOS soak test measures instead of passing silently (audit OA-1)`.

---

## PHASE 2 — BOARD GEOMETRY RESILIENCE + THE SNAPSHOT TEST SEAM *(~25%)*

**Objective:** OA-4. A pathological near-full-board chain lays out rows downward without limit while `BoardCamera` caps pan at ±300/±200 — worst case, the tail end renders out of reachable view. This is rare, cosmetic, and it is also the LAST UNCLOSED ITEM of `dominoes_ui_fix_non_negotiable.md` §17 ("scale the board intelligently … prevent horizontal overflow … avoid crushing dominoes"): the mandate's responsive clause was never finished because the failure needed a huge chain to appear. Fixing it COMPLETES the signed-off mandate rather than reopening it.

### 2a. Extract pure layout metrics (testability first)
- File: `Sources/IsolynApp/Game/ChainAndZonesView.swift` (anchor: `computeLayout`).
- Hoist the extent calculation into a pure, internal-static function: given tile sequence + available size, returns `{placed, headPos, tailPos, contentWidth, contentHeight, suggestedScale}`. `SnakeChainBoard.body` consumes it unchanged — zero rendering-behavior change intended or permitted in this sub-step.

### 2b. Auto-fit scale (uniform ⇒ the 2:1 law survives)
- When `contentHeight` (including perpendicular-double protrusion and marker clearance) exceeds ~94% of available height, apply ONE uniform `scaleEffect(suggestedScale)` to the board plane, clamped to `0.62…1.0`. Uniform scaling multiplies both axes equally — a 56×28 tile stays exactly 2:1 at every scale, so mandate §2/§3 cannot be violated BY CONSTRUCTION. Below the clamp floor, stop shrinking and let the extended pan range (2d) take over — never crush dominoes into unreadability (§17's own priority order).

### 2c. Content-aware camera bounds
- Files: `ChainAndZonesView.swift`, `BoardCamera.swift`.
- Feed the POST-scale residual overflow back into the camera: `maxOffsetY` (and X, symmetrically) grows to cover half the residual overflow beyond the default bounds. Panning then always reaches the tail. Implementation shape: the layout pass reports fitted extents up through a closure; the game screen sets them on the camera. No gesture/hover/arbitration logic changes — those systems were hardened separately and stay orthogonal (FIX-26 contract intact).

### 2d. The GameSnapshot TEST SEAM (shared infrastructure with Phase 3)
- File: `Sources/IsolynApp/Engine/EngineTypes.swift` (anchor: `fileprivate init?(dto:`).
- Widen `GameSnapshot.init?(dto:)` from `fileprivate` to internal. Justification, stated plainly: `@testable import` reaches internal, never fileprivate — without this, NO headless test can fabricate a snapshot, and neither this phase nor Phase 3 can unit-test anything. Zero runtime behavior change; one word. Anchor-comment the widening with this paragraph's reasoning so a future reader doesn't "tidy" it back.

### Exit criteria (all of Phase 2)
- New `Tests/IsolynAppTests/BoardLayoutTests.swift`: pure-metric assertions — N-tile chains produce expected row counts/extents; scale engages only past the height threshold; scale NEVER breaks 2:1 (assert `fittedTileLongAxis == 2 × fittedShortAxis` within epsilon at min/max/engaged scale); camera bounds grow monotonically with residual overflow.
- Code-level §29-step-7 interaction trace re-walked (select/deselect/marker/place/invalid/draw/analyze/pass paths resolve unchanged).
- `swift test` green including the new suite; `swift build` zero warnings.
- Commits: 2a+2d one commit (pure extraction + seam), 2b+2c second (behavior), tests ride with their subject.

---

## PHASE 3 — ANALYTICAL LENS CORRECTNESS: RESOLVER PROBABILITY MATH *(~18%)*

**Objective:** OA-3. `TileKnowledgeResolver.predictedOpponentProbability` computes `combinedProbability / numOpponents` — a number that ignores differing hand sizes and therefore matches NEITHER BeliefState's proportional-share math NOR any honest reading of "probability an opponent holds this tile." Its comment claims it "mirrors BeliefState's construction math"; BeliefState's constructor weights each location by its share of the unseen pool. Harmless behind the 0.35 threshold today, but this project's standard is that comments never overstate fidelity — and the hover-chain is the player-facing face of exactly that belief machinery.

### 3a. Fix the math to match the claim (or the claim to match the math — math wins)
- File: `Sources/IsolynApp/Game/HoverChain/TileKnowledgeResolver.swift` (anchor: `predictedOpponentProbability`).
- New semantics, stated in the doc comment: *"probability that the SINGLE MOST-LIKELY opponent holds this tile"* = `max over opponents p of (otherHandSizes[p] / totalUnseenTiles)`. This is exactly BeliefState-constructor proportional allocation, evaluated per opponent — the comment and the code finally say the same true thing. Return nil under the same degenerate conditions as today (no unseen tiles, no opponents).
- `HoverChainOverlay.knowledgeLabel` already prints a percentage; its wording stays truthful under the new definition (verify, adjust one string if needed).

### 3b. Regression suite — the resolver gets its FIRST tests ever
- New file: `Tests/IsolynAppTests/TileKnowledgeResolverTests.swift`, consuming Phase 2d's snapshot seam.
- Coverage (each a named check):
  1. Family completeness: every pip 0–6 yields exactly 7 family members, doubles included exactly once.
  2. Precedence chain: a tile on the chain classifies `.historical` even when it's ALSO inferable-predicted; own-hand beats locked-off; locked-off requires dry yard + non-empty chain (empty-chain case explicitly `.unknown`-ward).
  3. Prediction math, hand-derived: crafted 1v1 snapshot, opponent holding 6 of 13 unseen → `6/13`; unequal-hand 1v1v1 case proving max-per-opponent beats the old averaged formula; boundary at `PredictivePolicy.predictionThreshold` (≥ classifies, < doesn't).
  4. Degenerate inputs: zero unseen, zero opponents → nil-path → `.unknown`, never a crash, never a fabricated percentage.
- House rule honored: tests derived from the SAME first-principles derivation BeliefState.cpp documents, so app-layer and engine-layer math are pinned to one shared truth.

### Exit criteria (all of Phase 3)
- Old formula string `combinedProbability` gone (grep-clean); new per-opponent-max present with the corrected doc comment.
- New suite green; full `swift test` green; build zero-warning.
- One commit: `fix(hoverchain): resolver predicts per-opponent share, matching BeliefState semantics + first resolver test suite (audit OA-3)`.

---

## PHASE 4 — DOC-TRUTH SWEEP: RETIRE THE "NEVER COMPILED" ERA *(~15%)*

**Objective:** OA-2. Every document below was TRUE when written — that epistemic discipline is why this repo's docs are trustworthy — and every one is now FALSE in the same way: the Swift/Cxx boundary compiled clean and its test suite ran green on target hardware. Per house style, history is annotated, never rewritten: each site gets a short dated resolution note, preserving the original claim as a record of what was believed and why.

Inventory (each item: file → anchor → action):

1. `Package.swift` → IsolynApp target comment ("has NOT been verified by an actual Swift/Xcode compile…") and IsolynAppTests comment ("NOT been re-verified…") → append: *RESOLVED 2026‑08‑25: compiled zero-warning and tested green on macOS/Xcode; interop spelling and tuple-import behavior confirmed.*
2. `Sources/IsolynApp/Engine/EngineTypes.swift` → header block ("have NEVER been compiled…") → resolution note atop the two uncertainties; KEEP the explanations (tuple-as-tuple layout rationale remains the best documentation of WHY `withTupleAsArray` exists).
3. `Sources/IsolynApp/Engine/EngineSession.swift` → pointer comment referencing EngineTypes' uncertainties → one-line resolution pointer.
4. `docs/BRIDGE_TESTING.md` → Environment section ("no Swift toolchain, ever") + "What has not been done" (Swift-side testing line) → resolution note + replace the Swift-side-testing absence with the CURRENT truth (35 swift tests green, incl. headless gameplay through the real bridge), citing Step-0 outputs.
5. `docs/BRIDGE_ARCHITECTURE.md` → threading-section parenthetical + "Everything Swift-compiler-dependent" out-of-scope bullet → resolution note; move the actor-discipline item from "unverifiable" to "compiler-enforced and exercised."
6. `legacy handoff.md` → §2 scoreboard (add a verified-this-session column/row), §5.6 timeline tail (one closing sentence), §6 proofs (numbers already correct — add "re-confirmed 2026‑08‑25 on macOS") → minimal annotations.
7. `docs/RELEASE_CHECKLIST.md` — checked-for-relevance, expected UNCHANGED (packaging substrate genuinely still absent; F-05 stays "grounded, not closed").
8. `isolyn current audit.md` → append `Appendix E — Swift-boundary closure (2026‑08‑25)`: two paragraphs, the F-01-era uncertainty formally retired, citing the four green gates. History above untouched.

### Exit criteria (all of Phase 4)
- Repo-wide grep for `NEVER been compiled` / `never been available` / `not been verified` returns only sites carrying a dated RESOLVED annotation (or genuinely-still-true statements — e.g., Training/Sandbox absence).
- Every doc edit cites the SAME recorded Step-0 numbers (one source, no drift between documents).
- Docs-only commit(s): `docs: retire never-compiled era — annotate resolved interop unknowns (audit OA-2)`.

---

## PHASE 5 — OPEN-DECISIONS LEDGER *(~7% — a structured conversation, captured in writing)*

**Objective:** OA-5. Four carried items need an OWNER RULING or an explicit acceptance — not code yet. Deliverable: `docs/OPEN_DECISIONS.md`, one page per question in the ambiguity-listing style of handoff §5.3 (background → options → recommendation → implementation cost once ruled). Implement NOTHING from this phase except items the owner rules on IN-session AND which cost ≤ a few lines (listed per item).

1. **Ambiguity #6 — all-doubles-round closer (1v1).** Current fallback credits the last player. Options: (a) keep, (b) declare such rounds closeless with starter = dealer's-left convention (INVENTED rule — violates never-invent), (c) escalate to source-document review. Recommendation: keep (a); it's flagged in-place, astronomically rare, and reversible. Cost to flip if overruled: one comparison in `RulesEngine::determineCloser` + two test cases.
2. **Ambiguity #8 — One Domino Rule mechanics.** Genuinely underspecified (how a Domino victory occurs INSIDE a draw-one/play-one ritual). Present the three worked readings side-by-side with concrete tile traces; recommend a physical-tiles walkthrough with the owner before ANY implementation. Explicitly OUT of implementation scope until ruled — this is the one item where guessing would violate the never-invent rule in gameplay-visible ways.
3. **`probabilityHoldsAtLeast` independence approximation.** Recommend ACCEPT-as-documented (≤7 Bernoulli trials, exact DP over the approximation, marginals feed explainability — while SEARCH-critical worlds come from capacity-exact Determinizer sampling and are unaffected). Alternative (joint-exact via iterative proportional fitting) priced honestly: days of work, zero search-quality delta, marginal explanation-precision gain. Owner may simply initial the acceptance in this file.
4. **Evaluation weights sequencing.** Not a new decision — CONFIRM that placeholder 1.0 weights stay frozen until `isolyn roadmap.md` Phase 3's calibration harness exists (changing evaluation while introducing opponents confounds the ladder signals — already documented there). One checkbox.

### Exit criteria (all of Phase 5)
- `docs/OPEN_DECISIONS.md` exists; every item carries either an owner ruling or a dated recommendation awaiting one.
- Any ≤-few-line rulings implemented WITH their tests in the same commit; everything else explicitly deferred with a pointer from handoff §5.5 to the new file (§5.5 edited to reference it — the map must not fork).
- One commit: `docs: open-decisions ledger — ambiguity #6/#8, approximation acceptance, weights sequencing (audit OA-5)`.

---

## PHASE 6 — CLOSEOUT: TAG, SYNC, LEAVE NO TRACE *(~5%)*

1. **Fix-log entries** in the 12-field protocol format: FIX-27 (OA-1, citing the recorded macOS soak outputs), FIX-28 (OA-4 + BoardLayoutTests anchor), FIX-29 (OA-3 + resolver-suite anchor), FIX-30 (OA-2 doc inventory compressed), OPS-09 (Open-Decisions ledger + any rulings).
2. **Tag the baseline:** `git tag audit-remediated-1 && git push origin main --tags`. This is the first tag in history where EVERY layer — engine, bridge, Swift consumer, environment, UI geometry, and now the measurement harness itself — is machine-verified on the shipping platform. Name it so the feature roadmap starts from an immutable, citable state.
3. **Rule-8 map sync:** regenerate `tree.md` from a fresh listing (now including this roadmap + the two new test files + OPEN_DECISIONS.md); `graphify update . --force`; verify node/edge counts moved plausibly.
4. **Final gates, verbatim into the session log:** `./run_tests.sh` · `./run_bridge_tests.sh` (soak now printing real numbers) · `swift build` · `swift test`.
5. **`./clean.sh`** — zero residue handed back (OPS-03/OPS-07 lesson, permanently applied).

---

## EFFORT SUMMARY

| Phase | Title | % | Character |
|---|---|---|---|
| 0 | Hygiene gate | — | minutes |
| 1 | Soak-test measurement truth (OA-1) | **30%** | only real systems lift: Mach APIs, honest reporting, recorded receipts |
| 2 | Board resilience + snapshot seam (OA-4) | **25%** | layout math, uniform-scale law preservation, camera coupling, QA loop |
| 3 | Resolver math + first test suite (OA-3) | **18%** | one function aligned to BeliefState semantics + brand-new coverage |
| 4 | Doc-truth sweep (OA-2) | **15%** | eight annotated sites, one shared set of cited numbers |
| 5 | Open-decisions ledger (OA-5) | **7%** | writing down what only the owner can decide |
| 6 | Closeout: tag, sync, clean | **5%** | commands and paperwork |

Strictly descending ✓ · heavy lifting exhausted by Phase 3 ✓ · zero features ✓ · hands off to `isolyn roadmap.md` Phase 3 (AI) with a fully-remediated, tagged base ✓.

## RISK REGISTER

1. **P1's Mach reader could disagree with Linux numbers** (different accounting: resident vs. proportional share). Mitigation: the 500 B/cycle threshold has enormous headroom; the acceptance is "real, stable, plausible numbers," not byte-equality across OSes — say THAT in the fix-log entry.
2. **P2 touches the visually-signed-off board.** Mitigation: 2a is provably behavior-neutral (pure extraction, consumed identically); 2b activates ONLY past the overflow threshold ordinary games never reach; §29-step-7 trace re-walked; owner eyeballs the long-chain case once, same sign-off pattern as UI-QA.
3. **P2d's visibility widening could be reverted as "tidying."** Mitigation: the anchor comment states the test-seam justification verbatim; BoardLayoutTests + TileKnowledgeResolverTests FAIL TO COMPILE if it regresses — the suite IS the guardrail.
4. **P5's #8 discussion spawns implementation pressure mid-phase.** Mitigation: scope table is binding — no One-Domino-Rule code until ruled, per the never-invent rule; the ledger captures the conversation instead.
5. **Scope gravity toward AI features.** Mitigation: `isolyn roadmap.md` Phase 3 is fully specified and waiting; this document's exit criteria end at a tag.

## EXPLICITLY DEFERRED (post-roadmap, governed by isolyn roadmap.md)

DifficultyModel/AI turns + calibration harness (P3) · PositionConstructor/Sandbox (P4) · ExplanationEngine/Training (P5) · drag-and-drop placement · packaging/app-shell execution (checklist ready) · One Domino Rule IMPLEMENTATION (blocked on its P5 ruling, not on code).

---

*House rules in force throughout: Finality doctrine before edits · prove every claim with shown command output · commit after every meaningful chunk · engine changes land test-first (none anticipated — if one appears, the rule wakes up) · docs match reality at every boundary (P6 executes rule 8) · when torn between readings, stop and ask the owner.*
