from __future__ import annotations

import hashlib
import json
import shutil
import tempfile
import unittest
from pathlib import Path

from isolyn_lab import cloud, cloud_verify


def _write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def _make_workspace(root: Path) -> cloud.Workspace:
    # Minimal allowlisted source tree. The app and lab data are deliberately
    # absent so a snapshot test can prove they cannot be uploaded by accident.
    _write(root / "Sources/IsolynEngine/Engine.cpp", "// engine\n")
    _write(root / "Sources/IsolynEngine/include/Engine.hpp", "// header\n")
    _write(root / "tools/selfplay/main.cpp", "// harness\n")
    _write(root / "tools/selfplay/build.sh", "#!/bin/bash\n")
    _write(root / "tools/selfplay/README.md", "harness\n")
    _write(root / "lab/pyproject.toml", "[project]\nname='isolyn-lab'\n")
    _write(root / "lab/src/isolyn_lab/__init__.py", "")
    _write(root / "lab/src/isolyn_lab/cloud_verify.py", "// verifier\n")
    _write(root / "cloud/run_session.py", "// worker\n")
    _write(root / "Sources/IsolynApp/Secret.swift", "should not upload\n")
    _write(root / "lab/data/private.csv", "should not upload\n")
    return cloud.Workspace(
        root=root,
        data_root=root / "cloud-data",
        head_fn=lambda: "a" * 40,
        clean_fn=lambda: True,
    )


def _args(*extra: str):
    return cloud.build_parser().parse_args(
        ["plan", "--owner", "tester", "--games", "10000", "--games-per-shard", "2500",
         "--run-id", "plan-test", *extra]
    )


def _csv(games: int, seed: int) -> str:
    lines = ["game,seed,mode,value\n"]
    for game in range(games):
        lines.append(f"{game},{seed},1v1,row-{game}\n")
    return "".join(lines)


class PlanTests(unittest.TestCase):
    def test_plan_covers_every_game_once_with_contiguous_sessions(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            ws = _make_workspace(Path(tmp))
            args = _args("--session-games", "5000")
            result = cloud.plan(ws, args)
            self.assertEqual(sum(shard["games"] for shard in result["shards"]), 10000)
            indexes = [shard["index"] for shard in result["shards"]]
            self.assertEqual(indexes, list(range(len(indexes))))
            covered = []
            for session in result["sessions"]:
                self.assertLess(session["shard_start"], session["shard_end"])
                covered.extend(range(session["shard_start"], session["shard_end"]))
            self.assertEqual(covered, indexes)
            self.assertEqual(len(set(covered)), len(covered))
            self.assertEqual(sum(session["games"] for session in result["sessions"]), 10000)

    def test_dry_run_writes_no_plan(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            ws = _make_workspace(Path(tmp))
            cloud.plan(ws, _args("--dry-run"))
            self.assertFalse((ws.data_root / "plan-test" / "plan.json").exists())

    def test_dirty_tree_is_refused(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            ws = _make_workspace(root)
            ws.clean_fn = lambda: False
            with self.assertRaises(SystemExit):
                cloud.plan(ws, _args())


class PrepareTests(unittest.TestCase):
    def test_prepare_writes_private_cpu_only_metadata_and_an_exact_snapshot(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            ws = _make_workspace(root)
            cloud.plan(ws, _args("--games", "5000", "--games-per-shard", "2500"))
            self.assertEqual(cloud.prepare(ws, "plan-test"), 0)

            run = ws.data_root / "plan-test"
            dataset = run / "dataset"
            kernel = run / "kernels" / "0000"
            metadata = json.loads((dataset / "dataset-metadata.json").read_text(encoding="utf-8"))
            kernel_metadata = json.loads((kernel / "kernel-metadata.json").read_text(encoding="utf-8"))
            snapshot = json.loads((dataset / "snapshot.json").read_text(encoding="utf-8"))

            self.assertTrue(metadata["id"].endswith("/isolyn-code"))
            self.assertEqual(snapshot["source_commit"], "a" * 40)
            self.assertTrue(kernel_metadata["is_private"])
            self.assertFalse(kernel_metadata["enable_gpu"])
            self.assertFalse(kernel_metadata["enable_internet"])
            self.assertNotIn("Sources/IsolynApp/Secret.swift",
                             [entry["path"] for entry in snapshot["files"]])
            self.assertNotIn("lab/data/private.csv",
                             [entry["path"] for entry in snapshot["files"]])
            self.assertTrue((dataset / "cloud" / "run_session.py").is_file())
            self.assertTrue((dataset / "session_specs" / "0000.json").is_file())
            self.assertTrue((kernel / "notebook.ipynb").is_file())

    def test_prepare_refuses_a_second_time(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            ws = _make_workspace(Path(tmp))
            cloud.plan(ws, _args("--games", "5000", "--games-per-shard", "2500"))
            cloud.prepare(ws, "plan-test")
            with self.assertRaises(SystemExit):
                cloud.prepare(ws, "plan-test")

    def test_prepare_refuses_code_drift_and_leaves_no_partial_dataset(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            ws = _make_workspace(root)
            cloud.plan(ws, _args("--games", "5000", "--games-per-shard", "2500"))
            _write(root / "tools/selfplay/main.cpp", "// changed after plan\n")
            with self.assertRaises(SystemExit):
                cloud.prepare(ws, "plan-test")
            self.assertFalse((ws.run_dir("plan-test") / "dataset").exists())
            self.assertFalse((ws.run_dir("plan-test") / "kernels").exists())


class ReceiptTests(unittest.TestCase):
    def _fixture(self, root: Path):
        ws = _make_workspace(root)
        cloud.plan(ws, _args("--games", "4", "--games-per-shard", "2", "--session-games", "4"))
        plan_data = json.loads(ws.plan_path("plan-test").read_text(encoding="utf-8"))
        session = plan_data["sessions"][0]
        target = ws.run_dir("plan-test") / "sessions" / session["id"]
        target.mkdir(parents=True)
        shards = []
        total_rows = 0
        for want in plan_data["shards"][session["shard_start"]:session["shard_end"]]:
            csv_name = f"shard-{want['index']:04d}.csv"
            csv_path = target / csv_name
            csv_path.write_text(_csv(want["games"], want["seed"]), encoding="utf-8")
            log_name = f"shard-{want['index']:04d}.log"
            log_path = target / log_name
            log_path.write_text("ok\n", encoding="utf-8")
            rows = want["games"]
            total_rows += rows
            shards.append({
                "index": want["index"],
                "seed": want["seed"],
                "games": want["games"],
                "csv": csv_name,
                "rows": rows,
                "bytes": csv_path.stat().st_size,
                "sha256": cloud_verify.sha256_file(csv_path),
                "log": log_name,
                "log_bytes": log_path.stat().st_size,
                "log_sha256": cloud_verify.sha256_file(log_path),
                "exit_code": 0,
            })
        receipt = {
            "schema": 1,
            "run_id": "plan-test",
            "session_id": session["id"],
            "source_commit": plan_data["source_commit"],
            "code_sha256": plan_data["code_sha256"],
            "dataset_ref": plan_data["dataset_ref"],
            "config": plan_data["config"],
            "status": "complete",
            "shards": shards,
            "total_games": sum(item["games"] for item in shards),
            "total_rows": total_rows,
        }
        (target / "session.json").write_text(json.dumps(receipt), encoding="utf-8")
        return ws, plan_data, session, receipt, target

    def test_valid_receipt_passes_and_a_bad_hash_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            ws, plan_data, session, receipt, target = self._fixture(Path(tmp))
            verified = cloud_verify.validate_session(receipt, target, plan_data, session)
            self.assertEqual(len(verified), 2)

            receipt["shards"][0]["sha256"] = "0" * 64
            with self.assertRaises(ValueError):
                cloud_verify.validate_session(receipt, target, plan_data, session)

            receipt["shards"][0]["sha256"] = cloud_verify.sha256_file(target / "shard-0000.csv")
            receipt["shards"][0]["exit_code"] = 7
            with self.assertRaises(ValueError):
                cloud_verify.validate_session(receipt, target, plan_data, session)

            receipt["shards"][0]["exit_code"] = 0
            receipt["total_rows"] += 1
            with self.assertRaises(ValueError):
                cloud_verify.validate_session(receipt, target, plan_data, session)

            with self.assertRaises(ValueError):
                cloud_verify.safe_relative_name("../shard-0000.csv", cloud_verify.SHARD_NAME)

            wrong_seed = target / "wrong-seed.csv"
            wrong_seed.write_text(_csv(1, 99), encoding="utf-8")
            with self.assertRaises(ValueError):
                cloud_verify.inspect_csv(wrong_seed, 1, 1, "1v1")

    def test_assembly_rewrites_game_ids_and_seeds(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            ws, plan_data, session, receipt, target = self._fixture(Path(tmp))
            ledger = {"schema": 1, "sessions": {
                session["id"]: {"verified_at": "now", "pushed_at": "now", "kernel_id": "tester/isolyn-lab-0000"}
            }}
            (ws.run_dir("plan-test") / "ledger.json").write_text(json.dumps(ledger), encoding="utf-8")
            output = ws.run_dir("plan-test") / "assembled.csv"
            self.assertEqual(cloud.assemble(ws, "plan-test", output), 0)
            lines = output.read_text(encoding="utf-8").splitlines()
            self.assertEqual(lines[0], "game,seed,mode,value")
            self.assertEqual([line.split(",")[0] for line in lines[1:]], ["0", "1", "2", "3"])
            self.assertEqual([line.split(",")[1] for line in lines[1:]], ["1", "1", "2", "2"])
            summary = json.loads((output.with_name(output.name + ".json")).read_text(encoding="utf-8"))
            self.assertEqual(summary["games"], 4)
            self.assertEqual(summary["rows"], 4)

    def test_assembly_refuses_a_missing_verified_session(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            ws, plan_data, session, receipt, target = self._fixture(Path(tmp))
            with self.assertRaises(SystemExit):
                cloud.assemble(ws, "plan-test", ws.run_dir("plan-test") / "assembled.csv")

    def test_fetch_requires_a_pushed_session_and_never_overwrites(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            ws, plan_data, session, receipt, target = self._fixture(Path(tmp))
            with self.assertRaises(SystemExit):
                cloud.fetch(ws, "plan-test", session["id"])

            ledger = {"schema": 1, "sessions": {
                session["id"]: {"pushed_at": "now", "kernel_id": "tester/isolyn-lab-0000"}
            }}
            (ws.run_dir("plan-test") / "ledger.json").write_text(json.dumps(ledger), encoding="utf-8")
            with self.assertRaises(SystemExit):
                cloud.fetch(ws, "plan-test", session["id"])


class FetchTests(unittest.TestCase):
    def test_fetch_validates_then_moves_the_session_into_place(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            ws, plan_data, session, receipt, target = ReceiptTests()._fixture(Path(tmp))
            source = Path(tmp) / "remote"
            shutil.copytree(target, source)
            shutil.rmtree(target)
            ledger = {"schema": 1, "sessions": {
                session["id"]: {"pushed_at": "now", "kernel_id": "tester/isolyn-lab-0000"}
            }}
            (ws.run_dir("plan-test") / "ledger.json").write_text(json.dumps(ledger), encoding="utf-8")

            def kaggle(args):
                self.assertEqual(args[:2], ["kernels", "output"])
                incoming = Path(args[args.index("-p") + 1])
                for item in source.iterdir():
                    shutil.copy2(item, incoming / item.name)
                return "ok"

            ws.kaggle_fn = kaggle
            self.assertEqual(cloud.fetch(ws, "plan-test", session["id"]), 0)
            self.assertTrue((target / "session.json").is_file())
            updated = json.loads((ws.run_dir("plan-test") / "ledger.json").read_text(encoding="utf-8"))
            self.assertIn("fetched_at", updated["sessions"][session["id"]])
            self.assertIn("verified_at", updated["sessions"][session["id"]])


class PushTests(unittest.TestCase):
    def test_push_dry_run_does_not_call_kaggle(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            ws = _make_workspace(Path(tmp))
            cloud.plan(ws, _args("--games", "5000", "--games-per-shard", "2500"))
            cloud.prepare(ws, "plan-test")
            calls = []
            ws.kaggle_fn = calls.append
            self.assertEqual(cloud.push(ws, "plan-test", "0000", "auto", False), 2)
            self.assertEqual(calls, [])

    def test_push_uploads_private_artifacts_and_records_the_session(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            ws = _make_workspace(Path(tmp))
            cloud.plan(ws, _args("--games", "5000", "--games-per-shard", "2500"))
            cloud.prepare(ws, "plan-test")
            calls = []
            ws.kaggle_fn = lambda args: calls.append(args) or "ok"
            self.assertEqual(cloud.push(ws, "plan-test", "0000", "auto", True), 0)
            self.assertEqual(len(calls), 2)
            self.assertIn("datasets", calls[0])
            self.assertIn("create", calls[0])
            self.assertIn("kernels", calls[1])
            ledger = json.loads((ws.run_dir("plan-test") / "ledger.json").read_text(encoding="utf-8"))
            self.assertIn("0000", ledger["sessions"])
            self.assertIn("pushed_at", ledger["sessions"]["0000"])

    def test_push_refuses_an_unexpected_file_in_the_upload_directories(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            ws = _make_workspace(Path(tmp))
            cloud.plan(ws, _args("--games", "5000", "--games-per-shard", "2500"))
            cloud.prepare(ws, "plan-test")
            (ws.run_dir("plan-test") / "dataset" / "extra.txt").write_text("secret\n", encoding="utf-8")
            calls = []
            ws.kaggle_fn = lambda args: calls.append(args) or "ok"
            with self.assertRaises(SystemExit):
                cloud.push(ws, "plan-test", "0000", "auto", True)
            self.assertEqual(calls, [])

    def test_a_failed_kernel_push_is_recorded_and_retried_as_a_dataset_version(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            ws = _make_workspace(Path(tmp))
            cloud.plan(ws, _args("--games", "5000", "--games-per-shard", "2500"))
            cloud.prepare(ws, "plan-test")
            calls = []

            def kaggle(args):
                calls.append(args)
                if args[:2] == ["kernels", "push"]:
                    raise SystemExit("simulated kernel failure")
                return "ok"

            ws.kaggle_fn = kaggle
            with self.assertRaises(SystemExit):
                cloud.push(ws, "plan-test", "0000", "auto", True)
            ledger = json.loads((ws.run_dir("plan-test") / "ledger.json").read_text(encoding="utf-8"))
            entry = ledger["sessions"]["0000"]
            self.assertIn("dataset_uploaded_at", entry)
            self.assertNotIn("pushed_at", entry)

            calls.clear()
            ws.kaggle_fn = lambda args: calls.append(args) or "ok"
            self.assertEqual(cloud.push(ws, "plan-test", "0000", "auto", True), 0)
            self.assertEqual(calls[0][:2], ["datasets", "version"])
            self.assertEqual(calls[1][:2], ["kernels", "push"])


if __name__ == "__main__":
    unittest.main()
