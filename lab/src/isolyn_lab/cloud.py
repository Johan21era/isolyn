"""Local control plane for pre-planned Kaggle self-play sessions.

This module is deliberately conservative:

- it plans contiguous shard ranges with no gaps or overlaps;
- it snapshots only explicit code paths, not the whole checkout or lab data;
- it refuses to prepare a plan whose clean Git commit or code hash changed;
- it never reads or writes a Kaggle token, and it never shells out with a
  token in an argument;
- it trusts downloaded artifacts only after a receipt/hash/count re-check.

The remote worker lives in ``cloud/run_session.py`` and uses the same
``cloud_verify`` module. The local driver is the only place that invokes the
``kaggle`` CLI.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Callable

from . import cloud_verify

ROOT = Path(__file__).resolve().parents[3]
CLOUD = Path(os.environ.get("ISOLYN_CLOUD_DIR") or (ROOT / "lab" / "data" / "cloud"))
RUN_ID_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,80}$")
OWNER_PATTERN = re.compile(r"^[a-z0-9][a-z0-9_-]{0,49}$")
SLUG_PATTERN = re.compile(r"^[a-z0-9][a-z0-9-]{2,49}$")
SESSION_SCHEMA = 1
PLAN_SCHEMA = 1
LEDGER_SCHEMA = 1
DATASET_LICENSE = [{"name": "other"}]


def _now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def _atomic_json(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    os.replace(temporary, path)


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(message)


def _run_id(value: str) -> str:
    _require(RUN_ID_PATTERN.match(value) is not None,
             f"invalid run id {value!r}: use letters, digits, dot, dash, underscore")
    return value


def _slug(value: str, label: str) -> str:
    value = value.lower()
    _require(SLUG_PATTERN.match(value) is not None,
             f"invalid {label} slug {value!r}: use 3-50 lowercase letters, digits and dashes")
    return value


def _owner(value: str) -> str:
    value = value.lower()
    _require(OWNER_PATTERN.match(value) is not None,
             f"invalid owner {value!r}: use lowercase letters, digits, dash or underscore")
    return value


def _ref(owner: str, slug: str) -> str:
    return f"{_owner(owner)}/{_slug(slug, 'dataset/kernel')}"


def _sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _sha256_file(path: Path) -> str:
    return cloud_verify.sha256_file(path)


def _git_head(root: Path) -> str:
    result = subprocess.run(
        ["git", "-C", str(root), "rev-parse", "HEAD"],
        capture_output=True,
        text=True,
        check=True,
    )
    value = result.stdout.strip()
    _require(bool(value), "git returned an empty commit hash")
    return value


def _git_clean(root: Path) -> bool:
    result = subprocess.run(
        ["git", "-C", str(root), "status", "--porcelain"],
        capture_output=True,
        text=True,
        check=True,
    )
    return not result.stdout.strip()


def _default_kaggle(args: list[str]) -> str:
    result = subprocess.run(["kaggle", *args], capture_output=True, text=True)
    if result.returncode != 0:
        detail = (result.stderr or result.stdout).strip()
        raise SystemExit(f"kaggle {' '.join(args)} failed ({result.returncode}): {detail}")
    return result.stdout.strip()


class Workspace:
    """Injected filesystem/git seam so safety rules can be tested offline."""

    def __init__(
        self,
        root: Path = ROOT,
        data_root: Path | None = None,
        head_fn: Callable[[], str] | None = None,
        clean_fn: Callable[[], bool] | None = None,
        kaggle_fn: Callable[[list[str]], str] | None = None,
    ):
        self.root = root.resolve()
        self.data_root = (data_root or CLOUD).resolve()
        self.head_fn = head_fn or (lambda: _git_head(self.root))
        self.clean_fn = clean_fn or (lambda: _git_clean(self.root))
        self.kaggle_fn = kaggle_fn or _default_kaggle

    def run_dir(self, run_id: str) -> Path:
        return self.data_root / _run_id(run_id)

    def plan_path(self, run_id: str) -> Path:
        return self.run_dir(run_id) / "plan.json"

    def ledger_path(self, run_id: str) -> Path:
        return self.run_dir(run_id) / "ledger.json"


def _allowlisted_files(root: Path) -> list[tuple[str, Path]]:
    """The only source files a cloud dataset may contain.

    The app, Accelerator, tests, build output, docs, and lab data are excluded
    by construction. A future cloud worker needs the engine, the self-play
    harness and the Python verification helpers, not the shipped UI.
    """
    candidates: list[Path] = []
    engine = root / "Sources" / "IsolynEngine"
    if engine.is_dir():
        candidates.extend(sorted(engine.glob("*.cpp")))
        include = engine / "include"
        if include.is_dir():
            candidates.extend(sorted(include.glob("*.hpp")))
    for relative in (
        "tools/selfplay/main.cpp",
        "tools/selfplay/build.sh",
        "tools/selfplay/README.md",
        "lab/pyproject.toml",
        "cloud/run_session.py",
    ):
        path = root / relative
        if path.is_file():
            candidates.append(path)
    lab_src = root / "lab" / "src" / "isolyn_lab"
    if lab_src.is_dir():
        candidates.extend(sorted(lab_src.glob("*.py")))

    files: list[tuple[str, Path]] = []
    seen: set[str] = set()
    for path in candidates:
        if path.is_symlink():
            raise SystemExit(f"refusing symlink in cloud snapshot: {path}")
        if not path.is_file():
            continue
        relative = path.relative_to(root).as_posix()
        if relative in seen:
            continue
        seen.add(relative)
        files.append((relative, path))
    if not files:
        raise SystemExit(f"no allowlisted source files under {root}")
    return files


def _code_manifest(root: Path) -> list[dict]:
    files = _allowlisted_files(root)
    manifest = []
    for relative, path in files:
        data = path.read_bytes()
        manifest.append({"path": relative, "bytes": len(data), "sha256": _sha256_bytes(data)})
    return manifest


def _code_digest(manifest: list[dict]) -> str:
    return cloud_verify.code_digest(manifest)


def _validate_config(args: argparse.Namespace) -> dict:
    _require(args.games > 0, "--games must be positive")
    _require(args.games_per_shard > 0, "--games-per-shard must be positive")
    _require(args.session_games > 0, "--session-games must be positive")
    _require(args.parallel >= 1 and args.parallel <= 4, "--parallel must be 1..4")
    _require(args.workers >= 1 and args.workers <= 4, "--workers must be 1..4")
    _require(args.parallel * args.workers <= 4,
             "--parallel * --workers must not exceed Kaggle's four CPU cores")
    _require(args.depth > 0 and args.determinizations > 0,
             "--depth and --determinizations must be positive")
    _require(args.seed >= 0, "--seed must be non-negative")
    _require(args.max_seconds >= 60 and args.max_seconds <= 43_200,
             "--max-seconds must be 60..43200")
    if args.opponent_depth is not None:
        _require(args.opponent_depth > 0, "--opponent-depth must be positive")
    if args.opponent_determinizations is not None:
        _require(args.opponent_determinizations > 0,
                 "--opponent-determinizations must be positive")
    for value, flag in (
        (args.time_ms, "--time-ms"),
        (args.voluntary_draw, "--voluntary-draw"),
        (args.opponent_voluntary_draw, "--opponent-voluntary-draw"),
    ):
        _require(value >= 0, f"{flag} must be non-negative")
    return {
        "mode": args.mode,
        "depth": args.depth,
        "determinizations": args.determinizations,
        "workers": args.workers,
        "seed": args.seed,
        "opponent_depth": args.opponent_depth if args.opponent_depth is not None else args.depth,
        "opponent_determinizations": (
            args.opponent_determinizations
            if args.opponent_determinizations is not None
            else args.determinizations
        ),
        "opponent_workers": args.workers,
        "time_ms": args.time_ms,
        "voluntary_draw": args.voluntary_draw,
        "opponent_voluntary_draw": args.opponent_voluntary_draw,
    }


def _build_shards(games: int, per_shard: int, seed: int) -> list[dict]:
    shards = []
    for index in range((games + per_shard - 1) // per_shard):
        first = index * per_shard
        shards.append(
            {
                "index": index,
                "seed": seed + index,
                "games": min(per_shard, games - first),
            }
        )
    return shards


def _build_sessions(shards: list[dict], session_games: int) -> list[dict]:
    sessions = []
    start = 0
    while start < len(shards):
        end = start
        total = 0
        while end < len(shards):
            candidate = total + shards[end]["games"]
            if end > start and candidate > session_games:
                break
            total = candidate
            end += 1
        sessions.append(
            {
                "id": f"{len(sessions):04d}",
                "shard_start": start,
                "shard_end": end,
                "shard_count": end - start,
                "games": total,
            }
        )
        start = end
    return sessions


def _default_run_id(args: argparse.Namespace) -> str:
    return f"cloud-{args.mode}-d{args.depth}x{args.determinizations}-n{args.games}-s{args.seed}"


def plan(ws: Workspace, args: argparse.Namespace) -> dict:
    config = _validate_config(args)
    head = ws.head_fn()
    _require(ws.clean_fn(), "source tree is dirty; commit or stash before planning cloud work")
    manifest = _code_manifest(ws.root)
    digest = _code_digest(manifest)
    run_id = _run_id(args.run_id or _default_run_id(args))
    owner = args.owner or os.environ.get("KAGGLE_USERNAME", "")
    _require(bool(owner), "--owner or KAGGLE_USERNAME is required")
    dataset_ref = _ref(owner, args.dataset)
    kernel_slug = _slug(args.kernel, "kernel")
    _require(len(kernel_slug) + 5 <= 50, "kernel slug is too long after the session suffix")
    shards = _build_shards(args.games, args.games_per_shard, args.seed)
    sessions = _build_sessions(shards, args.session_games)
    result = {
        "schema": PLAN_SCHEMA,
        "run_id": run_id,
        "created_at": _now(),
        "source_commit": head,
        "code_sha256": digest,
        "code_manifest": manifest,
        "dataset_ref": dataset_ref,
        "kernel_prefix": kernel_slug,
        "config": config,
        "games": args.games,
        "games_per_shard": args.games_per_shard,
        "session_games": args.session_games,
        "parallel": args.parallel,
        "max_seconds": args.max_seconds,
        "shards": shards,
        "sessions": sessions,
    }
    path = ws.plan_path(run_id)
    if path.exists():
        existing = json.loads(path.read_text(encoding="utf-8"))
        comparable = ("source_commit", "code_sha256", "config", "games",
                      "games_per_shard", "session_games", "parallel", "max_seconds")
        if any(existing.get(key) != result.get(key) for key in comparable):
            raise SystemExit(f"{run_id}: a different cloud plan already exists")
        print(f"{run_id}: plan already exists and matches; nothing written")
        return existing
    if args.dry_run:
        print(f"{run_id}: plan only (dry run; nothing written)")
    else:
        _atomic_json(path, result)
        print(f"{run_id}: wrote {path}")
    print(f"  source: {head}  code: {digest[:12]}")
    print(f"  corpus: {args.games} games in {len(shards)} shards, {len(sessions)} session(s)")
    print(f"  dataset: {dataset_ref}  kernel prefix: {owner}/{kernel_slug}")
    for session in sessions:
        print(f"    session {session['id']}: shards {session['shard_start']}..{session['shard_end'] - 1}, "
              f"{session['games']} games")
    return result


def _dataset_metadata(plan_data: dict) -> dict:
    title = f"Isolyn lab code {plan_data['run_id']}"
    return {
        "title": title[:50] if len(title) >= 6 else "Isolyn lab code",
        "id": plan_data["dataset_ref"],
        "licenses": DATASET_LICENSE,
        "description": (
            "Private source snapshot for the Isolyn offline lab. "
            f"Commit {plan_data['source_commit']}; code digest {plan_data['code_sha256']}. "
            "Generated by the local driver; no game results or account data are included."
        ),
    }


def _kernel_metadata(plan_data: dict, session: dict) -> dict:
    owner = plan_data["dataset_ref"].split("/", 1)[0]
    kernel_id = f"{owner}/{plan_data['kernel_prefix']}-{session['id']}"
    title = f"Isolyn {session['id']} {plan_data['run_id']}"
    return {
        "id": kernel_id,
        "title": title[:50],
        "code_file": "notebook.ipynb",
        "language": "python",
        "kernel_type": "notebook",
        "is_private": True,
        "enable_gpu": False,
        "enable_tpu": False,
        "enable_internet": False,
        "machine_shape": "",
        "dataset_sources": [plan_data["dataset_ref"]],
        "competition_sources": [],
        "kernel_sources": [],
        "model_sources": [],
    }


def _notebook(plan_data: dict, session: dict) -> dict:
    dataset_slug = plan_data["dataset_ref"].split("/", 1)[-1]
    source = (
        "import subprocess, sys\n"
        "from pathlib import Path\n"
        f"root = Path(\"/kaggle/input/{dataset_slug}\")\n"
        f"spec = root / \"session_specs\" / \"{session['id']}.json\"\n"
        "out = Path(\"/kaggle/working/out\")\n"
        "subprocess.run([\n"
        "    sys.executable, str(root / \"cloud\" / \"run_session.py\"),\n"
        "    \"--root\", str(root), \"--session\", str(spec), \"--output\", str(out),\n"
        "], check=True)\n"
    )
    return {
        "cells": [
            {
                "cell_type": "markdown",
                "metadata": {},
                "source": [
                    f"# Isolyn session {session['id']}\n",
                    f"Run `{plan_data['run_id']}` shards {session['shard_start']}.."
                    f"{session['shard_end'] - 1} on CPU only.\n",
                ],
            },
            {
                "cell_type": "code",
                "execution_count": None,
                "metadata": {},
                "outputs": [],
                "source": source.splitlines(keepends=True),
            },
        ],
        "metadata": {
            "kernelspec": {"display_name": "Python 3", "language": "python", "name": "python3"},
            "language_info": {"name": "python"},
        },
        "nbformat": 4,
        "nbformat_minor": 5,
    }


def _snapshot_code(source_root: Path, destination: Path) -> list[dict]:
    if destination.exists():
        raise SystemExit(f"refusing to overwrite snapshot: {destination}")
    files = _allowlisted_files(source_root)
    temporary = destination.with_name(destination.name + ".tmp-" + uuid.uuid4().hex)
    try:
        for relative, source in files:
            target = temporary / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
        manifest = []
        for relative, source in files:
            data = (temporary / relative).read_bytes()
            manifest.append({"path": relative, "bytes": len(data), "sha256": _sha256_bytes(data)})
        _atomic_json(temporary / "snapshot.json", {
            "schema": 1,
            "source_commit": None,
            "code_sha256": _code_digest(manifest),
            "files": manifest,
        })
        os.replace(temporary, destination)
        return manifest
    except BaseException:
        shutil.rmtree(temporary, ignore_errors=True)
        raise


def _write_prepared(ws: Workspace, plan_data: dict) -> Path:
    run_dir = ws.run_dir(plan_data["run_id"])
    dataset = run_dir / "dataset"
    kernels = run_dir / "kernels"
    if dataset.exists() or kernels.exists():
        raise SystemExit(f"{run_dir}: already prepared; refusing to overwrite generated artifacts")
    try:
        manifest = _snapshot_code(ws.root, dataset)
        _require(_code_digest(manifest) == plan_data["code_sha256"],
                 "snapshot code digest differs from the plan")
        # The snapshot function wrote a placeholder commit; replace it with the
        # exact plan value so a downloaded dataset cannot silently change code.
        snapshot_path = dataset / "snapshot.json"
        _atomic_json(snapshot_path, {
            "schema": 1,
            "source_commit": plan_data["source_commit"],
            "code_sha256": plan_data["code_sha256"],
            "files": manifest,
        })
        _atomic_json(dataset / "dataset-metadata.json", _dataset_metadata(plan_data))
        for session in plan_data["sessions"]:
            start, end = session["shard_start"], session["shard_end"]
            spec = {
                "schema": SESSION_SCHEMA,
                "run_id": plan_data["run_id"],
                "session_id": session["id"],
                "source_commit": plan_data["source_commit"],
                "code_sha256": plan_data["code_sha256"],
                "dataset_ref": plan_data["dataset_ref"],
                "config": plan_data["config"],
                "parallel": plan_data["parallel"],
                "max_seconds": plan_data["max_seconds"],
                "shards": plan_data["shards"][start:end],
            }
            _atomic_json(dataset / "session_specs" / f"{session['id']}.json", spec)
            kernel_dir = kernels / session["id"]
            _atomic_json(kernel_dir / "notebook.ipynb", _notebook(plan_data, session))
            _atomic_json(kernel_dir / "kernel-metadata.json", _kernel_metadata(plan_data, session))
        return dataset
    except BaseException:
        shutil.rmtree(dataset, ignore_errors=True)
        shutil.rmtree(kernels, ignore_errors=True)
        raise


def prepare(ws: Workspace, run_id: str) -> int:
    path = ws.plan_path(run_id)
    _require(path.is_file(), f"no cloud plan for {run_id}; run `lab cloud plan` first")
    plan_data = json.loads(path.read_text(encoding="utf-8"))
    _require(plan_data.get("schema") == PLAN_SCHEMA, "unsupported cloud plan schema")
    _require(ws.head_fn() == plan_data["source_commit"],
             "current Git commit differs from the plan; create a new plan")
    _require(ws.clean_fn(), "source tree is dirty; commit or stash before preparing")
    current = _code_manifest(ws.root)
    _require(_code_digest(current) == plan_data["code_sha256"],
             "allowlisted source changed since the plan; create a new plan")
    try:
        dataset = _write_prepared(ws, plan_data)
    except SystemExit:
        raise
    except OSError as exc:
        raise SystemExit(f"could not prepare {run_id}: {exc}") from exc
    print(f"{run_id}: prepared {dataset}")
    print(f"  dataset files: {sum(1 for _ in dataset.rglob('*') if _.is_file())}")
    print(f"  sessions: {len(plan_data['sessions'])}")
    print("  next: commit/push, then `lab cloud push <run> --session 0000 --yes`")
    return 0


def _load_plan(ws: Workspace, run_id: str) -> dict:
    path = ws.plan_path(run_id)
    _require(path.is_file(), f"no cloud plan for {run_id}; run `lab cloud plan` first")
    value = json.loads(path.read_text(encoding="utf-8"))
    _require(value.get("schema") == PLAN_SCHEMA, "unsupported cloud plan schema")
    return value


def _load_ledger(ws: Workspace, run_id: str) -> dict:
    path = ws.ledger_path(run_id)
    if not path.exists():
        return {"schema": LEDGER_SCHEMA, "sessions": {}}
    value = json.loads(path.read_text(encoding="utf-8"))
    _require(value.get("schema") == LEDGER_SCHEMA, "unsupported cloud ledger schema")
    value.setdefault("sessions", {})
    return value


def _save_ledger(ws: Workspace, run_id: str, ledger: dict) -> None:
    _atomic_json(ws.ledger_path(run_id), ledger)


def _session(plan_data: dict, session_id: str) -> dict:
    for session in plan_data["sessions"]:
        if session["id"] == session_id:
            return session
    raise SystemExit(f"{plan_data['run_id']}: unknown session {session_id!r}")


def _kernel_id(plan_data: dict, session: dict) -> str:
    owner = plan_data["dataset_ref"].split("/", 1)[0]
    return f"{owner}/{plan_data['kernel_prefix']}-{session['id']}"


def _dataset_dir(ws: Workspace, run_id: str) -> Path:
    return ws.run_dir(run_id) / "dataset"


def _kernel_dir(ws: Workspace, run_id: str, session: dict) -> Path:
    return ws.run_dir(run_id) / "kernels" / session["id"]


def _verify_upload_layout(dataset: Path, kernel: Path, plan_data: dict) -> None:
    """Reject files a human or stray process added after preparation."""
    snapshot = json.loads((dataset / "snapshot.json").read_text(encoding="utf-8"))
    declared = {entry["path"] for entry in snapshot.get("files", [])}
    allowed_dataset = declared | {"snapshot.json", "dataset-metadata.json"}
    allowed_dataset |= {
        f"session_specs/{session['id']}.json" for session in plan_data["sessions"]
    }
    for path in dataset.rglob("*"):
        _require(not path.is_symlink(), f"refusing symlink in upload: {path}")
        if path.is_file():
            relative = path.relative_to(dataset).as_posix()
            _require(relative in allowed_dataset,
                     f"refusing unexpected dataset file: {relative}")
    allowed_kernel = {"notebook.ipynb", "kernel-metadata.json"}
    for path in kernel.rglob("*"):
        _require(not path.is_symlink(), f"refusing symlink in upload: {path}")
        if path.is_file():
            relative = path.relative_to(kernel).as_posix()
            _require(relative in allowed_kernel,
                     f"refusing unexpected kernel file: {relative}")


def push(
    ws: Workspace,
    run_id: str,
    session_id: str | None,
    dataset_mode: str,
    confirmed: bool,
) -> int:
    plan_data = _load_plan(ws, run_id)
    ledger = _load_ledger(ws, run_id)
    if session_id is None:
        for session in plan_data["sessions"]:
            if not ledger["sessions"].get(session["id"], {}).get("pushed_at"):
                session_id = session["id"]
                break
        _require(session_id is not None, "every session has already been pushed")
    session = _session(plan_data, session_id)
    dataset = _dataset_dir(ws, run_id)
    kernel = _kernel_dir(ws, run_id, session)
    _require((dataset / "dataset-metadata.json").is_file(),
             "dataset is not prepared; run `lab cloud prepare` first")
    _require((kernel / "kernel-metadata.json").is_file(),
             "kernel directory is not prepared")
    _verify_upload_layout(dataset, kernel, plan_data)
    try:
        cloud_verify.verify_code_snapshot(
            dataset, plan_data["source_commit"], plan_data["code_sha256"]
        )
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        raise SystemExit(f"prepared dataset failed code verification: {exc}") from exc
    dataset_metadata = json.loads((dataset / "dataset-metadata.json").read_text(encoding="utf-8"))
    _require(dataset_metadata.get("id") == plan_data["dataset_ref"],
             "prepared dataset metadata does not match the plan")
    kernel_metadata = json.loads((kernel / "kernel-metadata.json").read_text(encoding="utf-8"))
    _require(kernel_metadata.get("id") == _kernel_id(plan_data, session),
             "prepared kernel metadata has the wrong id")
    _require(kernel_metadata.get("dataset_sources") == [plan_data["dataset_ref"]],
             "prepared kernel metadata has the wrong dataset source")
    _require(kernel_metadata.get("is_private") is True, "refusing a non-private notebook")
    _require(kernel_metadata.get("enable_gpu") is False,
             "refusing a GPU notebook for CPU-only work")
    _require(kernel_metadata.get("enable_internet") is False,
             "refusing a notebook with internet enabled")

    if dataset_mode == "auto":
        dataset_mode = (
            "version"
            if any(entry.get("dataset_uploaded_at") or entry.get("pushed_at")
                   for entry in ledger["sessions"].values())
            else "create"
        )
    _require(dataset_mode in ("create", "version"), "dataset mode must be auto, create, or version")
    dataset_command = (
        ["datasets", "create", "-p", str(dataset), "-r", "tar", "-q"]
        if dataset_mode == "create"
        else ["datasets", "version", "-p", str(dataset), "-m",
              f"code {plan_data['source_commit'][:12]} / {plan_data['run_id']}", "-r", "tar", "-q"]
    )
    kernel_command = ["kernels", "push", "-p", str(kernel)]
    _require(ledger["sessions"].get(session_id, {}).get("pushed_at") is None,
             f"session {session_id} is already recorded as pushed; refusing a silent re-run")
    if not confirmed:
        print("cloud push is an external action; pass --yes to confirm")
        print("  kaggle " + " ".join(dataset_command))
        print("  kaggle " + " ".join(kernel_command))
        return 2

    print("uploading private code dataset…")
    print("  kaggle " + " ".join(dataset_command))
    ws.kaggle_fn(dataset_command)
    # Record the dataset before the kernel push. If the kernel fails, the next
    # automatic push must create a new dataset version, not try to create the
    # same private dataset again.
    ledger["sessions"][session_id] = {
        "kernel_id": _kernel_id(plan_data, session),
        "dataset_mode": dataset_mode,
        "dataset_uploaded_at": _now(),
    }
    _save_ledger(ws, run_id, ledger)
    print("pushing CPU-only private notebook…")
    print("  kaggle " + " ".join(kernel_command))
    ws.kaggle_fn(kernel_command)

    ledger["sessions"][session_id]["pushed_at"] = _now()
    _save_ledger(ws, run_id, ledger)
    print(f"{run_id}/{session_id}: pushed; wait for Kaggle to finish before fetching")
    return 0


def status(ws: Workspace, run_id: str, session_id: str) -> int:
    plan_data = _load_plan(ws, run_id)
    session = _session(plan_data, session_id)
    print(ws.kaggle_fn(["kernels", "status", _kernel_id(plan_data, session)]))
    return 0


def _copy_declared_artifacts(receipt: dict, source: Path, destination: Path) -> None:
    """Copy only the files the receipt declares, never an arbitrary tree."""
    destination.mkdir(parents=True, exist_ok=False)
    shutil.copy2(source / "session.json", destination / "session.json")
    for shard in receipt.get("shards", []):
        for key, pattern in (("csv", cloud_verify.SHARD_NAME), ("log", cloud_verify.LOG_NAME)):
            name = shard.get(key)
            if name is None:
                continue
            name = cloud_verify.safe_relative_name(name, pattern)
            shutil.copy2(source / name, destination / name)


def fetch(ws: Workspace, run_id: str, session_id: str) -> int:
    plan_data = _load_plan(ws, run_id)
    session = _session(plan_data, session_id)
    ledger = _load_ledger(ws, run_id)
    entry = ledger["sessions"].get(session_id)
    _require(entry is not None and entry.get("pushed_at"),
             f"session {session_id} has not been pushed by this driver")
    _require(entry.get("kernel_id") == _kernel_id(plan_data, session),
             f"ledger kernel id for session {session_id} does not match the plan")
    target = ws.run_dir(run_id) / "sessions" / session_id
    _require(not target.exists(), f"refusing to overwrite fetched session {target}")
    target.parent.mkdir(parents=True, exist_ok=True)
    incoming = target.parent / f".{session_id}.fetching-{uuid.uuid4().hex}"
    staged = target.parent / f".{session_id}.staged-{uuid.uuid4().hex}"
    incoming.mkdir()
    try:
        ws.kaggle_fn(["kernels", "output", entry["kernel_id"], "-p", str(incoming)])
        receipts = [p for p in incoming.rglob("session.json") if p.is_file() and not p.is_symlink()]
        _require(len(receipts) == 1,
                 f"Kaggle output must contain exactly one session.json; found {len(receipts)}")
        receipt_dir = receipts[0].parent
        receipt = json.loads(receipts[0].read_text(encoding="utf-8"))
        cloud_verify.validate_session(receipt, receipt_dir, plan_data, session)
        _copy_declared_artifacts(receipt, receipt_dir, staged)
        cloud_verify.validate_session(receipt, staged, plan_data, session)
        os.replace(staged, target)
    except BaseException:
        shutil.rmtree(incoming, ignore_errors=True)
        shutil.rmtree(staged, ignore_errors=True)
        raise
    shutil.rmtree(incoming, ignore_errors=True)
    ledger["sessions"][session_id]["fetched_at"] = _now()
    ledger["sessions"][session_id]["verified_at"] = _now()
    _save_ledger(ws, run_id, ledger)
    print(f"{run_id}/{session_id}: fetched and verified "
          f"({receipt['total_games']} games, {receipt['total_rows']} rows)")
    return 0


def verify(ws: Workspace, run_id: str, session_id: str | None) -> int:
    plan_data = _load_plan(ws, run_id)
    ledger = _load_ledger(ws, run_id)
    sessions = [session for session in plan_data["sessions"]
                if session_id is None or session["id"] == session_id]
    _require(sessions, f"unknown session {session_id!r}")
    failed = 0
    for session in sessions:
        target = ws.run_dir(run_id) / "sessions" / session["id"]
        if not (target / "session.json").is_file():
            print(f"{session['id']}: not fetched", file=sys.stderr)
            failed += 1
            continue
        receipt = json.loads((target / "session.json").read_text(encoding="utf-8"))
        try:
            cloud_verify.validate_session(receipt, target, plan_data, session)
        except (OSError, ValueError) as exc:
            print(f"{session['id']}: REJECTED: {exc}", file=sys.stderr)
            failed += 1
            continue
        ledger["sessions"].setdefault(session["id"], {})["verified_at"] = _now()
        print(f"{session['id']}: verified ({receipt['total_games']} games, {receipt['total_rows']} rows)")
    if ledger["sessions"]:
        _save_ledger(ws, run_id, ledger)
    return 1 if failed else 0


def _merge_shard(source: Path, destination, offset: int, seed: int) -> int:
    rows = 0
    with source.open("r", newline="", encoding="utf-8") as handle:
        header = handle.readline()
        if not header.startswith("game,seed,mode,"):
            raise SystemExit(f"{source}: unexpected header")
        for line in handle:
            if not line.endswith("\n"):
                raise SystemExit(f"{source}: row does not end with a newline")
            first = line.find(",")
            second = line.find(",", first + 1)
            if first < 0 or second < 0:
                raise SystemExit(f"{source}: row has no game,seed prefix")
            try:
                game = int(line[:first])
            except ValueError:
                raise SystemExit(f"{source}: invalid game id") from None
            destination.write(f"{offset + game},{seed},{line[second + 1:]}")
            rows += 1
    return rows


def assemble(ws: Workspace, run_id: str, output: Path | None) -> int:
    plan_data = _load_plan(ws, run_id)
    ledger = _load_ledger(ws, run_id)
    missing = [session["id"] for session in plan_data["sessions"]
               if not ledger["sessions"].get(session["id"], {}).get("verified_at")]
    _require(not missing, f"refusing to assemble unverified sessions: {', '.join(missing)}")
    output = output or (ws.run_dir(run_id) / "assembled.csv")
    _require(not output.exists(), f"refusing to overwrite existing output: {output}")
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_name(output.name + ".tmp-" + uuid.uuid4().hex)

    verified_by_shard: dict[int, dict] = {}
    for session in plan_data["sessions"]:
        target = ws.run_dir(run_id) / "sessions" / session["id"]
        receipt = json.loads((target / "session.json").read_text(encoding="utf-8"))
        for shard in cloud_verify.validate_session(receipt, target, plan_data, session):
            index = int(shard["index"])
            _require(index not in verified_by_shard, f"shard {index} appears twice")
            verified_by_shard[index] = shard
    _require(sorted(verified_by_shard) == list(range(len(plan_data["shards"]))),
             "verified shards do not cover the plan exactly")

    rows = 0
    try:
        with temporary.open("w", newline="", encoding="utf-8") as destination:
            header = None
            offset = 0
            for shard in plan_data["shards"]:
                verified = verified_by_shard[shard["index"]]
                path = Path(verified["path"])
                with path.open("r", newline="", encoding="utf-8") as source:
                    current = source.readline()
                    if header is None:
                        header = current
                        destination.write(current)
                    elif current != header:
                        raise SystemExit(f"{path}: header differs from the first shard")
                written = _merge_shard(path, destination, offset, shard["seed"])
                if written != int(verified["rows"]):
                    raise SystemExit(f"{path}: row count changed after verification")
                rows += written
                offset += shard["games"]
        os.replace(temporary, output)
    except BaseException:
        temporary.unlink(missing_ok=True)
        raise

    summary = {
        "schema": 1,
        "run_id": run_id,
        "source_commit": plan_data["source_commit"],
        "code_sha256": plan_data["code_sha256"],
        "input": str(output),
        "games": sum(int(shard["games"]) for shard in plan_data["shards"]),
        "rows": rows,
        "bytes": output.stat().st_size,
        "sha256": _sha256_file(output),
        "sessions": [session["id"] for session in plan_data["sessions"]],
    }
    _atomic_json(output.with_name(output.name + ".json"), summary)
    print(f"wrote {output} ({summary['games']} games, {rows} move rows)")
    return 0


def doctor(ws: Workspace) -> int:
    problems = 0
    print("Isolyn cloud doctor")
    try:
        head = ws.head_fn()
        clean = ws.clean_fn()
        print(f"  PASS  git              {head[:12]} {'clean' if clean else 'DIRTY'}")
        problems += 0 if clean else 1
    except (OSError, subprocess.SubprocessError) as exc:
        print(f"  FAIL  git              {exc}")
        problems += 1
    if shutil.which("kaggle"):
        print("  PASS  kaggle CLI       found")
    else:
        print("  WARN  kaggle CLI       not found; only offline plan/verify commands work")
    try:
        ws.data_root.mkdir(parents=True, exist_ok=True)
        print(f"  PASS  cloud store      {ws.data_root}")
    except OSError as exc:
        print(f"  FAIL  cloud store      {exc}")
        problems += 1
    print(f"RESULT: {'FAIL' if problems else 'PASS'} — {problems} problem(s)")
    return 1 if problems else 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="lab cloud",
        description="Plan, prepare, fetch and verify private Kaggle self-play sessions.",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    plan_parser = sub.add_parser("plan", help="create a gap-free session plan")
    plan_parser.add_argument("--games", type=int, default=10_000)
    plan_parser.add_argument("--games-per-shard", type=int, default=2_500)
    plan_parser.add_argument("--session-games", type=int, default=200_000)
    plan_parser.add_argument("--parallel", type=int, default=4)
    plan_parser.add_argument("--workers", type=int, default=1)
    plan_parser.add_argument("--mode", default="1v1", choices=("1v1", "1v1v1", "2v2"))
    plan_parser.add_argument("--depth", type=int, default=8)
    plan_parser.add_argument("--determinizations", type=int, default=64)
    plan_parser.add_argument("--opponent-depth", type=int)
    plan_parser.add_argument("--opponent-determinizations", type=int)
    plan_parser.add_argument("--time-ms", type=int, default=0)
    plan_parser.add_argument("--voluntary-draw", type=int, default=0)
    plan_parser.add_argument("--opponent-voluntary-draw", type=int, default=0)
    plan_parser.add_argument("--seed", type=int, default=1)
    plan_parser.add_argument("--max-seconds", type=int, default=42_000)
    plan_parser.add_argument("--run-id")
    plan_parser.add_argument("--owner", help="Kaggle owner; defaults to KAGGLE_USERNAME")
    plan_parser.add_argument("--dataset", default="isolyn-code")
    plan_parser.add_argument("--kernel", default="isolyn-lab")
    plan_parser.add_argument("--dry-run", action="store_true", help="print without writing")

    for name in ("prepare", "status", "fetch", "verify"):
        command = sub.add_parser(name)
        command.add_argument("run_id")
        if name != "prepare":
            command.add_argument("--session", help="session id; default is all/next")
    push_parser = sub.add_parser("push")
    push_parser.add_argument("run_id")
    push_parser.add_argument("--session", help="session id; default is next unpushed")
    push_parser.add_argument("--dataset-mode", default="auto", choices=("auto", "create", "version"))
    push_parser.add_argument("--yes", action="store_true", help="confirm the external upload")
    assemble_parser = sub.add_parser("assemble")
    assemble_parser.add_argument("run_id")
    assemble_parser.add_argument("--output", type=Path)
    sub.add_parser("doctor")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    ws = Workspace()
    if args.command == "plan":
        plan(ws, args)
        return 0
    if args.command == "prepare":
        return prepare(ws, args.run_id)
    if args.command == "push":
        return push(ws, args.run_id, args.session, args.dataset_mode, args.yes)
    if args.command == "status":
        session = args.session or _load_plan(ws, args.run_id)["sessions"][0]["id"]
        return status(ws, args.run_id, session)
    if args.command == "fetch":
        _require(bool(args.session), "--session is required")
        return fetch(ws, args.run_id, args.session)
    if args.command == "verify":
        return verify(ws, args.run_id, args.session)
    if args.command == "assemble":
        return assemble(ws, args.run_id, args.output)
    return doctor(ws)


if __name__ == "__main__":
    raise SystemExit(main())
