"""Resumable, sharded self-play runner.

A large run is split into shards. Each shard is one `tools/selfplay` process
with its own seed, CSV and log. The manifest records a shard as `done` only
after the harness exited 0, its log reports zero incomplete rounds, and its CSV
is complete; everything else is replayed on the next invocation.

The unit of resumption is the shard, deliberately: the C++ harness has no way
to resume mid-file, so an interrupted shard is replayed from its seed. Keeping
shards small (the default is 5,000 games, about two minutes at depth 8) bounds
what an interruption can cost.

Seeds are `base + shard_index`, not a multiple of the harness's golden-ratio
game stride. That matters: the harness seeds game `j` of a shard with
`seed + j * 0x9E3779B97F4A7C15`, so advancing each shard's base by that same
constant would silently replay another shard's deals.
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SELFPLAY = ROOT / "tools" / "selfplay" / "build" / "selfplay"
# The app runs this from inside its bundle and keeps run data in Application
# Support, because a bundle under ~/Desktop is a TCC-protected location: reading
# it makes macOS ask for Desktop access on every rebuild (ad-hoc signing gives a
# new identity each time). The CLI keeps the repo-local default.
RUNS = Path(os.environ.get("ISOLYN_RUNS_DIR") or (ROOT / "lab" / "data" / "runs"))
MANIFEST_VERSION = 1
RUN_ID_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,80}$")

_INTERRUPTED = False


def _now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def _atomic_json(path: Path, data: dict) -> None:
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    os.replace(tmp, path)


def _check_run_id(run_id: str) -> str:
    if not RUN_ID_PATTERN.match(run_id):
        raise SystemExit(f"invalid run id {run_id!r}: use letters, digits, dot, dash, underscore")
    return run_id


def _run_dir(run_id: str) -> Path:
    return RUNS / _check_run_id(run_id)


def _default_run_id(config: dict) -> str:
    return (
        f"{config['mode']}-d{config['depth']}x{config['determinizations']}"
        f"-n{config['games']}-s{config['seed']}"
    )


def _count_rows(path: Path) -> int:
    with path.open("rb") as handle:
        return max(0, sum(1 for _ in handle) - 1)


def _csv_complete(path: Path) -> bool:
    """A complete shard CSV ends on a newline and starts with the real header."""
    if not path.exists() or path.stat().st_size == 0:
        return False
    with path.open("rb") as handle:
        head = handle.readline()
        handle.seek(-1, os.SEEK_END)
        return head.startswith(b"game,seed,mode,") and handle.read(1) == b"\n"


def _log_confirms(path: Path, games: int) -> bool:
    if not path.exists():
        return False
    text = path.read_text(encoding="utf-8", errors="replace")
    return f"completed rounds: {games}" in text and "incomplete rounds: 0" in text


def _shard_is_valid(entry: dict, shard_dir: Path) -> bool:
    if entry.get("status") != "done":
        return False
    csv_path = shard_dir / entry["csv"]
    return _csv_complete(csv_path) and _log_confirms(shard_dir / entry["log"], entry["games"])


def _plan_shards(args: argparse.Namespace, per_shard: int, shard_count: int) -> list[dict]:
    shards = []
    for index in range(shard_count):
        first = index * per_shard
        games = min(per_shard, args.games - first)
        if games <= 0:
            break
        shards.append(
            {
                "index": index,
                "seed": args.seed + index,
                "games": games,
                "status": "pending",
                "exit": None,
                "rows": 0,
                "csv": f"shard-{index:04d}.csv",
                "log": f"shard-{index:04d}.log",
                "started_at": None,
                "finished_at": None,
                "pid": None,
                "reason": None,
            }
        )
    return shards


def _lock(path: Path) -> None:
    """Refuse to run two runners against one run directory."""
    if path.exists():
        try:
            pid = int(path.read_text().strip())
        except ValueError:
            pid = -1
        if pid > 0:
            try:
                os.kill(pid, 0)
            except OSError:
                pass
            else:
                raise SystemExit(f"run is already active (pid {pid}); use `lab status` to watch it")
    path.write_text(str(os.getpid()), encoding="utf-8")


def _command(entry: dict, config: dict, shard_dir: Path) -> list[str]:
    cmd = [
        str(SELFPLAY),
        "--games", str(entry["games"]),
        "--mode", config["mode"],
        "--depth", str(config["depth"]),
        "--determinizations", str(config["determinizations"]),
        "--workers", str(config["workers"]),
        "--seed", str(entry["seed"]),
        "--output", str(shard_dir / entry["csv"]),
    ]
    optional = (
        ("opponent_depth", "--opponent-depth"),
        ("opponent_determinizations", "--opponent-determinizations"),
        ("opponent_workers", "--opponent-workers"),
        ("time_ms", "--time-ms"),
        ("voluntary_draw", "--voluntary-draw"),
        ("opponent_voluntary_draw", "--opponent-voluntary-draw"),
    )
    for key, flag in optional:
        value = config.get(key)
        if value is not None:
            cmd += [flag, str(value)]
    return cmd


def _reap_orphans(manifest: dict) -> None:
    """Kill harness children left behind by a runner that died without cleanup.

    A SIGKILL leaves the Python runner gone but its `selfplay` children alive in
    their own session, still writing the shard CSV that the resumed run is about
    to truncate. Two writers to one file is corruption, so the recorded pid is
    checked and, if it is really a selfplay process, stopped.
    """
    for shard in manifest["shards"]:
        pid = shard.pop("pid", None)
        if not pid or shard["status"] == "done":
            continue
        try:
            os.kill(pid, 0)
        except OSError:
            continue
        try:
            comm = subprocess.run(
                ["ps", "-o", "comm=", "-p", str(pid)],
                capture_output=True, text=True, timeout=2,
            ).stdout.strip()
        except (OSError, subprocess.SubprocessError):
            continue
        if "selfplay" not in Path(comm).name.lower():
            continue
        print(f"  reaping orphaned shard {shard['index']} (pid {pid})")
        try:
            os.killpg(os.getpgid(pid), signal.SIGTERM)
        except OSError:
            pass
        for _ in range(20):
            time.sleep(0.05)
            try:
                os.kill(pid, 0)
            except OSError:
                break
        else:
            try:
                os.killpg(os.getpgid(pid), signal.SIGKILL)
            except OSError:
                pass


def _terminate(process: subprocess.Popen) -> None:
    try:
        os.killpg(os.getpgid(process.pid), signal.SIGTERM)
    except OSError:
        pass


def _handle_signal(signum, frame) -> None:  # noqa: ARG001 - signal API
    global _INTERRUPTED
    _INTERRUPTED = True


def _progress(manifest: dict, total_games: int) -> str:
    done = [s for s in manifest["shards"] if s["status"] == "done"]
    games_done = sum(s["games"] for s in done)
    started = manifest.get("started_at")
    elapsed = 0.0
    if started:
        elapsed = max(1e-9, (datetime.now(timezone.utc) - datetime.fromisoformat(started)).total_seconds())
    rate = games_done / elapsed if elapsed else 0.0
    remaining = total_games - games_done
    eta = f"{remaining / rate / 3600:.1f}h" if rate > 0 else "--"
    pct = 100.0 * games_done / total_games if total_games else 100.0
    return (
        f"{len(done)}/{len(manifest['shards'])} shards | {games_done}/{total_games} games "
        f"({pct:.1f}%) | {rate:.1f} games/s | eta {eta}"
    )


def _execute(args: argparse.Namespace) -> int:
    global _INTERRUPTED

    if not SELFPLAY.exists():
        print(f"self-play harness not built: {SELFPLAY}", file=sys.stderr)
        print("run: ./tools/selfplay/build.sh", file=sys.stderr)
        return 2

    per_shard = args.games_per_shard
    shard_count = args.shards or -(-args.games // per_shard)
    shard_count = max(1, min(shard_count, args.games))
    per_shard = -(-args.games // shard_count)

    config = {
        "games": args.games,
        "mode": args.mode,
        "depth": args.depth,
        "determinizations": args.determinizations,
        "workers": args.workers,
        "seed": args.seed,
        "shards": shard_count,
        "games_per_shard": per_shard,
        # The C++ harness defaults side B to 4 / 20, not to side A's values.
        # Left alone, a "depth 8 / 64 self-play" run would really be 8/64 against
        # 4/20: half its moves weaker, and its Elo report a config comparison
        # rather than self-play. Resolve B to A unless the caller says otherwise.
        "opponent_depth": args.opponent_depth if args.opponent_depth is not None else args.depth,
        "opponent_determinizations": (
            args.opponent_determinizations
            if args.opponent_determinizations is not None
            else args.determinizations
        ),
        "opponent_workers": args.opponent_workers,
        "time_ms": args.time_ms,
        "voluntary_draw": args.voluntary_draw,
        "opponent_voluntary_draw": args.opponent_voluntary_draw,
    }

    run_id = _check_run_id(args.run_id or _default_run_id(config))
    run_dir = _run_dir(run_id)
    manifest_path = run_dir / "manifest.json"

    if run_dir.exists() and args.restart:
        shutil.rmtree(run_dir)
    run_dir.mkdir(parents=True, exist_ok=True)
    (run_dir / "shards").mkdir(exist_ok=True)

    if manifest_path.exists():
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        if manifest.get("config") != config:
            print(f"{run_id}: existing run has a different configuration.", file=sys.stderr)
            print("use --restart to discard it, or a new --run-id.", file=sys.stderr)
            return 2
        for shard in manifest["shards"]:
            if shard["status"] == "running":
                shard["status"] = "pending"
                shard["reason"] = "interrupted"
    else:
        manifest = {
            "version": MANIFEST_VERSION,
            "run_id": run_id,
            "created_at": _now(),
            "started_at": None,
            "updated_at": _now(),
            "config": config,
            "shards": _plan_shards(args, per_shard, shard_count),
        }

    _lock(run_dir / "run.lock")
    signal.signal(signal.SIGINT, _handle_signal)
    signal.signal(signal.SIGTERM, _handle_signal)

    if manifest["started_at"] is None:
        manifest["started_at"] = _now()

    shard_dir = run_dir / "shards"
    for shard in manifest["shards"]:
        if shard["status"] == "done" and not _shard_is_valid(shard, shard_dir):
            shard["status"] = "pending"
            shard["reason"] = "recorded done but its output is missing or truncated"

    _reap_orphans(manifest)
    queued = [s for s in manifest["shards"] if s["status"] != "done"]
    print(f"run {run_id}")
    print(f"  {_progress(manifest, args.games)}")
    if not queued:
        print("nothing to do: every shard is already complete")
        _atomic_json(manifest_path, {**manifest, "updated_at": _now()})
        (run_dir / "run.lock").unlink(missing_ok=True)
        return 0

    running: dict[int, subprocess.Popen] = {}
    logs: dict[int, object] = {}
    failures = 0

    try:
        while (queued and not _INTERRUPTED) or running:
            while queued and len(running) < args.parallel and not _INTERRUPTED:
                shard = queued.pop(0)
                shard["status"] = "running"
                shard["started_at"] = _now()
                shard["finished_at"] = None
                shard["reason"] = None
                log_path = shard_dir / shard["log"]
                handle = log_path.open("w", encoding="utf-8")
                logs[shard["index"]] = handle
                process = subprocess.Popen(
                    _command(shard, config, shard_dir),
                    stdout=handle,
                    stderr=subprocess.STDOUT,
                    start_new_session=True,
                )
                running[shard["index"]] = process
                shard["pid"] = process.pid
                _atomic_json(manifest_path, {**manifest, "updated_at": _now()})

            if _INTERRUPTED:
                for process in running.values():
                    _terminate(process)

            for index, process in list(running.items()):
                code = process.poll()
                if code is None:
                    continue
                process.wait()
                logs.pop(index, None).close()
                shard = next(s for s in manifest["shards"] if s["index"] == index)
                del running[index]
                csv_path = shard_dir / shard["csv"]
                killed_by_us = _INTERRUPTED and code is not None and code < 0
                if killed_by_us:
                    # We stopped it, so it is not a failure; it is simply unfinished.
                    shard["status"] = "pending"
                    shard["reason"] = "interrupted"
                    shard["exit"] = None
                    shard["pid"] = None
                    shard["finished_at"] = _now()
                elif code == 0 and _csv_complete(csv_path) and _log_confirms(shard_dir / shard["log"], shard["games"]):
                    shard["status"] = "done"
                    shard["pid"] = None
                    shard["rows"] = _count_rows(csv_path)
                    shard["exit"] = 0
                    shard["finished_at"] = _now()
                else:
                    shard["pid"] = None
                    shard["status"] = "failed"
                    shard["exit"] = code
                    shard["reason"] = f"harness exit {code} or incomplete output"
                    shard["finished_at"] = _now()
                    failures += 1
                    print(f"  shard {index} FAILED: {shard['reason']} (log: {shard['log']})", file=sys.stderr)
                    if not args.keep_going:
                        queued.clear()
                _atomic_json(manifest_path, {**manifest, "updated_at": _now()})
                if not args.quiet:
                    print(f"  {_progress(manifest, args.games)}")

            if _INTERRUPTED:
                time.sleep(0.1)
            elif not running and not queued:
                break
            else:
                time.sleep(0.25)
    finally:
        for handle in logs.values():
            handle.close()
        for process in running.values():
            _terminate(process)
        for shard in manifest["shards"]:
            if shard["status"] == "running":
                shard["status"] = "pending"
                shard["reason"] = "interrupted"
        _atomic_json(manifest_path, {**manifest, "updated_at": _now()})
        (run_dir / "run.lock").unlink(missing_ok=True)

    print(_progress(manifest, args.games))
    remaining = [s for s in manifest["shards"] if s["status"] != "done"]
    if _INTERRUPTED:
        print(f"interrupted; {len(remaining)} shard(s) will be replayed on the next run")
        return 130
    if remaining:
        print(f"{len(remaining)} shard(s) incomplete; rerun the same command to resume", file=sys.stderr)
        return 1
    print(f"complete: {args.games} games in {run_dir}")
    return 0


def _load_manifest(run_id: str) -> dict:
    path = _run_dir(run_id) / "manifest.json"
    if not path.exists():
        raise SystemExit(f"no such run: {run_id} (try `lab list`)")
    return json.loads(path.read_text(encoding="utf-8"))


def _status(run_id: str) -> int:
    manifest = _load_manifest(run_id)
    config = manifest["config"]
    run_dir = _run_dir(run_id)
    shard_dir = run_dir / "shards"
    print(f"run {run_id}")
    print(f"  config: {config['mode']} depth {config['depth']} / det {config['determinizations']} "
          f"/ workers {config['workers']} / seed {config['seed']}")
    print(f"  {_progress(manifest, config['games'])}")
    broken = [s for s in manifest["shards"] if s["status"] == "done" and not _shard_is_valid(s, shard_dir)]
    failed = [s for s in manifest["shards"] if s["status"] == "failed"]
    pending = [s for s in manifest["shards"] if s["status"] in ("pending", "running")]
    print(f"  shards: {len(manifest['shards'])} total, "
          f"{len(manifest['shards']) - len(broken) - len(failed) - len(pending)} verified done, "
          f"{len(pending)} pending, {len(failed)} failed, {len(broken)} recorded-but-broken")
    for shard in failed[:10]:
        print(f"    failed shard {shard['index']}: {shard['reason']}")
    for shard in broken[:10]:
        print(f"    broken shard {shard['index']}: output missing or truncated")
    return 0 if not failed and not broken and not pending else 1


def _list_runs() -> int:
    if not RUNS.exists():
        print("no runs yet")
        return 0
    for manifest_path in sorted(RUNS.glob("*/manifest.json")):
        try:
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        done = sum(1 for s in manifest["shards"] if s["status"] == "done")
        games = sum(s["games"] for s in manifest["shards"] if s["status"] == "done")
        print(f"{manifest['run_id']:<44} {done:>5}/{len(manifest['shards']):<5} shards "
              f"{games:>9} games  started {manifest.get('started_at') or manifest['created_at']}")
    return 0


def _merge(run_id: str, output: Path | None) -> int:
    manifest = _load_manifest(run_id)
    run_dir = _run_dir(run_id)
    shard_dir = run_dir / "shards"
    pending = [s for s in manifest["shards"] if s["status"] != "done"]
    if pending:
        raise SystemExit(f"{run_id} is not complete: {len(pending)} shard(s) remaining")

    output = output or run_dir / "merged.csv"
    offsets, total = {}, 0
    for shard in manifest["shards"]:
        offsets[shard["index"]] = total
        total += shard["games"]

    rows = 0
    with output.open("w", newline="", encoding="utf-8") as destination:
        writer = csv.writer(destination)
        wrote_header = False
        for shard in manifest["shards"]:
            with (shard_dir / shard["csv"]).open(newline="", encoding="utf-8") as source:
                reader = csv.reader(source)
                header = next(reader)
                game_col = header.index("game")
                seed_col = header.index("seed")
                if not wrote_header:
                    writer.writerow(header)
                    wrote_header = True
                offset = offsets[shard["index"]]
                for row in reader:
                    row[game_col] = str(offset + int(row[game_col]))
                    row[seed_col] = str(shard["seed"])
                    writer.writerow(row)
                    rows += 1
    print(f"wrote {output} ({total} games, {rows} move rows)")
    if output.stat().st_size > 2 * 1024 ** 3:
        print("warning: larger than 2 GiB; `isolyn-lab evaluate` loads a CSV into memory", file=sys.stderr)
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="lab",
        description="Resumable sharded self-play runs for IsolynV2.0.",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    run = sub.add_parser("run", help="start or resume a sharded run")
    run.add_argument("--games", type=int, default=200)
    run.add_argument("--shards", type=int, default=0, help="default: ceil(games / games-per-shard)")
    run.add_argument("--games-per-shard", type=int, default=5000)
    run.add_argument("--parallel", type=int, default=min(8, os.cpu_count() or 1))
    run.add_argument("--mode", default="1v1", choices=("1v1", "1v1v1", "2v2"))
    run.add_argument("--depth", type=int, default=8)
    run.add_argument("--determinizations", type=int, default=64)
    run.add_argument("--workers", type=int, default=1)
    run.add_argument("--seed", type=int, default=1)
    run.add_argument("--opponent-depth", type=int)
    run.add_argument("--opponent-determinizations", type=int)
    run.add_argument("--opponent-workers", type=int)
    run.add_argument("--time-ms", type=int)
    run.add_argument("--voluntary-draw", type=int)
    run.add_argument("--opponent-voluntary-draw", type=int)
    run.add_argument("--run-id")
    run.add_argument("--restart", action="store_true", help="discard an existing run with this id")
    run.add_argument("--keep-going", action="store_true", help="continue past a failed shard")
    run.add_argument("--quiet", action="store_true")

    status = sub.add_parser("status", help="show a run's progress and verify its shards")
    status.add_argument("run_id")

    listing = sub.add_parser("list", help="list runs")

    merge = sub.add_parser("merge", help="merge completed shards into one CSV")
    merge.add_argument("run_id")
    merge.add_argument("--output", type=Path)

    # The app keeps run data outside the checkout (see LabPaths.dataDirectory);
    # this flag points the CLI at that store for one invocation.
    for subparser in (run, status, listing, merge):
        subparser.add_argument("--runs-dir", type=Path, help=argparse.SUPPRESS)

    return parser


def main(argv: list[str] | None = None) -> int:
    global RUNS
    args = build_parser().parse_args(argv)
    if getattr(args, "runs_dir", None):
        RUNS = args.runs_dir
    if args.command == "run":
        if args.games <= 0 or args.games_per_shard <= 0 or args.parallel <= 0:
            raise SystemExit("--games, --games-per-shard and --parallel must be positive")
        return _execute(args)
    if args.command == "status":
        return _status(args.run_id)
    if args.command == "list":
        return _list_runs()
    return _merge(args.run_id, args.output)


if __name__ == "__main__":
    raise SystemExit(main())
