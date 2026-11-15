# Kaggle Bridge — Free Cloud Compute for the Offline Lab

**Status:** implemented on 2026-11-14 (tier 3) and **proven live on
2026-11-15**. The first 10,000-round session (`cloud-1v1-d8x64-n10000-s1`,
kernel `johan21era/isolyn-lab-0000`) completed at 01:59 UTC: 4 shards, 10,000
rounds, 176,591 decisions, 0 incomplete, assembled and hash-verified. Kaggle
reports `KernelWorkerStatus.COMPLETE`. Source commit `2ed1e9d`; worker platform
Linux x86_64, 4 cores, Python 3.13.18; 1,847 s wall. The session is a symmetric
control — both sides depth 8 / 64 determinizations — so it calibrates the
measurement instrument and proves the portable build; it is not a playing-
strength result. Platform limits were read from Kaggle's own documentation on
2026-11-14; product limits change, so re-check before relying on the arithmetic.

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
   `tools/selfplay/`, `lab/`, and a `cloud/` worker are copied through an explicit
   allowlist into one versioned dataset. No GitHub clone and no internet toggle
   needed inside the notebook. The app, Accelerator, tests, build output and
   `lab/data` are excluded.
2. **One generated notebook per session.** The notebook is fully
   environment-driven: an embedded session spec names the shard range, seeds,
   configuration and output paths. It builds with `g++ -std=c++20 -O2 -pthread`,
   runs `selfplay --check`, runs each shard, and writes `out/shard-*.csv` plus a
   `session.json` receipt (source commit, config, per-file game/row/byte/SHA-256,
   totals and status). It is private, CPU-only and has internet disabled.
3. **A local driver: `scripts/lab cloud`.** `plan` turns a target game count into
   contiguous sessions; `prepare` builds the private dataset and all session
   specs; `push` submits the next session; `status` polls; `fetch` downloads;
   `verify` recomputes counts and checksums; `assemble` folds only verified
   sessions into the corpus. It keeps a ledger on disk and treats a session as
   done only when the artefacts verify.
4. **Assembly.** Session CSVs have their game ids rewritten per shard before
   concatenation, exactly as `lab merge` does per run; the result is written
   atomically and refuses gaps, overlaps or unverified sessions.
5. **A determinism policy.** The engine and harness now use the in-tree
   `StableRandom.hpp` (raw `std::mt19937_64`, rejection sampling, Fisher-Yates,
   53-bit doubles) instead of implementation-defined `std::shuffle` and
   `std::uniform_*` mappings. A pinned fixture records the expected sequence.
   The dataset and receipt also record the source commit, platform and code
   digest, so a cross-platform mismatch is still visible rather than silent.

A generic `cloud/` contract — job spec in, artefact manifest out — keeps the
worker reusable; Kaggle is one backend behind it, not the abstraction itself.

## Blockers addressed in code (2026-11-14)

1. **The build is macOS-only.** `tools/selfplay/build.sh` now selects the
   Security framework only on Darwin, uses `-pthread` on both platforms, honours
   `ISOLYN_SELFPLAY_OUT`, and refuses an unsupported platform. `EntropySource.cpp`
   already has a `getrandom()` path. A fake-toolchain test pins the Linux and
   Darwin argument sets. **Actual Linux compilation is now proven**, not
   inferred: the worker built the portable harness on Kaggle's x86_64 Linux and
   ran 10,000 rounds to completion on 2026-11-15. The open receipt records the
   platform, source commit and code digest, so a future cross-platform
   divergence stays visible instead of silent.
2. **The same seed could not reproduce the same deals across platforms.**
   `dealSeeded` (selfplay), `Determinizer`, and `SimulationEngine` now use
   `StableRandom.hpp` instead of implementation-defined `std::shuffle` and
   `std::uniform_*_distribution`. The helper uses raw `std::mt19937_64` output,
   rejection sampling, Fisher-Yates and a 53-bit unit interval. `StableRandomTests`
   pins the expected indices, shuffle and unit-interval value. The corpus and
   receipt still record platform and code digest, because a deterministic test on
   macOS is evidence about the algorithm, not proof about the Kaggle binary.
3. **Metal is irrelevant and should be excluded.** `Accelerator/` is
   Objective-C++ against Metal; it does not build on Linux and would not help if
   it did. It is excluded from the cloud allowlist.

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

## Session contract

A session is accepted only when all of the following hold:

- the receipt is a JSON object with the same run id, source commit, code digest,
  dataset reference and exact config as the plan;
- every planned shard appears exactly once, with no extra shard and no duplicate;
- each CSV has the expected header and is a whole number of games with ids
  `0..games-1`, and every row's seed and mode match the planned shard;
- each shard's game count and row count match the receipt, and the file SHA-256
  matches the receipt;
- the receipt's totals equal the sum of the shards and the plan's shard total;
- the session status is `complete`.

`fetch` downloads into a temporary directory, validates, copies only the declared
files, validates the copy, and only then renames it into place. `assemble`
re-verifies every session immediately before writing, so a hand-edited ledger or
a stale receipt cannot silently enter the corpus.

Before a session starts, the worker verifies every file against the dataset's
`snapshot.json` and the plan's code digest. `push` repeats that check, rejects
unexpected files or symlinks in the dataset/kernel directories, and refuses any
notebook metadata that is not private, CPU-only and internet-disabled.

Operational details and the exact commands live in
[`cloud/README.md`](../../cloud/README.md). The local worker and verifier are
covered by `lab/tests/test_cloud.py`, `lab/tests/test_cloud_worker.py` and
`lab/tests/test_build_script.py`.
