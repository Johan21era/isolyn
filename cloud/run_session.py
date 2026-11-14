#!/usr/bin/env python3
"""Run one pre-planned Isolyn cloud session and write a verifiable receipt.

This file is copied into the private Kaggle code dataset. It uses only the
Python standard library and the C++ engine already in that dataset. Kaggle's
input mount is treated as read-only; all build and result files go under
--output (normally /kaggle/working/out).

The worker never decides a game rule. It starts the real tools/selfplay binary,
checks its CSV shape, and records what happened. The local driver re-hashes and
re-counts every artifact before accepting a session.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import re
import signal
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

SCHEMA = 1
ID_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,80}$")
MAX_SESSION_SECONDS = 43_200  # Kaggle's hard 12-hour limit.

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "lab" / "src"))
from isolyn_lab.cloud_verify import (  # noqa: E402
    inspect_csv,
    sha256_file,
    verify_code_snapshot,
)


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def atomic_json(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    os.replace(temporary, path)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def validate_spec(spec: dict) -> None:
    require(spec.get("schema") == SCHEMA, "unsupported session spec schema")
    for key in ("run_id", "session_id"):
        require(isinstance(spec.get(key), str) and ID_PATTERN.match(spec[key]) is not None,
                f"invalid {key}")
    require(isinstance(spec.get("source_commit"), str)
            and re.fullmatch(r"[0-9a-f]{40,64}", spec["source_commit"]) is not None,
            "invalid source_commit")
    require(isinstance(spec.get("code_sha256"), str)
            and re.fullmatch(r"[0-9a-f]{64}", spec["code_sha256"]) is not None,
            "invalid code_sha256")
    require(isinstance(spec.get("dataset_ref"), str)
            and re.fullmatch(r"[a-z0-9][a-z0-9_-]{0,49}/[a-z0-9][a-z0-9-]{2,49}",
                              spec["dataset_ref"]) is not None,
            "invalid dataset_ref")
    config = spec.get("config")
    require(isinstance(config, dict), "missing config")
    require(config.get("mode") in ("1v1", "1v1v1", "2v2"), "invalid mode")
    for key in ("depth", "determinizations", "opponent_depth",
                "opponent_determinizations", "workers"):
        require(isinstance(config.get(key), int) and config[key] > 0, f"invalid config.{key}")
    for key in ("time_ms", "voluntary_draw", "opponent_voluntary_draw"):
        require(isinstance(config.get(key), int) and config[key] >= 0, f"invalid config.{key}")
    require(config["workers"] <= 4, "workers must not exceed 4")
    parallel = spec.get("parallel")
    require(isinstance(parallel, int) and 1 <= parallel <= 4, "parallel must be 1..4")
    require(parallel * config["workers"] <= 4,
            "parallel * workers exceeds Kaggle's four CPU cores")
    max_seconds = spec.get("max_seconds", 39_600)
    require(isinstance(max_seconds, int) and 60 <= max_seconds <= MAX_SESSION_SECONDS,
            f"max_seconds must be 60..{MAX_SESSION_SECONDS}")

    shards = spec.get("shards")
    require(isinstance(shards, list) and shards, "session has no shards")
    seen = set()
    for shard in shards:
        require(isinstance(shard, dict), "shard entry is not an object")
        index = shard.get("index")
        require(isinstance(index, int) and index >= 0, "invalid shard index")
        require(index not in seen, f"duplicate shard index {index}")
        seen.add(index)
        require(isinstance(shard.get("games"), int) and shard["games"] > 0,
                f"shard {index}: invalid games")
        require(isinstance(shard.get("seed"), int) and shard["seed"] >= 0,
                f"shard {index}: invalid seed")
    ordered = sorted(seen)
    require(ordered == list(range(ordered[0], ordered[-1] + 1)),
            "shards must be a contiguous index range")


def shard_command(binary: Path, config: dict, shard: dict, csv_path: Path) -> list[str]:
    command = [
        str(binary),
        "--games", str(shard["games"]),
        "--mode", str(config["mode"]),
        "--depth", str(config["depth"]),
        "--determinizations", str(config["determinizations"]),
        "--workers", str(config["workers"]),
        "--seed", str(shard["seed"]),
        "--output", str(csv_path),
        # Never leave B at the harness defaults (4/20): a symmetric run must be
        # symmetric or its numbers mean something else.
        "--opponent-depth", str(config["opponent_depth"]),
        "--opponent-determinizations", str(config["opponent_determinizations"]),
        "--opponent-workers", str(config["workers"]),
        "--time-ms", str(config["time_ms"]),
        "--voluntary-draw", str(config["voluntary_draw"]),
        "--opponent-voluntary-draw", str(config["opponent_voluntary_draw"]),
    ]
    return command


def terminate(processes: list[subprocess.Popen]) -> None:
    for process in processes:
        if process.poll() is not None:
            continue
        try:
            if hasattr(os, "killpg"):
                os.killpg(os.getpgid(process.pid), signal.SIGTERM)
            else:  # pragma: no cover - Kaggle/Linux always takes the branch above
                process.terminate()
        except OSError:
            pass
    deadline = time.monotonic() + 5.0
    for process in processes:
        remaining = max(0.0, deadline - time.monotonic())
        try:
            process.wait(timeout=remaining)
        except subprocess.TimeoutExpired:
            try:
                if hasattr(os, "killpg"):
                    os.killpg(os.getpgid(process.pid), signal.SIGKILL)
                else:  # pragma: no cover
                    process.kill()
            except OSError:
                pass


def collect_shard(output: Path, shard: dict, log_path: Path, returncode: int) -> dict:
    csv_path = output / f"shard-{shard['index']:04d}.csv"
    inspected = inspect_csv(csv_path, int(shard["games"]))
    return {
        "index": shard["index"],
        "seed": shard["seed"],
        "games": shard["games"],
        "csv": csv_path.name,
        "rows": inspected["rows"],
        "bytes": csv_path.stat().st_size,
        "sha256": sha256_file(csv_path),
        "log": log_path.name,
        "log_bytes": log_path.stat().st_size,
        "log_sha256": sha256_file(log_path),
        "exit_code": returncode,
    }


def run(root: Path, spec_path: Path, output: Path) -> int:
    started = time.monotonic()
    started_at = utc_now()
    root = root.resolve()
    output = output.resolve()
    spec = json.loads(spec_path.read_text(encoding="utf-8"))
    validate_spec(spec)
    try:
        verify_code_snapshot(root, spec["source_commit"], spec["code_sha256"])
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        raise SystemExit(f"code snapshot failed verification: {exc}") from exc

    output.mkdir(parents=True, exist_ok=True)
    receipt_path = output / "session.json"
    if receipt_path.exists():
        raise SystemExit(f"refusing to overwrite an existing receipt: {receipt_path}")

    max_seconds = int(spec.get("max_seconds", 39_600))
    deadline = started + max_seconds
    config = spec["config"]
    shards = spec["shards"]
    parallel = int(spec["parallel"])
    processes: list[subprocess.Popen] = []
    open_logs = []
    status = "failed"
    error = None
    verified: list[dict] = []

    def finish() -> None:
        receipt = {
            "schema": SCHEMA,
            "run_id": spec["run_id"],
            "session_id": spec["session_id"],
            "source_commit": spec.get("source_commit"),
            "code_sha256": spec.get("code_sha256"),
            "dataset_ref": spec.get("dataset_ref"),
            "created_at": started_at,
            "finished_at": utc_now(),
            "duration_seconds": round(time.monotonic() - started, 3),
            "status": status,
            "error": error,
            "config": config,
            "parallel": parallel,
            "max_seconds": max_seconds,
            "platform": {
                "system": platform.system(),
                "release": platform.release(),
                "machine": platform.machine(),
                "python": platform.python_version(),
                "cpu_count": os.cpu_count(),
            },
            "shards": verified,
            "total_games": sum(item["games"] for item in verified),
            "total_rows": sum(item["rows"] for item in verified),
        }
        atomic_json(receipt_path, receipt)

    try:
        build_dir = output / "build"
        build_log = output / "build.log"
        env = os.environ.copy()
        env["ISOLYN_SELFPLAY_OUT"] = str(build_dir)
        with build_log.open("w", encoding="utf-8") as log:
            built = subprocess.run(
                ["bash", str(root / "tools" / "selfplay" / "build.sh")],
                cwd=str(root),
                env=env,
                stdout=log,
                stderr=subprocess.STDOUT,
                timeout=min(900, max(60, max_seconds)),
            )
        if built.returncode != 0:
            error = f"build failed with exit {built.returncode}; see {build_log.name}"
            return 1

        binary = build_dir / "selfplay"
        if not binary.is_file() or not os.access(binary, os.X_OK):
            error = "build produced no executable selfplay binary"
            return 1
        check = subprocess.run(
            [str(binary), "--check"],
            cwd=str(root),
            capture_output=True,
            text=True,
            timeout=30,
        )
        if check.returncode != 0:
            error = f"selfplay --check failed with exit {check.returncode}"
            return 1

        pending = list(shards)
        running: dict[int, tuple[subprocess.Popen, object, str]] = {}
        completed: set[int] = set()

        while pending or running:
            if time.monotonic() >= deadline:
                status = "interrupted"
                error = "session time limit reached"
                terminate([proc for proc, _, _ in running.values()])
                break

            while pending and len(running) < parallel:
                shard = pending.pop(0)
                index = int(shard["index"])
                csv_path = output / f"shard-{index:04d}.csv"
                log_path = output / f"shard-{index:04d}.log"
                command = shard_command(binary, config, shard, csv_path)
                log = log_path.open("w", encoding="utf-8")
                open_logs.append(log)
                process = subprocess.Popen(
                    command,
                    cwd=str(root),
                    stdout=log,
                    stderr=subprocess.STDOUT,
                    env=env,
                    start_new_session=True,
                )
                processes.append(process)
                running[index] = (process, log, log_path.name)

            for index, (process, _log, _log_name) in list(running.items()):
                if process.poll() is None:
                    continue
                del running[index]
                log_path = output / f"shard-{index:04d}.log"
                try:
                    if process.returncode != 0:
                        raise ValueError(f"harness exited {process.returncode}")
                    entry = next(item for item in shards if item["index"] == index)
                    verified.append(collect_shard(output, entry, log_path, process.returncode))
                    completed.add(index)
                except (OSError, ValueError) as exc:
                    error = f"shard {index}: {exc}"
                    terminate([proc for proc, _, _ in running.values()])
                    pending.clear()
                    break
            if error:
                break

            if pending or running:
                time.sleep(0.25)

        if not error and len(completed) == len(shards):
            status = "complete"
            verified.sort(key=lambda item: int(item["index"]))
            return 0
        if not error:
            error = "session ended with unfinished shards"
        return 1
    except KeyboardInterrupt:
        status = "interrupted"
        error = "worker interrupted"
        return 130
    except (OSError, ValueError, subprocess.SubprocessError) as exc:
        error = str(exc)
        return 1
    finally:
        terminate(processes)
        for log in open_logs:
            try:
                log.close()
            except OSError:
                pass
        if status != "complete":
            verified.sort(key=lambda item: int(item["index"]))
        finish()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Run one planned Isolyn cloud session.")
    parser.add_argument("--root", type=Path, required=True, help="private code dataset root")
    parser.add_argument("--session", type=Path, required=True, help="session spec JSON")
    parser.add_argument("--output", type=Path, required=True, help="writable output directory")
    args = parser.parse_args(argv)
    try:
        return run(args.root, args.session, args.output)
    except SystemExit as exc:
        print(str(exc), file=sys.stderr)
        return int(exc.code) if isinstance(exc.code, int) else 2


if __name__ == "__main__":
    raise SystemExit(main())
