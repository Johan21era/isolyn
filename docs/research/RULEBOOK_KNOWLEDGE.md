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

## The exam: scored, per tier

The audit above measures reachability. This section measures **answers**.

`tools/rulebook_test` poses positions whose correct answer is computed by
simulation, never authored: the legal placements are enumerated, and each one is
applied to see what it actually does. A question is only kept when at least one
legal move is wrong, and "sharp" questions allow exactly one right answer out of
three or more, so guessing is punished rather than rewarded.

Scoring is violent by design: correct `+1`, wrong `0`, **illegal `-5`**. The
published score is `100 * max(0, correct - 5*illegal) / questions`.

Run: `./tools/rulebook_test/build.sh && ./tools/rulebook_test/build/rulebook_test --per-section 250`

| Tier | Score | win-now | win + draw offered | defence | sharp defence |
|---|---|---|---|---|---|
| s100 d2x8 | **77** | 100% | 100% | 54% | 56% |
| s400 d2x8 | **77** | 100% | 100% | 54% | 56% |
| s900 d3x16 | **80** | 100% | 100% | 57% | 64% |
| s1600 d4x24 | **80** | 100% | 100% | 52% | 70% |
| s2300 d5x40 | **81** | 100% | 100% | 56% | 68% |
| s3000 d8x64 | **81** | 100% | 100% | 55% | 70% |
| s5000 d24x80 | **80** | 100% | 100% | 54% | 68% |

1,000 questions per tier for s100–s3000; 200 for s5000 (depth 24 costs ~0.85 s per
question). Mythical (s10000, depth 48) was not run: the sweep exceeded the host's
command limit. No illegal move was produced by any tier.

### What the exam shows

**Winning is completely learned.** Every tier, including the weakest, takes a
winning placement 100% of the time — and does so even when a voluntary draw is on
offer, so the engine never prefers a draw to a win (R-02 beats R-15 at every
tier). This is the one capability the score model already prices correctly, and
the exam confirms it end to end.

**Defence against an immediate loss is not.** Given a position where the opponent
can empty their hand on their next turn, the engine fails to prevent it **44–48%
of the time**, and this is flat from depth 2 to depth 24. It is the single largest
source of lost points at every tier: roughly a quarter of the whole exam.

**Depth buys recognition, not prevention.** When the right answer is unique among
three or more options ("sharp defence"), the score climbs with depth —
56% → 64% → 70% — and then plateaus. So search *does* find the saving move when
the position is narrow. It fails on the wider positions, where several moves look
acceptable and one of them concedes an immediate loss. That is consistent with
E-105: the evaluator does not price the opponent's threat, so nothing separates
the losing move from the safe ones until the search is deep enough to see the loss
itself.

**This is the first measurement in the campaign that separates the tiers.** Every
strength experiment returned approximately zero; the exam orders them 77 / 77 /
80 / 80 / 81 / 81 / 80. The differences are small, but the ordering exists, and it
is a knowledge ordering rather than a win-rate one.

### Limitations

- Positions are artificial: 1–3 tiles per hand with the rest of the set in the
  boneyard. They are legal, complete (all 28 tiles accounted for) states, but not
  deals the app produces.
- Ground truth is "does not allow an immediate loss", not "is optimal". A move can
  pass the defence question and still be poor.
- The exam measures a tier's choices, not its win rate. A high exam score is not
  a strength claim and must not be quoted as one.

## The control that changed the conclusion

**Retraction.** The section above says "the evaluator does not price the opponent's
threat". That claim is now **falsified** and must not be cited. It was inferred from
a defence score near 55% without controlling for whether the question was
answerable at all.

Every defence question so far hid the opponent's tiles. The engine's belief assigns
them by sampling, so a move that loses only to the opponent's *actual* tile looks
safe in most sampled worlds. A low score there is consistent with two very
different stories: a blind engine, or an engine being asked to see through the
backs of the tiles. The first exam could not tell them apart.

`defence, all tiles known` separates them. The chain is grown until a handful of
tiles remain, the opponent is left holding exactly one, and the boneyard is empty —
so every tile is accounted for and the opponent's immediate win is **deducible**.
Missing it there is a mistake; missing it in the other section may be unavoidable.

| Tier | defence (hidden tiles) | defence (all tiles known) |
|---|---|---|
| s100 d2x8 | 61% | **99%** |
| s400 d2x8 | 56% | **99%** |
| s900 d3x16 | 67% | **99%** |
| s1600 d4x24 | 62% | **99%** |
| s2300 d5x40 | 66% | **99%** |
| s3000 d8x64 | 59% | **99%** |

100 questions per cell, 0 illegal moves.

### What this means

**The engine is not blind to the opponent's threat.** Given complete information it
blocks the immediate win 99% of the time — at depth 2, in the weakest tier, as
reliably as at depth 8. The capability is present and it does not need search depth.
Whatever the ~40% miss rate in the hidden-information section is, it is not a
missing evaluation term.

**Therefore no opponent-threat term was added.** It would have been a change made
to fix a bug that this control shows was not there, and it would have made the
engine defensive against threats that only exist in its own sampling noise. The
request was "teach the engine to value blocking"; the measurement says it already
does, and that the apparent failure was my exam demanding clairvoyance.

**What the remaining hidden-information gap could still be.** Two things are not
yet separated: (a) the engine is playing well under uncertainty, or (b) it is
leaving value on the table because its belief sampling is too coarse to notice a
1-in-N threat. Distinguishing them requires a Bayes-optimal baseline — the move
that minimises the probability of the opponent's win over all hands consistent
with what is known — which is not yet implemented. Until that exists, the
hidden-information defence score is **not** evidence of a defect and must not be
quoted as one.

### Re-scored totals, with the control included

| Tier | Score |
|---|---|
| s100 d2x8 | 85 |
| s400 d2x8 | 81 |
| s900 d3x16 | 86 |
| s1600 d4x24 | 86 |
| s2300 d5x40 | 87 |
| s3000 d8x64 | 85 |

Still 100% on win-now and win-with-a-draw-on-offer at every tier, and still zero
illegal moves across all 3,000 answers.
