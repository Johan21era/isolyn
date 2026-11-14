from __future__ import annotations

import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from isolyn_lab import cloud_verify

ROOT = Path(__file__).resolve().parents[2]


FAKE_BUILD = r"""#!/bin/bash
set -euo pipefail
mkdir -p "$ISOLYN_SELFPLAY_OUT"
cat > "$ISOLYN_SELFPLAY_OUT/selfplay" <<'PY'
#!/usr/bin/env python3
import sys
args = sys.argv[1:]
if "--check" in args:
    print("selfplay: fake check ok")
    raise SystemExit(0)
def value(name, default=None):
    if name in args:
        return args[args.index(name) + 1]
    return default
games = int(value("--games", "1"))
seed = value("--seed", "1")
output = value("--output")
with open(output, "w", encoding="utf-8", newline="") as handle:
    handle.write("game,seed,mode,value\n")
    for game in range(games):
        handle.write(f"{game},{seed},1v1,row-{game}\n")
PY
chmod +x "$ISOLYN_SELFPLAY_OUT/selfplay"
"""


FAILING_BUILD = FAKE_BUILD.replace(
    '        handle.write(f"{game},{seed},1v1,row-{game}\\n")\nPY',
    '        handle.write(f"{game},{seed},1v1,row-{game}\\n")\nraise SystemExit(7)\nPY',
)


def _make_root(root: Path, build_script: str = FAKE_BUILD) -> str:
    (root / "cloud").mkdir(parents=True)
    shutil.copy2(ROOT / "cloud" / "run_session.py", root / "cloud" / "run_session.py")
    verifier = root / "lab" / "src" / "isolyn_lab"
    verifier.mkdir(parents=True)
    shutil.copy2(ROOT / "lab" / "src" / "isolyn_lab" / "cloud_verify.py", verifier / "cloud_verify.py")
    (verifier / "__init__.py").write_text("", encoding="utf-8")
    harness = root / "tools" / "selfplay"
    harness.mkdir(parents=True)
    (harness / "build.sh").write_text(build_script, encoding="utf-8")
    (harness / "build.sh").chmod(0o755)
    (harness / "main.cpp").write_text("// fake harness\n", encoding="utf-8")
    (harness / "README.md").write_text("fake\n", encoding="utf-8")
    files = []
    for relative in ("cloud/run_session.py", "lab/src/isolyn_lab/__init__.py",
                     "lab/src/isolyn_lab/cloud_verify.py",
                     "tools/selfplay/build.sh", "tools/selfplay/main.cpp",
                     "tools/selfplay/README.md"):
        path = root / relative
        files.append({"path": relative, "bytes": path.stat().st_size,
                      "sha256": cloud_verify.sha256_file(path)})
    digest = cloud_verify.code_digest(files)
    (root / "snapshot.json").write_text(json.dumps({
        "schema": 1, "source_commit": "a" * 40, "code_sha256": digest, "files": files,
    }), encoding="utf-8")
    return digest


def _spec(code_digest: str = "b" * 64) -> dict:
    config = {
        "mode": "1v1",
        "depth": 2,
        "determinizations": 2,
        "workers": 1,
        "seed": 5,
        "opponent_depth": 2,
        "opponent_determinizations": 2,
        "opponent_workers": 1,
        "time_ms": 0,
        "voluntary_draw": 0,
        "opponent_voluntary_draw": 0,
    }
    return {
        "schema": 1,
        "run_id": "worker-test",
        "session_id": "0000",
        "source_commit": "a" * 40,
        "code_sha256": code_digest,
        "dataset_ref": "tester/isolyn-code",
        "config": config,
        "parallel": 2,
        "max_seconds": 120,
        "shards": [
            {"index": 0, "seed": 5, "games": 2},
            {"index": 1, "seed": 6, "games": 2},
        ],
    }


class WorkerTests(unittest.TestCase):
    def _run(self, root: Path, spec: dict, output: Path) -> subprocess.CompletedProcess:
        spec_path = root / "session.json"
        spec_path.write_text(json.dumps(spec), encoding="utf-8")
        return subprocess.run(
            [sys.executable, str(root / "cloud" / "run_session.py"),
             "--root", str(root), "--session", str(spec_path), "--output", str(output)],
            capture_output=True,
            text=True,
            timeout=60,
        )

    def test_worker_builds_runs_and_writes_a_verifiable_receipt(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "code"
            digest = _make_root(root)
            spec = _spec(digest)
            output = Path(tmp) / "out"
            result = self._run(root, spec, output)
            self.assertEqual(result.returncode, 0, result.stderr)
            receipt = json.loads((output / "session.json").read_text(encoding="utf-8"))
            self.assertEqual(receipt["status"], "complete")
            self.assertEqual(receipt["total_games"], 4)
            self.assertEqual(receipt["total_rows"], 4)
            plan = {
                "run_id": spec["run_id"],
                "source_commit": spec["source_commit"],
                "code_sha256": spec["code_sha256"],
                "dataset_ref": spec["dataset_ref"],
                "config": spec["config"],
                "shards": spec["shards"],
            }
            session = {"id": "0000", "shard_start": 0, "shard_end": 2}
            verified = cloud_verify.validate_session(receipt, output, plan, session)
            self.assertEqual([item["index"] for item in verified], [0, 1])

    def test_worker_writes_a_failed_receipt_and_returns_nonzero(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "code"
            digest = _make_root(root, FAILING_BUILD)
            spec = _spec(digest)
            output = Path(tmp) / "out"
            result = self._run(root, spec, output)
            self.assertNotEqual(result.returncode, 0)
            receipt = json.loads((output / "session.json").read_text(encoding="utf-8"))
            self.assertEqual(receipt["status"], "failed")
            self.assertNotEqual(receipt["error"], None)

    def test_worker_refuses_a_spec_without_a_real_code_digest(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "code"
            digest = _make_root(root)
            spec = _spec(digest)
            spec["code_sha256"] = "not-a-digest"
            output = Path(tmp) / "out"
            result = self._run(root, spec, output)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("invalid code_sha256", result.stderr)
            self.assertFalse((output / "session.json").exists())

    def test_worker_refuses_a_tampered_code_snapshot(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "code"
            digest = _make_root(root)
            (root / "tools/selfplay/main.cpp").write_text("// altered\n", encoding="utf-8")
            output = Path(tmp) / "out"
            result = self._run(root, _spec(digest), output)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("code snapshot failed verification", result.stderr)
            self.assertFalse((output / "session.json").exists())


if __name__ == "__main__":
    unittest.main()
