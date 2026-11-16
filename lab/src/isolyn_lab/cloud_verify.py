"""Verification shared by the Kaggle session worker and the local driver.

The remote machine is not trusted just because it exited zero. A session is
accepted only after its receipt says complete, every declared shard exists at
the expected relative path, its SHA-256 matches, and the CSV itself has a valid
header, complete rows, and exactly the expected game count.

This module deliberately knows nothing about game rules. The C++ engine remains
the only authority for moves, legality, and scoring.
"""

from __future__ import annotations

import csv
import hashlib
import json
import re
from pathlib import Path, PurePosixPath

SESSION_SCHEMA = 1
SHARD_NAME = re.compile(r"^shard-(\d{4})\.csv$")
LOG_NAME = re.compile(r"^shard-(\d{4})\.log$")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def code_digest(files: list[dict]) -> str:
    """Hash the allowlisted path/hash manifest exactly as the driver does."""
    digest = hashlib.sha256()
    for entry in sorted(files, key=lambda item: item["path"]):
        digest.update(entry["path"].encode("utf-8"))
        digest.update(b"\0")
        digest.update(entry["sha256"].encode("ascii"))
        digest.update(b"\n")
    return digest.hexdigest()


def verify_code_snapshot(root: Path, source_commit: str, expected_digest: str) -> list[dict]:
    """Prove the code beside the worker is the exact code the plan authorized.

    The worker otherwise trusts its input mount. Checking the manifest here makes
    a tampered or stale dataset fail before it can spend a session running
    different code under the planned commit/hash labels.
    """
    root = root.resolve()
    snapshot_path = root / "snapshot.json"
    if snapshot_path.is_symlink() or not snapshot_path.is_file():
        raise ValueError("missing safe snapshot.json")
    snapshot = json.loads(snapshot_path.read_text(encoding="utf-8"))
    _require(snapshot.get("schema") == SESSION_SCHEMA,
             "unsupported code snapshot schema")
    _require(snapshot.get("source_commit") == source_commit,
             "code snapshot source commit mismatch")
    _require(snapshot.get("code_sha256") == expected_digest,
             "code snapshot digest mismatch")
    declared = snapshot.get("files")
    _require(isinstance(declared, list) and declared, "code snapshot has no files")

    checked = []
    seen = set()
    for entry in declared:
        _require(isinstance(entry, dict), "code snapshot entry is not an object")
        relative = entry.get("path")
        _require(isinstance(relative, str) and relative, "code snapshot path is invalid")
        pure = PurePosixPath(relative)
        _require(not pure.is_absolute() and ".." not in pure.parts and "\\" not in relative,
                 f"unsafe code snapshot path: {relative!r}")
        _require(relative not in seen, f"duplicate code snapshot path: {relative}")
        seen.add(relative)
        raw_path = root / relative
        _require(not raw_path.is_symlink(), f"symlinked code snapshot file: {relative}")
        path = raw_path.resolve()
        _require(root in path.parents, "code snapshot path escapes its root")
        _require(path.is_file() and not path.is_symlink(), f"missing code snapshot file: {relative}")
        actual_hash = sha256_file(path)
        _require(entry.get("sha256") == actual_hash, f"code snapshot hash mismatch: {relative}")
        _require(entry.get("bytes") == path.stat().st_size,
                 f"code snapshot byte count mismatch: {relative}")
        checked.append({"path": relative, "sha256": actual_hash, "bytes": path.stat().st_size})
    _require(code_digest(checked) == expected_digest, "code snapshot manifest digest mismatch")
    return checked


def safe_relative_name(name: str, pattern: re.Pattern[str]) -> str:
    """Accept only a bare shard/log filename, never a path or symlink target."""
    if not isinstance(name, str) or Path(name).name != name or not pattern.match(name):
        raise ValueError(f"unsafe session filename: {name!r}")
    return name


def inspect_csv(path: Path, expected_games: int, expected_seed: int | None = None,
                expected_mode: str | None = None) -> dict:
    """Read one self-play CSV without reimplementing any game logic.

    Returns rows/games and checks the shape the merger relies on: a real header,
    complete rows, artifact game ids starting at 0, increasing by whole games,
    and ending at expected_games - 1. When supplied, the seed and mode columns
    must describe the planned shard on every row.
    """
    if path.is_symlink():
        raise ValueError(f"{path}: refusing a symlink")
    if not path.is_file():
        raise ValueError(f"{path}: not a file")
    with path.open(newline="", encoding="utf-8") as handle:
        reader = csv.reader(handle)
        try:
            header = next(reader)
        except StopIteration:
            raise ValueError(f"{path}: empty CSV") from None
        if len(header) < 3 or header[:3] != ["game", "seed", "mode"]:
            raise ValueError(f"{path}: header must start with game,seed,mode")

        rows = 0
        games = 0
        first_game = None
        current_game = None
        for row in reader:
            if not row:
                raise ValueError(f"{path}: blank row")
            if len(row) != len(header):
                raise ValueError(f"{path}: row has {len(row)} columns, expected {len(header)}")
            try:
                game = int(row[0])
            except ValueError:
                raise ValueError(f"{path}: invalid game id {row[0]!r}") from None
            if expected_seed is not None:
                try:
                    seed = int(row[1])
                except ValueError:
                    raise ValueError(f"{path}: invalid seed {row[1]!r}") from None
                if seed != expected_seed:
                    raise ValueError(f"{path}: row seed {seed} does not match planned {expected_seed}")
            if expected_mode is not None and row[2] != expected_mode:
                raise ValueError(f"{path}: row mode {row[2]!r} does not match planned {expected_mode!r}")
            if first_game is None:
                first_game = game
            if current_game is None or game != current_game:
                if current_game is not None and game <= current_game:
                    raise ValueError(f"{path}: game ids are not strictly increasing")
                current_game = game
                games += 1
            rows += 1

    if rows == 0:
        raise ValueError(f"{path}: no move rows")
    if games != expected_games:
        raise ValueError(f"{path}: holds {games} games, receipt declares {expected_games}")
    if first_game != 0 or current_game != expected_games - 1:
        raise ValueError(
            f"{path}: game ids must span 0..{expected_games - 1}, got {first_game}..{current_game}"
        )
    return {"rows": rows, "games": games}


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def validate_session(
    receipt: dict,
    session_dir: Path,
    plan: dict,
    session: dict,
) -> list[dict]:
    """Validate one downloaded session and return its verified shard records."""
    session_dir = session_dir.resolve()
    _require(receipt.get("schema") == SESSION_SCHEMA, "unsupported session schema")
    _require(receipt.get("status") == "complete", "session did not finish complete")
    _require(receipt.get("run_id") == plan.get("run_id"), "session run id does not match plan")
    _require(receipt.get("session_id") == session.get("id"), "session id does not match plan")
    _require(receipt.get("source_commit") == plan.get("source_commit"), "source commit mismatch")
    _require(receipt.get("code_sha256") == plan.get("code_sha256"), "code digest mismatch")
    _require(receipt.get("dataset_ref") == plan.get("dataset_ref"), "dataset reference mismatch")
    # A tournament gives each session its own pairing config; a classic run
    # carries one config for the whole plan.
    expected_config = session.get("config") or plan.get("config")
    _require(receipt.get("config") == expected_config, "session configuration mismatch")

    expected = plan["shards"][session["shard_start"]:session["shard_end"]]
    declared = receipt.get("shards")
    _require(isinstance(declared, list) and len(declared) == len(expected),
             "session shard count does not match plan")

    verified = []
    total_rows = 0
    total_games = 0
    for want, got in zip(expected, declared):
        _require(isinstance(got, dict), "session shard entry is not an object")
        _require(got.get("index") == want.get("index"), "shard index mismatch")
        _require(got.get("seed") == want.get("seed"), "shard seed mismatch")
        _require(got.get("games") == want.get("games"), "shard game count mismatch")
        _require(got.get("exit_code") == 0, "shard did not exit zero")

        csv_name = safe_relative_name(got.get("csv"), SHARD_NAME)
        raw_csv = session_dir / csv_name
        _require(not raw_csv.is_symlink(), f"refusing symlink shard: {csv_name}")
        csv_path = raw_csv.resolve()
        _require(csv_path.parent == session_dir, "shard path escapes the session folder")
        _require(csv_path.is_file() and not csv_path.is_symlink(), f"missing shard: {csv_name}")

        expected_hash = got.get("sha256")
        _require(isinstance(expected_hash, str) and len(expected_hash) == 64,
                 f"{csv_name}: receipt has no SHA-256")
        _require(sha256_file(csv_path) == expected_hash, f"{csv_name}: SHA-256 mismatch")

        inspected = inspect_csv(csv_path, int(want["games"]),
                                int(want["seed"]), plan["config"]["mode"])
        _require(got.get("rows") == inspected["rows"], f"{csv_name}: row count mismatch")
        _require(got.get("bytes") == csv_path.stat().st_size, f"{csv_name}: byte count mismatch")

        log_name = got.get("log")
        if log_name is not None:
            log_name = safe_relative_name(log_name, LOG_NAME)
            raw_log = session_dir / log_name
            _require(not raw_log.is_symlink(), f"refusing symlink log: {log_name}")
            log_path = raw_log.resolve()
            _require(log_path.parent == session_dir, "log path escapes the session folder")
            _require(log_path.is_file() and not log_path.is_symlink(), f"missing log: {log_name}")
            log_hash = got.get("log_sha256")
            _require(isinstance(log_hash, str) and len(log_hash) == 64,
                     f"{log_name}: receipt has no log SHA-256")
            _require(sha256_file(log_path) == log_hash, f"{log_name}: log SHA-256 mismatch")

        verified.append({**got, "path": str(csv_path)})
        total_rows += inspected["rows"]
        total_games += inspected["games"]

    _require(receipt.get("total_rows") == total_rows, "session total row count mismatch")
    _require(receipt.get("total_games") == total_games, "session total game count mismatch")
    return verified
