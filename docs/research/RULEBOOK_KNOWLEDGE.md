# Rulebook knowledge audit

> **Status: current (2026-11-16).** Rules version: 1. Rulebook hash
> `79ca7387ac7ac5b85b93b4cee3818defaf4a1d3f406c0d6186edbc60261cfd55`
> (rules version 1). Measures *knowledge*, not strength: no Elo claim is made
> here, and none may be derived from it without a separate measurement.

`scripts/rules_audit.py` asks whether every rule is implemented with an
assertion. That is a legality question, and it passes: 21 of 22 rules are
`ENFORCED`, 1 is `BY_HAND`.

This audit asks a different question: **how many rules can change what the engine
plays?** A rule can be obeyed perfectly at every node and still never be sought.

Reproduce: `python3 scripts/rulebook_knowledge.py -v`

## Method

Each `ENFORCED` rule is classified into one of three levels:

| Level | Meaning |
|---|---|
| `VALUED` | An evaluation term rewards or punishes the position the rule describes. |
| `PATH_VISIBLE` | A file or symbol on the search/evaluation path enforces it, but no term prices it. |
| `LEGALITY_ONLY` | Implemented, but nothing on the decision path calls its mechanism. |

Decision path = `SearchEngine`, `EvaluationEngine`, `MoveGenerator`, `GameState`,
`SimulationEngine`, `BeliefState`, `ProbabilityEngine`. Where the rulebook names a
symbol (`privateLockedPair`, `enforceOneDominoRule`), the symbol is searched in
those files, because file-level membership overstates reach: `GameState.cpp` is on
the path for the simulator, yet `privateLockedPair` exists for the UI overlay.

**Caveats, stated because they bound the claim.** The `VALUED` map is
hand-maintained: it is a statement about meaning, and a regex cannot make it.
Static matching also cannot see mechanisms the search reimplements; four such
rules (R-14, R-15) are recorded in `PATH_OVERRIDES` with their evidence. This
audit measures reachability and pricing, not effect size — for effect, the
decision-flip procedure in E-105 applies.

## Result

22 rules, 21 enforced:

| Level | Count |
|---|---|
| `VALUED` | 7 |
| `PATH_VISIBLE` | 4 |
| `LEGALITY_ONLY` | 10 |

Priced: R-02 (win/close), R-03 (1v1 scoring), R-05 (2v2 totals), R-11 (opening),
R-16 (stuck must draw), R-19 (pip tally), R-20 (standard win pays the same).

Obeyed but unpriced — these constrain search and are never sought:

- **R-14** (the opener may never make the first draw)
- **R-15** (unlimited voluntary draws after the first)
- **R-17** (two locked tiles; private look at one tile)
- **R-18** (one-domino rule: both on one tile forces a draw at turn start)

## The strategic hole: the engine does not know the score

Ten rules never reach the decision path. Most are correctly outside it — dealing
counts, mode definitions, the double-six ritual, who starts the next hand. Two are
not:

- **R-06** — a set is won at 151, *which means reaching 151 loses the set*.
- **R-22** — in 1v1v1 the first player to 151 is eliminated.

Verified structurally, not inferred: `SearchEngine::Config` has no score field,
and no file on the decision path reads `raceTarget`, `currentScore` or
`kOneVsOneMatchLossThreshold`. The engine evaluates every hand as if the set were
0–0. It cannot know that winning a hand 40–0 while sitting on 145 is a loss, and
it cannot prefer the line that keeps its own total under the threshold.

This is the clearest answer to "how much of the rulebook does the engine know?":
it knows **how a hand is scored** and not **what the score means**. Every earlier
experiment in this campaign perturbed the hand-level evaluation; none could touch
this, because the information is not present at the decision at all.

## Scaling it up, in order

1. Pass the set score and race target into `SearchEngine::Config` (engine only,
   defaulting to a 0–0 game so shipped behaviour is unchanged).
2. Price the threshold — the existing two-tier root decision (E-106) is the cheap
   seam: among near-equal moves, prefer the one whose expected total stays below
   the loss threshold when the current score is close to it.
3. Measure with the harness on near-threshold scores, where the rule actually
   binds. A 0–0 self-play match cannot show this effect and would wrongly return
   zero.
