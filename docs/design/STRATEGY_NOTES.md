# Strategic Design Notes — Closing vs. Domino Decisions

> **Status: domain knowledge, mostly unimplemented (verified 2026-11-13).** Of
> the behaviours described here, only a round-level closing-opportunity component
> exists in `EvaluationEngine`. The 2v2 declarations, partner-play mode,
> match-threshold playstyle shift and locked-double tactic are design intent.
> Treat this file as requirements for future evaluation work, not as a claim
> about current playing strength. The measured ladder is in
> `docs/subsystems/LAB.md`.

> Captured from a design discussion. This is domain knowledge for
> EvaluationEngine, ProbabilityEngine, and DifficultyModel to encode when
> those are built -- it does not affect MoveValidator or MoveGenerator,
> which only ever decide legality, never which legal move is strategically
> better.

## Why "may not refuse to win/close" does not narrow legality

Rules Spec's Mandatory Play clause ("a player may not intentionally refuse
to win... to close a game") only restates the general rule that a player
must make *some* legal move if one exists. It does not make a
winning/closing move, when available, the *only* legal move. Players
legitimately -- and often correctly -- choose a different legal move
instead; see below. MoveValidator therefore does no win/close-priority
filtering at all: a move is legal exactly when it fits an open end (or
opens an empty chain).

## The real objective is match-level, not round-level

A round's outcome (Domino victory, or being the lower hand in a Close) is
a scoring event that adds points toward a running match total. The actual
goal is pushing the opponent(s) to or past the match-ending threshold --
not winning any single round in isolation. A player can take on points in
a given round and still be making the objectively correct move for the
match.

## Closing is sometimes chosen over a visible Domino path

Whoever closes a round starts the next one (Rules Spec Sec. 4/9/11) --
valuable enough that a player may deliberately force a Close even with a
visible path to a normal Domino win, and even when doing so risks being
the higher (scored) hand in that Close.

Why this can be correct: continuing toward a Domino win takes more turns,
during which the opponent also plays -- typically reducing their own
remaining hand value before the round eventually ends naturally. Forcing
a Close *now* freezes the opponent's hand value at its current, possibly
higher, level, before they get the chance to bring it down. The combined
value of (a) guaranteeing the next-round start, and (b) potentially
locking in a worse frozen value for the opponent, can outweigh (c) the
risk of being the closer stuck with the higher hand this specific round.

## The symmetric case: declining an available Close

The same logic runs in reverse: a player holding a heavy (high-value) hand
may deliberately not take an available closing move, and keep playing
toward reducing their own hand instead -- because closing right now with
a heavy hand risks a large point penalty against themselves.

## Both decisions are estimation-driven, not rule-driven

Whether to close, or to decline an available close, is answered by
estimating the opponent's likely remaining hand value from observable
evidence -- which specific pip values have already appeared on the board
or elsewhere, narrowing what the opponent could still be holding. This is
exactly the reasoning ProbabilityEngine/HiddenInformationModel/BeliefState
need to support, and exactly what ClosingOpportunityHeuristic and
ExpectedValueHeuristic need to weigh against each other -- neither one
encodes a fixed always/never-close rule; the decision is a genuine
expected-value comparison every time.

---

# 2v2 Strategy — Partner Communication and Coordination

> Captured from a domain-expert strategy drop, distilled and reorganized
> from the user's own words. Same status as the rest of this file: domain
> knowledge for EvaluationEngine/DifficultyModel to encode later, not
> something reflected in the current build.

## The two permitted pre-round declarations

At tournament level, 2v2 coordination is close to mandatory -- teams that
don't coordinate essentially don't win. Convention allows exactly two
declarations at the start of a round, both intentionally shallow (no
elaboration permitted for either):

- **"Heavy" or "light"** -- either partner, on either team, may say this
  about their own hand. Nothing more specific.
- **"Missing a set"**, or not (see definition below) -- usable only by
  the team that has the option of choosing who opens the round (i.e. the
  team that closed or won the previous round). The team without that
  option may not make this declaration. Lying about either declaration
  disqualifies a team, so whatever is said is always true.

Whichever gets said effectively fixes the receiving partner's game plan
for the round -- deviating from it is described as close to an automatic
loss.

## Definition: "missing a set"

A player is NOT missing a given pip value's set if they hold 5 or more
tiles containing that value, AND they hold that value's double (the
double counts as one of the 5+). Example: a hand of 5-6, 6-6, 1-6, 3-6,
2-6, 0-4, 1-1 holds five 6-containing tiles including 6-6 itself -- not
missing. Holding 4 or fewer of a value, or lacking that value's double
even with 5+ non-doubles, means the player IS missing that set.

Practical meaning: holding 5+ of a value plus its double leaves very few
of that value unaccounted for elsewhere, so opening with that double
carries much less risk of being intercepted by an opponent who also
holds several. Fewer than that (or no double) means real uncertainty
about who else holds that value -- worth flagging rather than opening
blind.

This threshold is concrete and well-defined enough to be a real candidate
for a future 2v2-specific evaluation component (a "set safety" heuristic
or similar), not just a table-talk convention.

## "Playing for your partner"

A distinct mode, not the default: for the rest of the hand, every play is
chosen purely for the partner's benefit, never your own hand's interests.
Not recommended most of the time, since it disrupts your own flow --
reserved specifically for when your own hand is bad or you're locked out,
AND your partner's hand is strong. Explicitly announced ("I'm playing
this hand for you") when adopted.

Mechanically, two things:
- Avoid playing anything that changes the value your partner is relying
  on at whichever end matters to them -- **except a double**, which
  attaches without changing the exposed value at all. (This is already a
  verified property of this engine's Chain: playing a double against an
  end it matches leaves that end showing the same value afterward -- the
  "partner plays 3-4, you follow with 4-4" example works specifically
  because of this.)
- Actively play tiles that clear or reopen whichever end the partner
  needs, even at the cost of not playing your own objectively strongest
  tile.

Worked example: the opponents leave both ends effectively showing 6 (via
a 5-6 and a 3-6 placement). The player holds 6-6 -- normally the clearly
strongest play -- but their partner has only 2 tiles left, so they play
6-1 instead, specifically to free the partner's route rather than take
the strong play for themselves.

Critical caveat, in the player's own words: this only makes sense if you
can actually infer what your partner holds. If you know (or can deduce)
your partner doesn't need what you'd be freeing up -- e.g. you're holding
the last remaining tile of that value yourself -- the logical play
reverts to your own strongest option (the double, in the example above),
since sacrificing it would help no one. This is squarely
ProbabilityEngine/HiddenInformationModel territory: "playing for your
partner" is only a good decision when belief-state confidence about the
partner's hand actually supports it, not a rule to apply unconditionally.

---

# 1v1 Strategy — Look-Ahead Depth and Tile-Counting Reasoning

> Captured from a worked example walked through live, with explicit
> caveats that must travel with this content: not claimed to be
> tournament-level or "correct" play, described by the user as their own
> personal reasoning style for a hypothetical game, and left unfinished
> partway through. The value here is in the FORM of the reasoning -- what
> a strong player tracks, and how many moves ahead they plan -- not in
> treating any specific move choice below as validated or optimal.

## Claimed look-ahead depth at high-level play

The user's own estimate: strong 1v1 players are typically inferring or
planning 5-7 moves ahead at any given point, and falling meaningfully
short of that depth leads to losing quickly. Not independently verified
-- worth keeping as an approximate calibration target once
SearchEngine/DifficultyModel need a sense of what search depth
"competitive" versus "strong" actually requires, not as a hard number.

## The pattern, distilled from the worked trace

- **Score and prior-round context shape the very first move.** Before any
  tile is played, the match score and *why* this player specifically is
  opening (having closed the previous round) both factored into opening
  strategy -- it isn't decided from the hand in isolation.
- **Proactive drawing based on anticipated future need, not just current
  legality.** A decision to draw next turn, regardless of what the
  opponent plays, was made in advance -- specifically because the hand
  holds almost nothing in a value (6s) judged "inevitable" soon. Drawing
  here is forward-looking, not merely reactive to being unable to play.
- **Exact remaining-count tracking for a specific pip value.** Reasoning
  is explicitly framed as how many of a given value remain unaccounted
  for. In a Double-Six set, any pip value appears on exactly 7 tiles
  total; subtracting what's visible (own hand, the chain) plus what's
  provably inert (the 2 permanently-locked boneyard tiles, once
  revealed) gives a hard upper bound on what an opponent could still
  hold of that value. This is exactly the observable-evidence tracking
  ProbabilityEngine/HiddenInformationModel need to formalize, now with a
  concrete, countable worked example to formalize against.
- **A double is not unconditionally good to hold or play.** Playing a
  double can invite the opponent to further entrench an already-scarce,
  contested value rather than neutralizing it. Several possible opponent
  replies to the double were weighed against each other specifically
  because certain replies would set up a targeted follow-up on this
  player's own next turn -- multi-ply conditional planning ("if they
  play A, I do X; if B, I do Y"), not a single-move evaluation.
- **Reading a single opponent play as a meaningful signal.** The
  opponent playing what was judged the strongest remaining tile
  unusually early itself updated the read on the position -- how much of
  that value remained, what the opponent might be short on. A direct
  example of the Concept Spec's own "Behavioral Analysis" -- observing
  decisions, not just tile identities.

## Worked trace (illustrative, explicitly unfinished)

Opening hand (no double): 1-2, 2-4, 4-0, 1-5, 5-2, 3-2, 3-6. Opens with
4-2, planning to draw next turn regardless of the opponent's reply, since
the hand is 6-light and 6s are judged inevitable. Two conditional
branches were planned before the opponent's reply was even known: if the
opponent plays a 6, draw aggressively and press the advantage while few
2s remain elsewhere; if they play a 4, draw a smaller amount and play
passively, since the 2-6 (judged the strongest tile in this specific
position) is still unaccounted for. Opponent plays 6-4. Draws three
tiles: 5-6, 1-1, 6-6. Weighs whether to play the double-6 immediately
against which of the opponent's possible 6-replies (6-1, 6-2, 6-5, 6-0)
would be favorable versus unfavorable, specifically hoping for a reply
that sets up a follow-up on the opponent's 6-2. Plays 6-6; board becomes
6-6 / 6-4 / 4-2, with (by the player's own count) 5 sixes remaining
outside their own hand, or 4 once the 2 permanently-locked boneyard
tiles are set aside as unknown-but-inert. Opponent plays 2-6 -- read as
notably strong and unusually early. Three sixes now unaccounted for;
opponent holds 5 tiles. Considering whether to draw, hoping specifically
for another 2 or a 4 rather than a 6. Trace ends here, unfinished.

---

# 1v1 Strategy — Skill Gap, Boneyard Draining, Score-Driven Playstyle, and Elite Tactics

> Captured from the user's own observed games (three players, one friend
> group, with a clearly stated ~40-45% skill gap on one side). Same
> status as the rest of this file: real domain knowledge worth encoding,
> not yet reflected in the current build.

## Hand quality matters less as the skill gap widens

At a large enough skill gap, hand quality stops predicting the outcome
at all -- the stronger player's estimation ability alone can force
outcomes regardless of what they were dealt. At EQUAL skill, hand
quality dominates instead: the better hand wins roughly 90% of the time,
and the disadvantaged player's main realistic chance is an exceptionally
strong hand combined with favorable circumstances letting them force a
close or a long domino run. At lower skill generally, what you're dealt
matters more than how you play it; that balance inverts as skill rises.

A concrete signal for DifficultyModel: how strongly a given strength
level's win rate still correlates with hand quality is itself a
plausible measurable proxy for how well-calibrated that strength setting
is -- a weak setting should still show meaningful correlation with hand
luck; a maximally strong one should show much less.

## Draining the entire boneyard: a real, high-variance, high-skill tactic

Conventional wisdom (echoed at lower skill) says drawing heavily from the
boneyard is dangerous -- too many tiles to actually place, likely to
lose badly. At high skill this inverts: drawing the ENTIRE remaining
boneyard converts hidden information into complete information. Once the
boneyard is empty, every tile not in your own hand or on the board is
deterministically in the opponent's hand -- full information, not just a
distribution. A sufficiently skilled player can then force closes or
wins by exploiting that certainty directly. The identical move attempted
without the calculation to exploit it backfires badly -- one observed
case lost 52 points in a single hand.

A genuine, identifiable tactic worth a name in the engine eventually --
something like a full-drain line -- and squarely ProbabilityEngine
territory: its entire value comes from collapsing uncertainty to zero,
which only that class can formally recognize as having happened.

## Score proximity to the match threshold changes the entire playstyle

Far from the losing threshold (e.g. 20-13 out of 101), strong players
play "normally" -- taking whatever the position's best win or close
happens to be. Close to it (e.g. 70-80), the calculus inverts entirely:
the objective becomes closing as fast and as often as possible, even for
small amounts, rather than chasing one large domino-sequence win.
Concrete framing given: needing 31 more points to lose, a player would
rather force several quick closes worth 6, 6, 5, 2, 6 than wait for one
large 20-30 point win, because forcing the opponent to the threshold
first is what matters, not points per round.

The opponent, aware of this, counters in kind -- forcing extra draws to
increase the trailing player's uncertainty about their own hand (making
a risky close more dangerous to attempt), or even deliberately conceding
a modest win while ensuring THEY are the one who closes it, specifically
to regain next-round initiative. This last point directly echoes the
earlier closing-vs-Domino notes: starting the next round can be worth
more than the round's own points, to both sides at once.

A concrete, currently-missing dimension for ClosingOpportunityHeuristic:
as built, it only weighs the round-level score comparison and a flat
next-round-start bonus -- no awareness yet of how close either side's
running match score is to the losing threshold, which this section
suggests should shift that weighting substantially, not just modestly,
as the threshold approaches.

## Elite tactic: locking down a single inferred double

Above a certain skill threshold, players can win primarily by
identifying -- via inference, not certainty -- that an opponent holds a
specific double, then dedicating the rest of their play, including
aggressive boneyard draining, purely to ensuring that double can never be
played for the rest of the round. The player doing this typically closes
with a light hand of their own, but the opponent's locked, unplayed
double (the single highest-value tile category, up to 12 points for
6-6) weighs heavily in the closing comparison, making the trade worth
it.

A real example given: a highly-ranked player won an entire match to 108
points purely through closes -- never once winning by Domino -- scoring
repeatedly in the 6-12 point range per round. The user's own assessment:
this requires not just the calculation to correctly infer what's locked,
but the discipline to consistently forgo easier, larger-looking wins in
favor of the harder, longer-horizon play, hand after hand.

Explicit, important caveat, in the user's own words: this is
probabilistic, not certain. The two permanently-locked boneyard tiles
are a real, irreducible source of error, and inference about an
opponent's hand can simply be wrong -- described in terms of concrete
confidence levels (50/50, 60/40, 70/30), not binary certainty. That
framing -- strong players already reasoning in explicit confidence
percentages for their own reads -- is a direct, human validation that
BeliefState should expose real confidence levels, not just a best guess.



