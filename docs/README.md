# IsolynV2.0 — Documentation

One entry point for every project document. This is a map, not an authority of
its own: each claim lives in exactly one place, and every other document points
to it rather than restating it.

## Read in this order

| # | Question | Document |
|---:|---|---|
| 1 | What is this and how do I run it? | [`../README.md`](../README.md) |
| 2 | What is true *right now*? | [`audits/2026-11-14-audit.md`](audits/2026-11-14-audit.md) |
| 3 | How is the system built? | [`architecture/BRIDGE_ARCHITECTURE.md`](architecture/BRIDGE_ARCHITECTURE.md) |
| 4 | What is it supposed to do? | [`architecture/FEATURE_SPECS.md`](architecture/FEATURE_SPECS.md) |
| 5 | How do I know it works? | [`engineering/BRIDGE_TESTING.md`](engineering/BRIDGE_TESTING.md) |
| 6 | What should I build next? | [`roadmaps/strategy-roadmap.md`](roadmaps/strategy-roadmap.md) |
| 7 | Why was a boundary drawn there? | [`engineering/OPEN_DECISIONS.md`](engineering/OPEN_DECISIONS.md) |
| 8 | How do I onboard deeply? | [`history/legacy-handoff.md`](history/legacy-handoff.md) |

## Authority model

Where two documents disagree, the higher tier wins. **Lower tiers are never
evidence about higher ones.**

| Tier | Source | Treat as |
|---:|---|---|
| 0 | [`rules/RULEBOOK.md`](rules/RULEBOOK.md) | **The rules of the game.** The implementation is judged against it; where they differ, the code is wrong |
| 1 | Running code and its output | Ground truth about *behaviour*; reproducible |
| 2 | [`audits/2026-11-14-audit.md`](audits/2026-11-14-audit.md) | Current measured state (2026-11-14) |
| 2a | [`audits/2026-11-13-audit.md`](audits/2026-11-13-audit.md) | Prior snapshot (2026-11-13); superseded where the newer audit differs |
| 3 | `architecture/`, `engineering/`, `subsystems/`, `design/UI_CHARTER.md` | Living; must change with the code |
| 4 | `roadmaps/` | Intent, never status |
| 5 | `history/` | Frozen receipts for a date |
| 6 | `graphify-out/` | Derived, regenerable, may lag |

A tier-3 document that contradicts tier 1 is a bug in the document. A tier-5
document that contradicts tier 1 is expected and is labelled as such.

## Register

| Document | Purpose | Status | Verified |
|---|---|---|---|
| `README.md` (root) | Identity, run, status, entry links | Living | 2026-11-13 |
| `docs/README.md` | This map | Living | 2026-11-13 |
| `rules/RULEBOOK.md` | Numbered rules of the game, each with the assertion that enforces it | Normative, tier 0 | 2026-11-14 |
| `architecture/BRIDGE_ARCHITECTURE.md` | C++/Swift boundary and its invariants | Living | 2026-11-13 |
| `architecture/FEATURE_SPECS.md` | Training and Sandbox intent | Specification (unimplemented) | 2026-11-13 |
| `architecture/PROJECT_INVENTORY.md` | Identity, LOC, caller map | Living | 2026-11-13 |
| `engineering/BRIDGE_TESTING.md` | Verification matrix and coverage gaps | Living | 2026-11-13 |
| `engineering/OPEN_DECISIONS.md` | ADR-001..004 and open questions | Living decisions | 2026-11-13 |
| `engineering/RELEASE_CHECKLIST.md` | Packaging, signing, privacy gates | Living checklist | 2026-08 |
| `design/UI_CHARTER.md` | Current table, layout and visual system | Living design | 2026-11-12 |
| `design/STRATEGY_NOTES.md` | Domino domain knowledge | Reference (mostly unimplemented) | 2026-11-13 |
| `subsystems/LAB.md` | Self-play, calibration, app integration, data contracts | Living | 2026-11-14 |
| `subsystems/ACCELERATOR.md` | Metal backend, parity, throughput | Living | 2026-11-13 |
| `roadmaps/strategy-roadmap.md` | Seven-phase plan of record | Plan (partially executed) | 2026-11-13 |
| `research/PROJECT_OVERDRIVE.md` | Strength programme charter, champion, next actions | Living journal | 2026-11-14 |
| `research/STRENGTH_BASELINE.md` | **The only home for playing-strength claims**, stamped with the rules version they were measured under | Living measurements | 2026-11-14 |
| `research/BENCHMARK_BASELINE.md` | Pre-rulebook ladder and timings — **VOID**, kept for audit only | VOID measurements | 2026-11-14 |
| `research/EXPERIMENT_REGISTRY.md` | Accepted and rejected experiments, with intervals | Living record | 2026-11-14 |
| `research/METAL_INTEGRATION.md` | Accelerator audit and integration gates | Living audit | 2026-11-14 |
| `research/KAGGLE_BRIDGE.md` | Free cloud compute: limits, arithmetic, session contract, first session | Implemented locally; live run pending | 2026-11-14 |
| `research/SEARCH_PERFORMANCE.md` | Five-tier self-play throughput and shard RSS for the compact transposition table | Living measurements | 2026-11-15 |
| `audits/2026-11-14-audit.md` | **Current factual baseline** | Authoritative | 2026-11-14 |
| `audits/2026-11-13-audit.md` | Prior factual baseline; superseded by the 2026-11-14 audit | Historical snapshot | 2026-11-13 |
| `audits/2026-11-13-documentation-audit.md` | Why each document exists; contradiction register | Authoritative for doc status | 2026-11-13 |
| `audits/2026-08-24-audit.md` (+`.pdf`) | First audit; 12 findings and their fixes | Historical | 2026-08-24 |
| `history/2026-08-ui-rebuild-mandate.md` | The rebuild mandate; §2–§3 still binding | Historical (normative excerpts) | 2026-11-13 |
| `history/legacy-handoff.md` | Onboarding, house rules, ambiguities | Historical (rules still binding) | 2026-08 |
| `history/fix-log.md` | Append-only fix receipts | Historical | append-only |
| `history/roadmaps/audit-remediation-roadmap.md` | Partially executed remediation plan (Phases 0–2 of 6) | Historical | 2026-08-25 |
| `history/roadmaps/core-hardening-roadmap.md` | Completed hardening plan | Historical | 2026-08 |

Component documentation lives next to its code, where its readers already are:
[`../lab/README.md`](../lab/README.md), [`../tools/selfplay/README.md`](../tools/selfplay/README.md), [`../cloud/README.md`](../cloud/README.md), [`../Accelerator/README.md`](../Accelerator/README.md).

## Claim → evidence

Every volatile number has one home. Re-measure before quoting; state the date.

| Claim | Home | Reproduce with |
|---|---|---|
| Engine checks (524, 20 exes, 2026-11-15) | `engineering/BRIDGE_TESTING.md` | `./scripts/ci/test_engine.sh` |
| Bridge checks (141, 2 exes) | `engineering/BRIDGE_TESTING.md` | `./scripts/ci/test_bridge.sh` |
| Swift tests (125, 0 skipped) | `engineering/BRIDGE_TESTING.md` | `swift test` |
| Whole-game conformance soak (1M games, ≈172.8M assertions) | `engineering/BRIDGE_TESTING.md` | `./scripts/ci/rules_soak.sh 1000000` |
| Offline lab/cloud tests (47, 0 failures) | `engineering/BRIDGE_TESTING.md` | `PYTHONPATH=lab/src python3 -m unittest discover -s lab/tests` |
| Sanitizer (623 checks, 0 findings) | `engineering/BRIDGE_TESTING.md` | `./scripts/ci/sanitize.sh address` |
| Accelerator (94 pass / 6 fail, parity red) | `subsystems/ACCELERATOR.md` | `./Accelerator/build.sh` |
| LOC by surface | `architecture/PROJECT_INVENTORY.md` | `git ls-files <dir> \| xargs cat \| wc -l` |
| 1v1 strength ladder | `research/STRENGTH_BASELINE.md` | `PYTHONPATH=lab/src python3 -m isolyn_lab.cli evaluate --input lab/data/<file>` |
| Search throughput and per-shard RSS | `research/SEARCH_PERFORMANCE.md` | `python3 tools/bench/tiers.py` then `python3 tools/bench/compare.py` |
| Which rules a strength figure belongs to | `rules/RULES_VERSION` | `python3 scripts/rules_audit.py` |
| Completion %, defects, priorities | `audits/2026-11-14-audit.md` | the commands in its §3 |
| Design intent per mode | `architecture/FEATURE_SPECS.md` | — (no implementation yet) |
| Rules and the assertion behind each | `rules/RULEBOOK.md` | `python3 scripts/rules_audit.py` |
| Rules decisions and open questions | `engineering/OPEN_DECISIONS.md` | — |

## Conventions

- **One home per fact.** Link to it; never copy a number into a second document.
- **Every document carries a status.** Living, plan, historical, specification,
  checklist or generated. No document is silently "current".
- **History is append-only.** `fix-log.md` gains entries at the end;
  `legacy-handoff.md` and dated audits are not rewritten.
- **Audits are dated.** A new assessment is a new file: `YYYY-MM-DD-audit.md`.
- **Plans move to `history/` when complete**, with a completed banner.
- **Generated output is not documentation.** `graphify-out/` and `lab/data/` are
  regenerated, never hand-edited, and never used as evidence.
- **Every new document gets a row in the register above.**
- **Run the gate before every closeout:** `python3 scripts/docs_audit.py`
  enforces every rule on this page — link and path resolution, status headers,
  register coverage, history banners, and the absence of superseded figures.
  It exits non-zero on any violation; a closeout that skips it is not a closeout.

## Related

- Design rationale for this structure and the per-document verdicts:
  [`audits/2026-11-13-documentation-audit.md`](audits/2026-11-13-documentation-audit.md)
- Open product decisions: [`engineering/OPEN_DECISIONS.md`](engineering/OPEN_DECISIONS.md)
