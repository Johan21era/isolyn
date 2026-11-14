# IsolynV2.0 — Open Decisions & Architecture Records

> **Status: living decision log (tier 3).** Created 2026-11-11. The audit flagged this ledger as missing. Each ADR records
> the decision, why it was made, and what would cause it to be revisited.
>
> Status vocabulary: **Accepted** = direction is settled. **Scaffolded** = files
> exist, but no behavior is implemented yet. **Open** = not decided.

## ADR-001 — Product languages: C++20 + Swift; Python offline only

- **Status:** Accepted
- **Date:** 2026-11-11

**Context.** IsolynV2.0 is a ~13k-line macOS game. Its engine is C++20; its UI is
SwiftUI; the bridge is a POD-only C++ boundary that already carries a significant
share of the project's complexity. The open product work is 2v2 correctness, AI,
Sandbox, Training, and packaging — not language capability.

**Decision.** The shipped product stays **C++20 + Swift**. Python is allowed only
in `lab/` and `tools/` as a tooling language. No Rust, Go, TypeScript, or Python
runtime is added to the app. No game rule, scoring rule, or legality decision may
live outside the C++ engine.

**Why.** A new product language would add another ABI, build system, CI job,
debugger, packaging path, and source of truth. The current bottlenecks are
product completeness and correctness, not expressiveness. IsolynV2.0's advantage is
its narrow waist, not its language count.

**Consequences.** Offline work may use Python freely; integration happens through
files, CSVs, weights, or a process boundary — never by linking Python into the
app. A web client, if ever required, should compile the existing C++ engine to
WASM rather than reimplement rules in TypeScript.

**Revisit when.** A measured capability gap appears that C++/Swift cannot close
economically, or a real distribution requirement (web, Windows/Linux) changes
the product boundary.

---

## ADR-002 — Offline lab and trainer

- **Status:** Accepted; self-play + calibration report implemented; trainer scaffolded
- **Date:** 2026-11-11

**Context.** The AI phase needs calibrated strength, and a future learned
evaluation would need a training loop. Neither belongs in the shipped app.

**Decision.** Build an offline lab with two parts:

1. `tools/selfplay/` — a C++ harness that links the real engine, plays games,
   and emits reproducible CSV/JSONL.
2. `lab/` — a Python package for datasets, calibration analysis, and optional
   model training.

Python may produce weights or reports. C++ performs inference and remains the
only authority on rules. The lab never ships inside the `.app`.

**Why.** This is the Stockfish NNUE pattern: Python/PyTorch can train; the engine
is C++ and owns play. It gives the lab the best research ecosystem without
putting a second runtime on the hot path.

**Consequences.** A second toolchain exists, but only for developers. Datasets
must record engine commit, seeds, configuration, and hardware. The lab's first
real milestone is self-play/calibration, not a neural network.

**Revisit when.** The self-play baseline shows that hand-tuned evaluation cannot
reach the target strength ladder, or training data outgrows local disk/CPU.

---

## ADR-003 — Metal accelerator is a first-class backend

- **Status:** Accepted; standalone batch evaluator implemented, search integration pending
- **Date:** 2026-11-11

**Context.** The owner wants a serious strength increase, not a small Metal
experiment. IsolynV2.0's search evaluates many independent determinized worlds,
which is a natural batch workload for Apple Silicon's unified-memory GPU.

**Decision.** Build a **first-class Metal compute backend** for batched
evaluation and parallel search. The CPU engine is the reference and fallback.
The accelerator returns evaluation values to C++; it never generates moves,
validates legality, or scores rounds.

The first implementation targets batched leaf evaluation and root
determinizations. A GPU-resident search frontier is a later phase, only after
parity and throughput are proven.

**Why.** A naive port of the recursive, pointer-shaped search tree would be
slower than the CPU. Batching the independent work is the path to a real
order-of-magnitude gain.

**Consequences.** The project needs a Metal toolchain, a separate
Xcode/Objective-C++ target, CPU-parity tests, deterministic tie-breaking, a
benchmark harness, and a hardware capability probe. The SPM build is not changed
until that target exists.

**Revisit when.** Parity cannot be achieved, thermal/memory limits erase the
gain, or the strength ladder shows no improvement over the CPU baseline.

---

## ADR-004 — One source of game truth

- **Status:** Accepted (existing project rule)
- **Date:** 2026-11-11

**Decision.** The C++ engine owns rules, legality, scoring, and match state. The
Swift app displays; the bridge transports; the accelerator evaluates. No layer
may reimplement a rule “for convenience.”

**Consequences.** Every new backend or tool must consume engine output or return
values to the engine. If a proposed feature needs game logic in another
language, the design is wrong.

---

## ADR-005 — Every production search has a wall-clock cap

- **Status:** Accepted
- **Date:** 2026-11-14

**Decision.** `SearchEngine::Config::timeLimitMs` is the only latency control.
Production callers use `bridge_analysis_run_with_budget`; the old unbounded
`bridge_analysis_run` remains for deterministic tests. The app budgets 1.5 s for
coach analysis and 3 s for the AI.

**Consequences.** No user action can start an unbounded search. A truncated run
must be presented as incomplete (`completed == false`), never as a fully
searched recommendation. Any strength measurement must state the budget it ran
under, because a tighter budget is a different engine.

---

## ADR-006 — The locked pair is never publicly revealed

- **Status:** Accepted (RULEBOOK R-17)
- **Date:** 2026-11-14

**Decision.** The snapshot DTO carries no locked-tile identities
(`boneyardLockedCount == 0`), and the belief model keeps the pair inside the
boneyard's uncertainty rather than adding it to `otherKnown`.

**Consequences.** Neither the player nor the search learns which tiles are
locked. The R-17 private look is still unimplemented; when it is built it must be
seat-scoped and must not become a public snapshot field. The previous
"reveal when the draw pile empties" behavior is forbidden.

---

## Open questions

- **Learned vs hand-tuned first:** should the lab's first model learn evaluation,
  move policy, or only calibration? (Recommended: evaluation only, after the
  self-play baseline.)
- **GPU scope:** batched leaf evaluation only, or also root determinizations and
  a GPU-resident frontier? (Recommended: phased, with parity gates.)
- **Feature encoding:** which `EvaluationBreakdown`/belief features cross the
  GPU boundary, and at what precision?
- **Hardware floor:** which Apple GPUs are supported, and what is the fallback
  policy on older Macs?
- **Data retention:** how much self-play data is kept, and what is reproducible
  from seeds alone?
