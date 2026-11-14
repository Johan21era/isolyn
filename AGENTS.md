# AGENTS.md — standing instructions for AI agents in this repository

This file is the operating contract for any AI assistant working on IsolynV2.0.
Read it before acting. It is authoritative for *process*; the code and tests are
authoritative for *behaviour*.

---

## 0. Authority, in strict order

1. **The owner's live hands-on testing.** If the owner reports what they saw, that
   is the specification. It outranks every measurement, benchmark and journal
   entry in this repository.
2. **Reproduced test output** from the commands in §2, run on the current tree.
3. **Recorded measurements** in `docs/research/` (self-play, benchmarks), which are
   supporting evidence only.

A self-play result is a *proxy*. It cannot know what a human notices, what a real
opponent punishes, or how the app feels. When the owner's experience contradicts a
number, the number is what is wrong — say so plainly and investigate.

Never claim a strength improvement without a measured effect and its confidence
interval. Never claim a test passed that was not run. Never call CI green when the
jobs did not execute (see §7).

**The rulebook outranks the code.** `docs/rules/RULEBOOK.md` is tier 0: it defines
the game, and the implementation is judged against it. Where code and the rulebook
disagree, the code is wrong — say so, and fix the code, not the document. A rule
may not be changed by editing code: change the rulebook, then its assertion, then
the implementation. `python3 scripts/rules_audit.py` enforces that every rule
names real code and at least one real assertion, and that declared holes are
visible.

---

## 1. The "Closeout Initiative" trigger

**When the owner says the words "closeout initiative", execute §3 through §8 in
order, in one uninterrupted pass, without asking for confirmation.** That phrase is
a standing instruction, not a topic for discussion.

If any step fails, enter the critical-analysis state in §9 and fix it before
continuing. Do not skip a failing step and continue as if it passed.

---

## 2. The verification commands (run all of them, capture literal output)

```bash
./tools/selfplay/build.sh          # engine + harness compile
./scripts/ci/test_engine.sh        # expect: 19 executables, 480 checks, 0 failed
./scripts/ci/test_bridge.sh        # expect: 2 executables, 116 checks, 0 failed
swift build                        # expect: Build complete!
swift test                         # expect: 112 tests, 0 skipped, 0 failures
./scripts/ci/local.sh             # all of the below, in ci.yml's order, one verdict line each
python3 scripts/rules_audit.py     # expect: RESULT: PASS (N declared holes)
python3 scripts/docs_audit.py      # expect: RESULT: PASS
```

The expected counts above are the state at commit `1352063`, updated at OPS-34
(2026-11-14) for the rulebook rewrite and the Lab suites: engine 432 → 451,
bridge 73 → 74, Swift 75 (1 skipped) → 112 (0 skipped); later that day Phase 1
took bridge 74 → 87, and Phase 2 took engine 451 → 471 and bridge 87 → 110;
R-17's private look then took engine 471 → 480 and bridge 110 → 116; Swift
stayed at 112.
If your run differs, the difference is a finding: explain it, do not quietly
update the numbers.

Record the **exact** lines (e.g. `TOTAL CHECKS PASSED: 432`), not a summary like
"tests pass". Every claim in the closeout receipt must be backed by a literal line
you can paste.

---

## 3. Step 1 — deep analysis of this session's work

Determine the boundary:

```bash
# Preferred boundary: the last closeout receipt in the append-only log.
grep -n "Closeout Initiative" docs/history/fix-log.md | tail -3

# All commits since that receipt, with per-commit file/LOC stats:
git log <last-closeout-sha>..HEAD --pretty=format:'%h %ad %s' --date=format:'%Y-%m-%d %H:%M' --shortstat

# Files changed, insertions/deletions, per commit:
git log <last-closeout-sha>..HEAD --numstat
```

**Midnight rule.** If the session crossed local midnight, the boundary is the start
of the *previous* calendar day, so pre-midnight work is included:

```bash
git log --since="$(date -v-2d '+%Y-%m-%d 00:00')" --pretty=format:'%h %ad %s' --date=format:'%Y-%m-%d %H:%M' --shortstat
```

For every commit, state in plain language: what changed, why, and what evidence
supports it. Separate **code changes** from **documentation changes** — a docs
commit changes no behaviour and must not be described as a strength change.

Also confirm what was *not* done, and why. A closeout that hides an abandoned
thread is not a closeout.

---

## 4. Step 2 — cleanup, allowlist only

**Never run `git clean -xfd`.** It deletes `.freebuff/`, `lab/data/*` (raw
experiment evidence) and the dated graph backups. That is data loss, not cleanup.

Delete only these, and only after confirming each is ignored (`git check-ignore -q
<path>`) and untracked (`git ls-files --error-unmatch <path>` must fail):

```bash
# Build output and compiler byproducts
rm -rf build/ .build/ Accelerator/build/ tools/selfplay/build/
# Interpreter and editor noise
find . -name '__pycache__' -type d -prune -exec rm -rf {} + 2>/dev/null
find . -name '*.pyc' -delete 2>/dev/null
find . -name '.DS_Store' -delete 2>/dev/null
find . -name '*.o' -o -name '*.dSYM' | head    # inspect; delete only if ignored
# Regenerable graph cache (never graph.json / reports / graph-3d-full.html)
rm -rf graphify-out/cache/
```

**Never touch, under any circumstance:**
`Sources/`, `Tests/`, `docs/`, `scripts/`, `tools/`, `Accelerator/src/`,
`Accelerator/shaders/`, `Package.swift`, `Package.resolved`, `.git/`, `.github/`,
`.freebuff/`, `lab/data/` (evidence CSVs), `graphify-out/graph.json`,
`graphify-out/GRAPH_REPORT.md`, `graphify-out/graph.html`,
`graphify-out/graph-3d-full.html`, `graphify-out/20*/` (dated backups), any `.env`
file, any lockfile.

Procedure: print the candidate list first, verify each entry against the rules
above, then delete. Report bytes reclaimed with `du -sh` before/after. If a path is
tracked, stop — tracked files are never junk.

---

## 5. Step 3 — documentation updates, evidence-backed

Update every document whose claims the session changed. At minimum check:
`docs/research/PROJECT_OVERDRIVE.md`, `docs/research/EXPERIMENT_REGISTRY.md`,
`docs/subsystems/LAB.md`, `docs/README.md`, `docs/architecture/*`.

Rules:
- **Append to `docs/history/fix-log.md`; never rewrite an existing entry.** It is
  an append-only receipt log. New entry = next `OPS-NN`.
- Numeric claims require literal evidence: test output lines for check counts,
  `cloc` for lines of code, `git diff --stat` for change volume, `du -b` / `wc -c`
  for byte-level claims.

```bash
cloc Sources Tests tools Accelerator scripts --quiet          # LOC by language
git diff --stat <boundary>..HEAD                              # net change volume
wc -c <file>                                                  # byte-level claims
du -sh <dir>                                                  # size claims
```

- If a previous claim is now false, **retract it explicitly** and say why. Silent
  edits make the log useless.
- Dated audit documents are snapshots: do not update their numbers, they are
  receipts for the day they were written.
- Run `python3 scripts/docs_audit.py` after editing and fix anything it reports.

---

## 6. Step 4 — refresh both graphs

The 2D and 3D views are different artifacts; refresh **both**:

```bash
# 2D community export + report + graph.json (rebuilds graph.html)
graphify update . --force

# 3D standalone page (embedded data, offline, no CDN)
python3 scripts/build-graph-3d.py            # writes graphify-out/graph-3d-full.html
python3 scripts/build-graph-3d.py --check    # verify it is internally consistent
```

Note the two artifacts are different files, and confusing them has already caused
a false claim once (see OPS-12a): `graph.html` is the **2D** community export from
`graphify update`; `graph-3d-full.html` is the **3D** page from the script.

Verify: report node/edge/community counts from `graphify update`, confirm the 3D
build prints `ok` under `--check`, and confirm its node/link counts match
`graph.json`. The 3D page is **gitignored by design** (`.gitignore`), so it will not
appear in a commit — verify it with `--check` and quote that output instead. If
`graphify` is unavailable, report that as a blocker — do not fake it.

---

## 7. Step 5 — commit, push, CI

```bash
python3 scripts/docs_audit.py          # gate before commit; must PASS
git add -A
git commit   # message states why, not just what; footer as configured
git push origin main
```

Then watch the run to completion:

```bash
gh run list --limit 1
gh run view <id> --json status,conclusion,jobs
```

**Distinguishing a code failure from infrastructure failure is mandatory:**
- If jobs fail in seconds with **0 steps executed** and/or **no runner assigned**
  (`runner_id: 0`, `runner_name` empty, `started_at` == `completed_at`), that is
  infrastructure. Say so explicitly, quote the evidence, and **do not report CI as
  green**. Fetch the annotation, which states the cause directly:
  `gh api repos/:owner/:repo/check-runs/<job_id>/annotations`.
- **Known cause in this repository (2026-11-14, OPS-12b):** the annotation reads
  *"The job was not started because recent account payments have failed or your
  spending limit needs to be increased."* The repository is private, so hosted
  minutes are billed. This cannot be fixed from the tree — tell the owner to
  resolve Billing & plans. Do not disable or weaken the workflow to manufacture a
  green check; a billing-red run is honest evidence.
- If steps ran and failed, that is a code failure: read the failing log, fix the
  cause, re-run, and only then report.

Report exactly what happened. "Local suites green, CI did not execute" is an
acceptable and honest outcome. "CI green" when no job ran is a lie.

---

## 8. Step 6 — the receipt

Append one entry to `docs/history/fix-log.md`:

```
## OPS-NN — Closeout Initiative (<YYYY-MM-DD>: <one-line scope>)

**Scope:** <what this closeout covered>

- **Commits analysed:** <list with hashes and one-line plain-language purpose>
- **Verification sweep:** <literal command output lines, including counts>
- **Cleanup:** <paths removed, bytes reclaimed, what was deliberately kept>
- **Documentation updated:** <files and the claims changed/retracted>
- **Graphs refreshed:** <2D counts, 3D check result>
- **CI:** <run id, conclusion, and whether it was code or infrastructure>
- **Not done, deliberately:** <open threads and why>
```

Then commit that receipt and push it.

---

## 9. Critical-analysis state (required on ANY failure)

When any step fails — test, docs gate, graph rebuild, commit, push, CI — do not
retry blindly and do not proceed. Work this sequence and write it down:

1. **Symptom** — the literal error text or the exact non-zero exit.
2. **Scope** — which step, which file, since which commit. `git log -1 --stat`,
   `git diff` of the relevant path.
3. **Hypothesis** — the mechanism, stated so it can be wrong.
4. **Discriminating test** — the specific command that would distinguish this
   hypothesis from the alternatives.
5. **Root cause** — confirmed, not assumed.
6. **Fix** — the smallest change that addresses the cause, not the symptom.
7. **Re-verification** — re-run the failing command *and* the neighbouring checks.
8. **Record** — what happened and what was learned, in the receipt.

Forbidden shortcuts: deleting a failing test, weakening an assertion, adding a
suppression, skipping a stage, `--no-verify`, force-pushing, or silently updating a
documented number to match a broken run.

---

## 10. Standing engineering rules

- One branch: `main`. Commit and push completed work rather than leaving it in the
  tree (unless the owner says otherwise for a specific change).
- Preserve the existing dependencies and configuration. Do not swap the package
  manager, regenerate lockfiles, or reformat unrelated files.
- A change to shipped behaviour needs a measurement; a change with no measurement is
  an experiment and must be off by default (`Config` flag defaulting to the current
  behaviour).
- Two independent nulls are stronger evidence than one positive result. Report
  unresolved results as unresolved: "no detectable difference at this sample size".
- Determinism matters: same seed and same configuration must reproduce the same
  decisions. Thread counts must not change the chosen move for a fixed seed.
- Correctness before speed. Never trade a legal-move or hidden-information guarantee
  for throughput.

---

## 11. Current state (update at each closeout)

- **No current strength claim exists.** The rulebook changed on 2026-11-14
  (scoring, hand values, 1v1v1 threshold) and every earlier figure measures a
  different game. Those numbers are stamped **VOID** in `docs/research/` — do
  not cite them, and do not build on them.
- **Only `docs/research/STRENGTH_BASELINE.md` may carry a strength claim**, and
  only stamped with the rules version it was measured under.
  `scripts/rules_audit.py` fails any research document that quotes Elo without
  the current rules hash or a SUPERSEDED banner.
- Previous champion label — depth 8, 64 determinization samples, 8 workers — is
  unearned under the current rules and has not been re-measured.
- The voluntary draw action is wired end to end (`AnalysisResultDTO::isDraw`,
  the app plays a recommended draw). Its old +44.3 Elo figure is superseded: the
  rulebook now allows unlimited draws per turn while the engine still caps at
  one (`Config::maxVoluntaryDraws = 1`), so it must be re-measured as part of
  closing rule gap R-15.
- Known dead ends, do not re-litigate: Metal/GPU end-to-end acceleration (slower at
  every batch size), maximin/win-count/trimmed root aggregation, extra determinization
  samples beyond 64 at depth 8.
- Known backlog: the three declared rule gaps (R-06's 101 option, R-15 analysis
  draws, R-22 elimination); transposition-table key and depth-preferred
  replacement; 1v1v1 pruning; production packaging.
- The 1v1 default is now 151 (R-06), and the locked pair is no longer revealed
  (R-17). Those rules remain GAP only for the optional 101 pre-game choice and
  the private look, respectively.
