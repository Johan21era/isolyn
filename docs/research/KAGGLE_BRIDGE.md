# Kaggle Bridge — Free Cloud Compute for the Offline Lab

**Status:** proposed design (tier 2). Nothing here is implemented. Platform limits
were read from Kaggle's own documentation on 2026-11-14; product limits change,
so re-check before relying on the arithmetic.

## Why this workload suits Kaggle

Self-play is the ideal cloud batch job and a poor interactive one:

- shards are independent and addressed by seed;
- a shard is one process with one CSV (~1.95 KB per game);
- the runner already resumes at shard granularity and verifies completion;
- **no GPU is needed.** The Metal accelerator was measured slower end-to-end
  (`METAL_INTEGRATION.md`), and a Kaggle GPU session has the same 4 CPU cores as
  a CPU session. Burning the 30 h/week GPU quota would buy nothing.

## What Kaggle provides (verified)

| Resource | Limit |
|---|---|
| CPU session length | **12 hours** |
| CPU hardware | **4 cores, 30 GB RAM** |
| Saved output | **20 GB** in `/kaggle/working`, auto-saved per notebook version |
| GPU | 1× P100 or 2× T4, 12 h session, **30 h/week** quota |
| TPU | 96 cores / 330 GB RAM, 9 h session, 20 h/week |
| Interactive idle timeout | 20 minutes (irrelevant for "Save & Run All") |
| Programmatic control | `kaggle` CLI / API: push a kernel, poll status, download output |

Not documented and therefore to be measured, not assumed: how many notebook
sessions may run concurrently, and whether back-to-back CPU sessions are
throttled beyond the 12-hour cap.

## The arithmetic

Measured locally, both sides at depth 8 / 64 samples, eight single-worker shards:
**22.7 games/s** on 8 cores (4 performance + 4 efficiency) = 2.84 games/s/core.

Kaggle's 4 server cores are Skylake-era, slower per core than an M3 performance
core, so a defensible estimate is **6–11 games/s per session**. A 12-hour session
minus build and verification is ~11.8 h:

- 6 games/s → 255k games/session; 5M needs **~20 sessions**
- 11 games/s → 467k games/session; 5M needs **~11 sessions**
- output per session: 0.5–0.9 GB, well under the 20 GB cap

At one session a day that is 2–3 weeks; at two, roughly a week. **This is not
faster than the local machine** — a local 5M run is ~61 hours. Kaggle's value is
parallel breadth and not occupying the owner's laptop, not raw speed. That
trade-off should be explicit before the founders invest in it.

## The bridge, in five pieces

1. **A private Kaggle dataset as the code drop.** The engine sources,
   `tools/selfplay/`, `lab/`, and a `cloud/` worker, uploaded as one versioned
   dataset. No GitHub clone and no internet toggle needed inside the notebook.
2. **One notebook, fully environment-driven.** `ISOLYN_SHARD_START`,
   `ISOLYN_SHARD_END`, `ISOLYN_MODE`, `ISOLYN_DEPTH`, `ISOLYN_SAMPLES`,
   `ISOLYN_SEED`. It builds with `g++ -std=c++20 -O2 -pthread`, runs its shard
   range, writes `out/shard-*.csv` plus `session.json` (game count, row count,
   SHA-256 per file), and tars the result.
3. **A local driver: `scripts/lab cloud`.** `plan` turns a target game count into
   sessions; `push` submits the next session; `status` polls; `fetch` downloads
   the output; `verify` checks counts and checksums against `session.json`;
   `assemble` folds verified sessions into the corpus. It keeps a ledger on disk
   and treats a session as done only when the artefacts verify — the same rule
   `lab run` already applies to shards.
4. **Assembly.** Session CSVs need game ids rewritten per session before
   concatenation, exactly as `lab merge` does per shard; extend it to take a
   session list rather than one run directory.
5. **A determinism policy.** Datasets are labelled by platform (see blocker 2).

A generic `cloud/` contract — job spec in, artefact manifest out — keeps the
worker reusable for the founders' other projects; Kaggle is one backend behind
it, not the abstraction itself.

## Three blockers, verified in this tree

1. **The build is macOS-only.** `tools/selfplay/build.sh` passes
   `-framework Security`, which Linux's linker rejects. `EntropySource.cpp`
   already has a `getrandom()` path, so the fix is to make the flag conditional
   on Darwin. Small, but nothing compiles on Kaggle until it is done.
2. **The same seed will not reproduce the same deals across platforms.**
   `dealSeeded` (selfplay), `Determinizer`, and `SimulationEngine` use
   `std::shuffle` and `std::uniform_*_distribution`, whose mappings are
   implementation-defined. libc++ on macOS and libstdc++ on Kaggle may produce
   different permutations from the same `mt19937_64` seed. The statistics remain
   valid; "same seed, same games" becomes false the moment a dataset crosses
   platforms. Either accept and label datasets by platform, or implement a stable
   Fisher-Yates with rejection sampling in-tree and add a fixture test that pins
   the first N deals. **Recommend the latter before any dataset is used for
   training**, because a corpus that cannot be reproduced is a trap for whoever
   trains on it six months later.
3. **Metal is irrelevant and should be excluded.** `Accelerator/` is
   Objective-C++ against Metal; it does not build on Linux and would not help if
   it did.

## Risks worth stating plainly

- **No SLA and preemption.** Sessions can queue or die; the shard ledger makes
  that survivable, but a 5M corpus is a multi-week calendar project.
- **Terms of use.** The free tier is personal-research infrastructure. Using it
  for company workloads may conflict with Kaggle's terms — that needs a read
  before proprietary data or weights go anywhere near it. Multiple accounts to
  multiply quota is abuse, not a strategy.
- **20 GB output and no persistent disk.** Every session's output must be
  fetched and verified or it is lost when the version is superseded.
- **TPU quota is not free CPU.** A 96-core TPU VM is tempting for CPU-only work;
  spending TPU quota on non-TPU compute likely violates the intent of the
  programme. Do not.

## Alternatives, for when Kaggle is the wrong shape

A long-running self-play box wants persistence, not notebooks. Oracle Cloud's
Always Free ARM instance (4 cores, 24 GB, persistent disk) is a better fit for a
continuous run; Colab has the same 12-hour shape without a clean push/fetch API;
GitHub Actions is unavailable here for billing reasons.

## First step — one session, one day

Do not start with 5M games. Run **10,000 games in one Kaggle session** and prove
the whole path: build on Kaggle's image, run, fetch, verify counts and checksums,
and compare the outcome mix and average points against the same configuration
locally. If the distributions agree within their intervals and the artefacts
verify, the session count follows from the measured rate — and only then is a 5M
run a schedule rather than a hope.
