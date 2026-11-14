# Documentation Audit — 2026-11-13

**Purpose:** establish which documents are true, which are stale, which duplicate
each other, and what each one is for. Every verdict below is grounded in a
measurement or a quoted line, not in the document's own authority.

**Scope:** 29 markdown files (no `.doc` files exist in this repository; there is
one PDF, a rendering of the 2026-08-24 audit). Includes the five generated
`graphify-out/GRAPH_REPORT.md` files and the three component READMEs.

---

## 1. Authority model

Documents do not all have equal standing. Where two disagree, the higher tier wins:

| Tier | Source | Rationale |
|---:|---|---|
| 1 | Running code and its output (`swift test`, `./run_tests.sh`, `git log`) | Reproducible; cannot be argued with |
| 2 | `docs/audits/2026-11-13-audit.md` | Point-in-time measurement of the current tree, with per-claim evidence |
| 3 | Living docs (`architecture/`, `engineering/`, `subsystems/`, `design/UI_CHARTER.md`) | Must be updated in the same change as the code they describe |
| 4 | Plans (`roadmaps/`) | Intent, not status; never evidence of completion |
| 5 | History (`history/`) | Frozen receipts; accurate only for the date they record |
| 6 | Generated (`graphify-out/`) | Derived, regenerable, may lag the tree |

A claim in tier 3 that contradicts tier 1 is a defect in the document. A claim in
tier 5 that contradicts tier 1 is expected and is labelled as such.

---

## 2. Verdict register

| # | Document | Type | Verified | Fate | Action taken |
|---:|---|---|---|---|---|
| A1 | `README.md` | Entry point | Updated | **Update** | Status rewritten to 57.5%, corrected ladder claim, audits linked |
| A2 | `docs/README.md` | Index | Rebuilt | **Restructure** | Becomes the navigation and authority hub |
| A3 | `architecture/BRIDGE_ARCHITECTURE.md` | Living | Corrected | **Update** | 426→429, 68→75, AUD-01 gap added |
| A4 | `architecture/FEATURE_SPECS.md` | Specification | Accurate | **Retain** | Status banner added (unimplemented) |
| A5 | `architecture/PROJECT_INVENTORY.md` | Living | Corrected | **Update** | LOC table and file counts re-measured |
| A6 | `engineering/BRIDGE_TESTING.md` | Living | Corrected | **Update** | 426→429, 68→75, 494→502, 95→100, coverage gap added |
| A7 | `engineering/OPEN_DECISIONS.md` | ADR log | Accurate | **Retain** | No change; ADR-002/003 statuses match reality |
| A8 | `engineering/RELEASE_CHECKLIST.md` | Checklist | Accurate | **Retain** | No change; "nothing exists yet" still true |
| A9 | `design/STRATEGY_NOTES.md` | Domain knowledge | Accurate | **Retain** | Status banner added (mostly unimplemented) |
| A10 | `design/UI_CHARTER.md` | Living design | Accurate | **Restructure** | Renamed from `UI_UX_OVERHAUL.md`; precedence block added |
| A11 | `subsystems/ACCELERATOR.md` | Living | Accurate | **Retain** | Throughput range matches re-measurement |
| A12 | `subsystems/LAB.md` | Living | **False claim removed** | **Update** | Ladder table replaced with recomputed values; monotonic claim retracted |
| A13 | `roadmaps/strategy-roadmap.md` | Plan | Partially stale | **Restructure** | Status banner, depth 6→8, 10.7M dated |
| A14 | `audits/2026-08-24-audit.md` | Historical audit | Superseded | **Retain** | Superseded banner added; numbers frozen |
| A15 | `audits/2026-11-13-audit.md` | **Source of truth** | Current | **Retain** | No change; this audit's reference |
| A16 | `history/2026-08-ui-rebuild-mandate.md` | Historical mandate | Executed | **Restructure** | Moved out of `design/`; binding clauses scoped; "not a live order" |
| A17 | `history/fix-log.md` | Historical receipts | Accurate for its dates | **Retain** | Append-only; scope banner already implied by §22 of the audit |
| A18 | `history/legacy-handoff.md` | Historical onboarding | Stale numbers | **Restructure** | Banner; §2 retitled as a 2026-08 snapshot |
| A19 | `history/roadmaps/audit-remediation-roadmap.md` | Completed plan | Executed | **Restructure** | Moved to history; completed banner |
| A20 | `history/roadmaps/core-hardening-roadmap.md` | Completed plan | Executed | **Restructure** | Moved to history; completed banner |
| A21 | `history/repo-tree-2026-08.md` | Generated snapshot | Stale + misleading | **Delete** | Removed (`git rm`); regenerable, and house rule #8 requires it match reality |
| A22 | `lab/README.md` | Component | One stale claim | **Update** | "Elo ladder is scaffold" corrected |
| A23 | `tools/selfplay/README.md` | Component | Accurate | **Retain** | Commands and CSV schema match the binary |
| A24 | `Accelerator/README.md` | Component | Accurate | **Retain** | Consistent with `ACCELERATOR.md` |
| A25–A29 | `graphify-out/**/GRAPH_REPORT.md` (×5) | Generated | Derived | **Retain in place** | Not documentation; excluded from the knowledge graph |

---

## 3. Contradiction register

Each entry: the conflict, the evidence, and which side wins.

| # | Conflict | Evidence | Resolution |
|---:|---|---|---|
| C1 | `LAB.md` claims 3/16 beats 4/24 190–210 (−17.4 Elo) | `ladder-900-1600.csv` → A 202, B 198, **+3.5** | **Data wins.** Table corrected |
| C2 | `LAB.md` claims 4/24 beats 5/40 196–204 (−6.9) | `ladder-1600-2300.csv` → A 205, B 195, **+8.7** | **Data wins.** Table corrected |
| C3 | `LAB.md` claims "directionally monotonic" | Two of three adjacent pairs favour the shallower side | **Claim retracted** |
| C4 | `BRIDGE_ARCHITECTURE.md` says 426 engine checks | `./run_tests.sh` → **429** | Code wins. Corrected |
| C5 | `BRIDGE_ARCHITECTURE.md` says 68 Swift tests | `swift test` → **75 tests, 1 skipped** | Code wins. Corrected |
| C6 | `BRIDGE_TESTING.md` says 426 checks | 429 | Corrected |
| C7 | `BRIDGE_TESTING.md` says 68 tests | 75 | Corrected |
| C8 | `BRIDGE_TESTING.md` says 494 sanitizer checks | 502 | Corrected |
| C9 | `BRIDGE_TESTING.md` says 95 accelerator checks | 100 | Corrected |
| C10 | `PROJECT_INVENTORY.md` engine 50/3,766 | **50/3,842** | Re-measured |
| C11 | `PROJECT_INVENTORY.md` bridge 2/1,054 | **2/1,082** | Re-measured |
| C12 | `PROJECT_INVENTORY.md` app 47/5,869 | **56/7,424** | Re-measured; 9 files of UI work unaccounted for |
| C13 | `PROJECT_INVENTORY.md` tests 29/4,056 | **35/4,597** | Re-measured |
| C14 | `PROJECT_INVENTORY.md` accelerator 13/1,640 | **13/1,702** | Re-measured |
| C15 | `PROJECT_INVENTORY.md` total 160/20,284 | **175/22,546** | Re-measured |
| C16 | `PROJECT_INVENTORY.md` GameViewModel 539 lines | **636** | Corrected |
| C17 | `strategy-roadmap.md` tier 2300–3000 = depth 6 | `DifficultyModel.hpp` returns `{8, 64}` | Code wins. Corrected |
| C18 | `strategy-roadmap.md` baseline 356/356, 33/33, 25/25 | 429/73/75 | Frozen as plan baseline; banner added |
| C19 | `strategy-roadmap.md` "10.7M concurrent queries" | Measured 2026-08-24; 2.2–6.7M on 2026-11-13 | Dated, both figures retained |
| C20 | `legacy-handoff.md` 380/380, 68/68 | 429/73 | Banner + §2 retitled as snapshot |
| C21 | `ci.yml` labels 380 / 68 checks | 429 / 73 | Corrected (documentation of the pipeline) |
| C22 | `README.md` "Late alpha" | 57.5%, two modes absent, no packaging | Reworded to prototype + audit link |
| C23 | `lab/README.md` "Elo ladder is still scaffold" | `calibration.py` computes Elo with CIs | Corrected |
| C24 | `IsolynBridge.hpp` says match state is "not owned or wired" | `bridge_match_record_round` exists | **Unresolved** — code comment, not a document. Logged in audit §10 D12 |
| C25 | `EngineSession.swift` says "round-scoped, not match-scoped" | Same file defines `recordRoundInto(matchHandle:)` | **Unresolved** — code comment. Audit §10 D13 |

---

## 4. Per-document findings

### A1. `README.md`
- **What:** product identity, run command, layer map, key documents, status.
- **Why:** the first file a visitor opens; carries the project's public claim.
- **How:** prose, no measurements of its own.
- **Where:** derives from `Package.swift`, the source tree, and the audit.
- **Validity:** structure accurate; status was stale ("Late alpha", unqualified ladder claim).
- **Fate:** Update — status now states 57.5%, names what is absent, links the audit.

### A2. `docs/README.md`
- **What:** navigation index for every document.
- **Why:** without it the corpus is a flat list of 20 files.
- **How:** curated tables and a hierarchy.
- **Where:** must agree with the filesystem.
- **Validity:** was accurate for the layout it described; rebuilt to carry the authority model and register.
- **Fate:** Restructure.

### A3. `architecture/BRIDGE_ARCHITECTURE.md`
- **What:** the C++/Swift boundary: why POD, handles, state versions, cancellation, snapshot isolation, match surface.
- **Why:** the header is the contract; this explains the reasoning behind it.
- **How:** derived by reading the `.cpp` files, with specific mechanisms named.
- **Where:** `IsolynBridge.cpp`, `IsolynBridge.hpp`, `EngineSession.swift`.
- **Validity:** substantively excellent and still accurate on design; two counts were stale, and it did not mention the mode-mismatch hole.
- **Fate:** Update — counts corrected, AUD-01 gap documented.

### A4. `architecture/FEATURE_SPECS.md`
- **What:** intended Training and Sandbox behaviour, including wrong-move handling and the live eval bar.
- **Why:** captures product intent that would otherwise be lost before implementation.
- **How:** transcribed requirements from the owner, explicitly future-facing.
- **Where:** no code dependency; names `PositionConstructor` and `ExplanationEngine`, neither of which exists.
- **Validity:** accurate as intent; dangerous only if read as a description of the app.
- **Fate:** Retain with an explicit unimplemented banner.

### A5. `architecture/PROJECT_INVENTORY.md`
- **What:** naming boundary, component LOC table, caller map, key file sizes.
- **Why:** orients a new reader and records the display-name decision.
- **How:** `git ls-files` + `wc -l`, manually transcribed.
- **Where:** the filesystem.
- **Validity:** the naming section is correct and still binding; **every LOC figure was stale** and understated the app by 1,555 lines.
- **Fate:** Update — table re-measured, as-of date and re-measure command added.

### A6. `engineering/BRIDGE_TESTING.md`
- **What:** the verification matrix, what the suite covers, what it does not.
- **Why:** distinguishes "tested" from "claimed".
- **How:** command → result table from real runs.
- **Where:** `run_tests.sh`, `run_bridge_tests.sh`, `swift test`, `run_sanitize.sh`, `Accelerator/build.sh`.
- **Validity:** honest in structure; four counts stale, and it omitted the one path that crashes.
- **Fate:** Update — counts corrected, mode-mismatch gap added to "Not covered".

### A7. `engineering/OPEN_DECISIONS.md`
- **What:** ADR-001..004 (languages, lab, Metal, single source of truth) plus open questions.
- **Why:** the audit had flagged the absence of a decision ledger.
- **How:** context / decision / why / consequences / revisit-when.
- **Where:** consistent with `Package.swift`, `tools/selfplay`, `Accelerator/`.
- **Validity:** statuses match reality, including "trainer scaffolded" and "search integration pending".
- **Fate:** Retain unchanged.

### A8. `engineering/RELEASE_CHECKLIST.md`
- **What:** the pre-researched path from SPM executable to notarized app.
- **Why:** turns release engineering into execution rather than archaeology.
- **How:** itemised, with the exact entitlements, strings and capabilities required.
- **Where:** Apple requirements + `LiveWeatherService` capability notes.
- **Validity:** "NOTHING here exists yet" remains literally true (no app target, no privacy manifest).
- **Fate:** Retain unchanged.

### A9. `design/STRATEGY_NOTES.md`
- **What:** closing-vs-Domino reasoning, 2v2 declarations and partner play, look-ahead depth, match-threshold playstyle.
- **Why:** domain knowledge that would otherwise have to be re-derived.
- **How:** owner interviews and worked examples, explicitly caveated as not validated play.
- **Where:** no code dependency; maps onto `ClosingOpportunityHeuristic` and `ProbabilityEngine`.
- **Validity:** honest about being unverified; but only one component of it is implemented.
- **Fate:** Retain with a "mostly unimplemented" banner.

### A10. `design/UI_CHARTER.md` (was `UI_UX_OVERHAUL.md`)
- **What:** the current design direction: table metaphor, palette, typography, spacing, mode-native layouts, component map, phases.
- **Why:** it is the design authority the UI was rebuilt against.
- **How:** written after the rebuild, grounded in what shipped plus explicit corrections.
- **Where:** `InteractiveGameBoardView`, `ChainAndZonesView`, theme files.
- **Validity:** consistent with the code; its only structural problem was competing with the older mandate.
- **Fate:** Restructure — renamed to `UI_CHARTER`, precedence block added.

### A11. `subsystems/ACCELERATOR.md`
- **What:** Metal backend architecture, parity gates, measured throughput, integration plan.
- **Why:** records a large investment and prevents it being mistaken for a search speedup.
- **How:** standalone harness measurements with batch sizes and ranges.
- **Where:** `Accelerator/`, `./Accelerator/build.sh`.
- **Validity:** accurate; explicitly says it is not wired into search and not a strength claim. Throughput range matches the 2026-11-13 re-measurement.
- **Fate:** Retain.

### A12. `subsystems/LAB.md`
- **What:** lab boundary, components, data contracts, calibration results.
- **Why:** makes strength claims measurable.
- **How:** self-play CSVs plus a Python report.
- **Where:** `tools/selfplay/`, `lab/`.
- **Validity:** **the single most serious documentation defect in the repository.** Three of four ladder rows did not reproduce, and the "directionally monotonic" conclusion was false.
- **Fate:** Update — table recomputed from the committed CSVs, claim retracted, "two tiers" conclusion stated.

### A13. `roadmaps/strategy-roadmap.md`
- **What:** the seven-phase plan of record with effort percentages, dependency graph, risk register.
- **Why:** sequences the remaining work.
- **How:** owner-directed ordering, effort estimates, exit criteria.
- **Where:** prior audit findings F-01…F-12.
- **Validity:** phases 1–2 executed, 3 partially; the header baseline and the depth table were stale.
- **Fate:** Restructure — banner, depth corrected to 8, concurrency figure dated.

### A14. `audits/2026-08-24-audit.md`
- **What:** the first full audit: 12 findings, verification log, resolution ledger.
- **Why:** it is the reason the repo has version control, a working test target and a linkable harness.
- **How:** live reproduction of each failure.
- **Where:** real command output, quoted.
- **Validity:** accurate for 2026-08; every count now differs.
- **Fate:** Retain as history with a superseded banner.

### A15. `audits/2026-11-13-audit.md`
- **What:** current 24-section audit: 57.5%, AUD-01, engine/bridge/UI analysis, roadmap, verdict.
- **Why:** the factual baseline this document audits against.
- **How:** three runs of every suite, six runs of the crash harness, static re-measurement.
- **Where:** commands and line references throughout.
- **Validity:** self-consistent, with its own §22 correction log.
- **Fate:** Retain — **source of truth** (tier 2).

### A16. `history/2026-08-ui-rebuild-mandate.md` (was `design/ui-fix-directive.md`)
- **What:** a 28-section rebuild mandate: single-rectangle law, tile spec, board composition, hand, typography, colour.
- **Why:** it produced the current UI after a rejected one.
- **How:** prescriptive rules with acceptance tests.
- **Where:** cited directly from `ChainAndZonesView`, `HandRackView`, `IsolynDominoTile`.
- **Validity:** executed; but its framing ("REJECT CURRENT UI", "STATUS: CRITICAL") is a live-sounding order attached to a finished job — an agent reading it cold could try to rebuild the UI again.
- **Fate:** Restructure — moved to `history/`, binding sections scoped to §2–§10, explicit "not a live order".

### A17. `history/fix-log.md`
- **What:** 1,095 lines of fix entries with severity, cause, change and verification anchor.
- **Why:** the project's proof that fixes happened.
- **How:** append-only session entries.
- **Where:** each entry cites files and commands.
- **Validity:** accurate as a receipt for its dates; numbers advance between entries (356 → 380 → 386 → 426 → 429), which is correct for a log and wrong if read as current state.
- **Fate:** Retain — append-only history.

### A18. `history/legacy-handoff.md`
- **What:** plain-words orientation, scoreboard, folder map, ambiguity resolutions, house rules, proof commands.
- **Why:** the onboarding document, written so a stranger could resume.
- **How:** narrative plus copy-paste verification blocks.
- **Where:** code comments, `fix-log.md`, command output.
- **Validity:** the house rules and ambiguity resolutions are still binding; the scoreboard (380/380, 68/68) and proof outputs are 2026-08.
- **Fate:** Restructure — banner added, §2 retitled as a snapshot.

### A19–A20. `history/roadmaps/*`
- **What:** two completed plans (audit remediation, core hardening) with phases, exit criteria and risk registers.
- **Why:** they scoped work that was then executed.
- **How:** prioritised by dependency, with explicit gates.
- **Where:** findings from the 2026-08 audit.
- **Validity:** complete; keeping them in `roadmaps/` implied open work.
- **Fate:** Restructure — moved to `history/roadmaps/`, completed banners.

### A21. `history/repo-tree-2026-08.md` (deleted)
- **What:** a 278-line directory listing from 2026-08.
- **Why:** house rule #8 required the tree to match reality.
- **How:** `tree` output pasted into a fenced block.
- **Where:** the filesystem as of 2026-08.
- **Validity:** **actively misleading** — it lists files that no longer exist and omits everything added since, including the reorganisation itself.
- **Fate:** **Delete.** Regenerable in seconds; retained in git history.

### A22–A24. Component READMEs (`lab/`, `tools/selfplay/`, `Accelerator/`)
- **What:** build/run instructions, data contracts, status and non-goals for each component.
- **Why:** they sit next to the code their readers are editing.
- **How:** real commands, real schemas.
- **Where:** the component's own source.
- **Validity:** all three accurate except `lab/README.md` calling the implemented Elo report a scaffold.
- **Fate:** Retain in place; `lab/README.md` corrected. Moving these into `docs/` would separate them from their code for no benefit.

### A25–A29. `graphify-out/**/GRAPH_REPORT.md`
- **What:** generated code-graph summaries (5 dated snapshots, 420–765 lines each).
- **Why:** produced by the graphify tool; referenced by the strategy roadmap.
- **How:** static analysis.
- **Where:** the tree at each generation date.
- **Validity:** derived and regenerable; the 2026-08 report describes a tree that no longer exists.
- **Fate:** Retain in place as generated artefacts. **They are not part of the documentation architecture** and must not be hand-edited. Regenerate rather than trust.

---

## 5. Numeric claim verification

Re-measured 2026-11-13 on this machine.

| Claim | Document | Re-measured | Verdict |
|---|---|---|---|
| Engine checks | `BRIDGE_ARCHITECTURE`, `BRIDGE_TESTING`, `ci.yml` | **429**, 19 executables | Stale → corrected |
| Bridge checks | `BRIDGE_TESTING`, `ci.yml` | **73**, 2 executables | Stale → corrected |
| Swift tests | `BRIDGE_ARCHITECTURE`, `BRIDGE_TESTING` | **75**, 1 skipped, 0 failures | Stale → corrected |
| Sanitizer checks | `BRIDGE_TESTING` | **502**, 0 findings | Stale → corrected |
| Accelerator checks | `BRIDGE_TESTING` | **100**, 0 failed | Stale → corrected |
| Engine LOC | `PROJECT_INVENTORY` | **3,842** | Stale → corrected |
| App LOC / files | `PROJECT_INVENTORY` | **7,424 / 56** | Stale → corrected |
| Total tracked | `PROJECT_INVENTORY` | **22,546 / 175** | Stale → corrected |
| 2/8 vs 3/16 | `LAB` | 187–213, −22.6 | Reproducible; table was already close |
| 3/16 vs 4/24 | `LAB` | **202–198, +3.5** | **Wrong** → corrected |
| 4/24 vs 5/40 | `LAB` | **205–195, +8.7** | **Wrong** → corrected |
| 2/8 vs 8/64 | `LAB` | 424–576, −53.2 [−75.0, −31.4] | Reproducible |
| 5–7 ply look-ahead | `STRATEGY_NOTES` | n/a | Owner estimate, correctly labelled unverified |
| 10.7M concurrent queries | `strategy-roadmap`, 2026-08 audit | 2.2–6.7M today | True for its date; now dated |
| "Late alpha" | `README` | 57.5%, 2 modes absent, no packaging | Understated → reworded |

---

## 6. What changed in this pass

1. **Four files moved, one deleted** — the UI mandate and two completed roadmaps into `history/`; the stale tree snapshot removed.
2. **Two of those moves also renamed the file** to say what it is: `UI_UX_OVERHAUL` → `UI_CHARTER`, `ui-fix-directive` → `2026-08-ui-rebuild-mandate`.
3. **Every numeric claim that re-measurement contradicted was corrected** — see §5 — across `LAB`, `BRIDGE_TESTING`, `BRIDGE_ARCHITECTURE`, `PROJECT_INVENTORY`, `strategy-roadmap`, `ci.yml` and `README`.
4. **Nine provenance banners added** so a historical file can no longer be read as current.
5. **Two false or unsupported claims retracted** — the monotonic ladder, and "Elo ladder is still scaffold".
6. **One coverage gap documented** — the bridge mode-mismatch path that SIGSEGVs in Release.
7. **The index rebuilt** as an authority hub with a claim→evidence table and a document register.

---

## 7. Residual risks

- **Generated artefacts still lag.** `graphify-out/` describes the pre-reorganisation tree and its reports are tracked. Regeneration is a tool run, not an edit; it was not attempted here.
- **Code comments still contradict documents in two places** (C24, C25). Fixing them is a code change with review implications, deliberately left to the engineering pass.
- **Numbers will drift again.** The only durable defence is the rule in `docs/README.md`: re-measure before quoting, and state the date.
- **Two documents remain large** (`fix-log.md` 1,095 lines, the UI mandate 1,119). They are historical and append-only; splitting them would break the receipt chain.
