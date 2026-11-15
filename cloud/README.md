# Isolyn cloud bridge

**Status:** the local driver, staged source bundle, app Cloud tab and Kaggle
worker are implemented and tested offline. A live Kaggle session has **not** been
run in this checkout; it requires a Kaggle account and API credentials. No token
is stored in this repository or read by the app.

The cloud bridge lets Kaggle run the existing C++ self-play harness as a private
batch worker. It does not run the macOS app, and it does not add a second rules
engine. The C++ harness remains the only source of game truth.

## What is safe by construction

- A plan is a contiguous list of shard ranges. Shards cannot overlap or go
  missing; assembly re-checks the full coverage.
- `plan` and `prepare` require a **clean source state**. From the checkout that
  is a clean Git commit; from the app it is the build-time bundle in
  `~/Library/Application Support/IsolynV2.0/Lab/source.json`, which records the
  commit, clean state, exact file list and SHA-256 code digest. The app never
  invokes Git against the checkout after staging. A changed or dirty bundle is
  refused.
- The code snapshot is allowlisted: engine, self-play harness, lab Python and
  the worker only. The app, Accelerator, tests, build output and `lab/data`
  cannot be uploaded.
- The planned commit and SHA-256 code digest are recorded in every session spec
  and receipt, and are checked again locally. Before building, the worker also
  verifies every file against the dataset's `snapshot.json`; a tampered snapshot
  fails before a session starts.
- `push` verifies the prepared snapshot again, rejects unexpected files or
  symlinks in the upload directories, and requires the generated notebook
  metadata to be private, CPU-only and internet-disabled.
- Datasets are private by default (`kaggle datasets create` without `--public`).
  Kernels are explicitly private, CPU-only, and have internet disabled.
- `push` is an external action and refuses to run without `--yes`. It does not
  read the Kaggle token; the installed `kaggle` CLI uses its normal per-user
  config.
- `fetch` refuses to overwrite an existing session. It downloads into a
  temporary directory, validates the receipt/hash/row count, rejects symlinked
  files, checks every row's seed and mode against the plan, copies only the
  declared files, validates again, then renames into place.
- `assemble` refuses unless every session was verified. It re-verifies before
  writing, rewrites game ids per shard, and replaces the output atomically.

## One-time setup

1. Create a Kaggle account and download its API token to the normal location
   (`~/.kaggle/kaggle.json`). Never put that file in this repository.
2. Install the Kaggle CLI (`pip install kaggle`) and confirm `kaggle --version`.
3. Set `KAGGLE_USERNAME` or pass `--owner`.
4. Commit the code you intend to upload. Cloud planning refuses a dirty tree.

## Small first run

Use 10,000 games in one session. Do not start with five million. The app's
**Lab → Cloud** tab is the normal path: enter the Kaggle owner, confirm the
private upload, and the app runs the fixed plan below through prepare and push.
Afterward, **Check Kaggle status** is the only action. **Collect verified
results** appears only when that check reports the notebook complete; it then
fetches, verifies and assembles the session.

From a terminal, after committing the checkout:

```bash
./run.sh   # builds the app and stages the allowlisted source + source.json

./scripts/lab cloud plan \
  --games 10000 --games-per-shard 2500 --session-games 10000 \
  --parallel 4 --workers 1 --owner <your-kaggle-username>

./scripts/lab cloud prepare cloud-1v1-d8x64-n10000-s1
./scripts/lab cloud push cloud-1v1-d8x64-n10000-s1 --session 0000 --yes
./scripts/lab cloud status cloud-1v1-d8x64-n10000-s1 --session 0000
./scripts/lab cloud fetch cloud-1v1-d8x64-n10000-s1 --session 0000
./scripts/lab cloud verify cloud-1v1-d8x64-n10000-s1
./scripts/lab cloud assemble cloud-1v1-d8x64-n10000-s1
# or, after the kernel reports complete, one command for fetch/verify/assemble:
./scripts/lab cloud collect cloud-1v1-d8x64-n10000-s1 --session 0000
```

`run.sh` records the source provenance even when the tree is dirty, but the
driver refuses to plan or prepare until the bundle says `clean`. Commit and run
`./run.sh` again after a source change.

The app stores plans, downloaded sessions and logs under
`~/Library/Application Support/IsolynV2.0/runs/cloud`, outside the staged
runtime that `run.sh` replaces. The CLI defaults to `lab/data/cloud` instead.

The first push uses `datasets create`; later sessions automatically use
`datasets version`. If dataset creation succeeded but the kernel push failed,
the ledger has no pushed session; rerun with `--dataset-mode version`.

## Session contract

`cloud/run_session.py` builds the harness with `ISOLYN_SELFPLAY_OUT` pointing at
a writable directory, runs `selfplay --check`, then runs the planned shards. Each
shard writes a CSV and a log. A session is `complete` only when every shard
exited zero and every CSV passed the shape/count check. A failed or
time-interrupted session writes a receipt with a non-complete status and is
rejected locally.

The receipt records the source commit, code digest, dataset reference, exact
configuration, platform, per-shard seed/game/row/byte/SHA-256 values, and totals.
The local verifier never trusts those values; it recomputes them.

## Limits and deliberate exclusions

- CPU only. GPU/TPU quota is not useful for this workload.
- Kaggle sessions are capped at 12 hours and `/kaggle/working` at 20 GB. The
  default plan keeps a session to 200,000 games and 11 h 40 m so there is room
  for build and verification. A 5M corpus is therefore a multi-session, likely
  multi-week calendar project, not a speedup over the Mac.
- The free tier is personal-research infrastructure. Read Kaggle's terms before
  uploading proprietary code or data. Use one account; multiple accounts to
  multiply quota is abuse.
- No model training. The Python trainer remains a scaffold; this bridge only
  generates and verifies self-play data.
- No live Kaggle run has been recorded here yet. The first live 10,000-game
  session is still the acceptance gate.

## Verification locally

```bash
PYTHONPATH=lab/src python3 -m unittest discover -s lab/tests
./tools/selfplay/build.sh
./tools/selfplay/build/selfplay --check
```

The Python suite includes a fake harness that exercises the real worker's
build/run/receipt path and deliberate bad-digest, bad-hash, overwrite and
no-confirmation failures. The engine suite carries the pinned cross-platform RNG
fixture; the lab suite carries the build-script platform-flag test.
