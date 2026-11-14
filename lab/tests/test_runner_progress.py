from __future__ import annotations

import contextlib
import io
import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from isolyn_lab import runner


class ProgressTests(unittest.TestCase):
    def test_last_progress_reads_the_final_flushed_line(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "shard.log"
            path.write_text(
                "IsolynV2.0 self-play\n"
                "  finished 10/5000 rounds (100 decisions)\n"
                "  finished 420/5000 rounds (4200 decisions)\n",
                encoding="utf-8",
            )
            self.assertEqual(runner._last_progress(path, 5000), 420)
            self.assertEqual(runner._last_progress(path, 100), 100, "never exceed the shard size")

    def test_refresh_keeps_only_running_shards_live(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            shard_dir = Path(tmp)
            (shard_dir / "a.log").write_text("  finished 7/10 rounds (1 decisions)\n", encoding="utf-8")
            (shard_dir / "b.log").write_text("  finished 9/10 rounds (1 decisions)\n", encoding="utf-8")
            manifest = {
                "shards": [
                    {"index": 0, "status": "running", "games": 10, "progress": 0, "log": "a.log"},
                    {"index": 1, "status": "done", "games": 10, "progress": 10, "log": "b.log"},
                ]
            }
            self.assertTrue(runner._refresh_running_progress(manifest, shard_dir))
            self.assertEqual(manifest["shards"][0]["progress"], 7)
            self.assertEqual(manifest["shards"][1]["progress"], 10)
            self.assertFalse(runner._refresh_running_progress(manifest, shard_dir))

    def test_progress_counts_partial_games_and_reports_rate(self) -> None:
        manifest = {
            "started_at": runner._now(),
            "shards": [
                {"index": 0, "status": "done", "games": 5000, "progress": 5000},
                {"index": 1, "status": "running", "games": 5000, "progress": 2500},
            ],
        }
        line = runner._progress(manifest, 10_000)
        self.assertIn("1/2 shards", line)
        self.assertIn("7500/10000 games (75.0%)", line)


class RunArgumentTests(unittest.TestCase):
    def _args(self, *extra: str):
        return runner.build_parser().parse_args(["run", *extra])

    def test_rejects_zero_games_before_creating_a_run(self) -> None:
        with self.assertRaises(SystemExit):
            runner._validate_run_args(self._args("--games", "0"))

    def test_resolves_shards_from_games(self) -> None:
        count, per_shard = runner._resolve_shards(self._args("--games", "10001"))
        self.assertEqual(count, 3)
        self.assertEqual(per_shard, 3334)
        self.assertEqual(count * per_shard, 10002)

    def test_dry_run_prints_a_plan_and_creates_nothing(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            with mock.patch.object(runner, "RUNS", Path(tmp)):
                output = io.StringIO()
                with contextlib.redirect_stdout(output):
                    code = runner.main(
                        ["run", "--games", "100", "--depth", "2", "--determinizations", "2",
                         "--dry-run", "--run-id", "plan-only"]
                    )
            self.assertEqual(code, 0)
            self.assertIn("plan only", output.getvalue())
            self.assertIn("shards: 1 x 100 games", output.getvalue())
            self.assertFalse((Path(tmp) / "plan-only").exists())

    def test_stop_removes_a_stale_lock_without_signaling_anyone(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            run_dir = Path(tmp) / "stale-run"
            run_dir.mkdir()
            (run_dir / "run.lock").write_text("999999999", encoding="utf-8")
            with mock.patch.object(runner, "RUNS", Path(tmp)):
                code = runner._stop("stale-run")
            self.assertEqual(code, 0)
            self.assertFalse((run_dir / "run.lock").exists())

    def test_clean_removes_only_selected_probe_and_stale_lock_paths(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            probe = root / "probe-test"
            probe.mkdir()
            (probe / "data.csv").write_text("x", encoding="utf-8")
            keep = root / "keep-me"
            keep.mkdir()
            stale = root / "stale-run"
            stale.mkdir()
            (stale / "run.lock").write_text("999999999", encoding="utf-8")
            with mock.patch.object(runner, "RUNS", root):
                self.assertEqual(runner._clean(True, True, True), 0)
            self.assertFalse(probe.exists())
            self.assertFalse((stale / "run.lock").exists(), "dead locks are removed")
            self.assertTrue(keep.exists(), "real runs are never deleted")
            self.assertTrue(stale.exists(), "the run directory itself is kept")


if __name__ == "__main__":
    unittest.main()
