from __future__ import annotations

import contextlib
import hashlib
import io
import json
import tempfile
import unittest
from pathlib import Path

from isolyn_lab import report


HEADER = (
    "game,seed,mode,outcome,deciding_player,participant_count,"
    "initial_hand0,initial_hand1,initial_hand2,initial_hand3,"
    "final_hand0,final_hand1,final_hand2,final_hand3,"
    "participant_score0,participant_score1,participant_score2,participant_score3\n"
)
# Two rows per hand: the raw format has one row per decision, repeated with the
# final summary.  The second hand is deliberately a closed hand whose closer
# lost, so the report cannot just copy deciding_player into "winner".
ROWS = {
    0: (
        "0,7,1v1,domino,0,2,10,20,0,0,0,20,0,0,20,0,0,0\n"
        "0,7,1v1,domino,0,2,10,20,0,0,0,20,0,0,20,0,0,0\n"
    ),
    1: (
        "1,7,1v1,closed,1,2,10,10,0,0,10,5,0,0,5,0,0,0\n"
        "1,7,1v1,closed,1,2,10,10,0,0,10,5,0,0,5,0,0,0\n"
    ),
    2: (
        "2,7,1v1,closed,0,2,10,10,0,0,10,5,0,0,5,0,0,0\n"
        "2,7,1v1,closed,0,2,10,10,0,0,10,5,0,0,5,0,0,0\n"
    ),
    3: (
        "3,7,1v1,domino,1,2,10,20,0,0,10,0,0,0,0,10,0,0\n"
        "3,7,1v1,domino,1,2,10,20,0,0,10,0,0,0,0,10,0,0\n"
    ),
    4: (
        "4,7,1v1,domino,1,2,10,20,0,0,10,0,0,0,0,10,0,0\n"
        "4,7,1v1,domino,1,2,10,20,0,0,10,0,0,0,0,10,0,0\n"
    ),
}


def _manifest(run_id: str, shards: list[dict] | None = None) -> dict:
    return {
        "version": 1,
        "run_id": run_id,
        "created_at": "2026-11-14T10:25:37+00:00",
        "updated_at": "2026-11-14T10:25:37+00:00",
        "config": {
            "games": 5,
            "mode": "1v1",
            "depth": 2,
            "determinizations": 2,
            "workers": 1,
            "seed": 7,
            "shards": 1,
            "games_per_shard": 5,
            "opponent_depth": 2,
            "opponent_determinizations": 2,
            "opponent_workers": None,
            "time_ms": None,
            "voluntary_draw": None,
            "opponent_voluntary_draw": None,
        },
        "shards": shards
        or [
            {
                "index": 0,
                "seed": 7,
                "games": 5,
                "status": "done",
                "rows": 10,
                "csv": "shard-0000.csv",
                "log": "shard-0000.log",
                "reason": None,
            }
        ],
    }


def _make_run(root: Path, run_id: str = "smoke") -> Path:
    run_dir = root / run_id
    shard_dir = run_dir / "shards"
    shard_dir.mkdir(parents=True)
    (shard_dir / "shard-0000.csv").write_text(
        HEADER + "".join(ROWS[index] for index in sorted(ROWS)),
        encoding="utf-8",
    )
    (shard_dir / "shard-0000.log").write_text("completed rounds: 5\nincomplete rounds: 0\n", encoding="utf-8")
    (run_dir / "manifest.json").write_text(json.dumps(_manifest(run_id)), encoding="utf-8")
    return run_dir


class ReportTests(unittest.TestCase):
    def test_smoke_run_gets_plain_language_and_warnings(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            run_dir = _make_run(Path(tmp))
            raw = run_dir / "shards" / "shard-0000.csv"
            before = hashlib.sha256(raw.read_bytes()).hexdigest()

            paths = report.generate(run_dir)

            readme = paths["readme"].read_text(encoding="utf-8")
            summary = json.loads(paths["summary"].read_text(encoding="utf-8"))
            self.assertIn("SMOKE TEST", readme)
            self.assertIn("not evidence about playing strength", readme)
            self.assertIn("Only 5 hands", readme)
            self.assertIn("depth 2", readme)
            self.assertIn("What is good", readme)
            self.assertIn("What needs attention", readme)
            self.assertIn("What to do next", readme)
            self.assertIn("Words used here", readme)
            self.assertIn("Both sides used the same settings", readme)
            self.assertNotIn("Two search settings were compared", readme)
            self.assertEqual(summary["counts"]["games_observed"], 5)
            self.assertEqual(summary["counts"]["incomplete"], 0)
            self.assertTrue(any(check["level"] == "warn" for check in summary["checks"]))
            self.assertTrue(any(check["level"] == "pass" for check in summary["checks"]))
            self.assertIsNotNone(paths["games_csv"])
            after = hashlib.sha256(raw.read_bytes()).hexdigest()
            self.assertEqual(before, after, "the report must not modify the raw CSV")

    def test_closed_hand_winner_is_not_the_closer(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            run_dir = _make_run(Path(tmp))
            paths = report.generate(run_dir)
            lines = paths["games_csv"].read_text(encoding="utf-8").splitlines()
            header = lines[0].split(",")
            game_one = lines[2].split(",")
            row = dict(zip(header, game_one))
            self.assertEqual(row["hand"], "1")
            self.assertEqual(row["outcome"], "closed")
            self.assertEqual(row["deciding_player"], "Player 2")
            self.assertEqual(row["winner"], "Player 1")
            self.assertIn("Player 1 won on points", row["what_happened"])

    def test_incomplete_run_is_not_presented_as_finished(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            run_dir = root / "partial"
            shard_dir = run_dir / "shards"
            shard_dir.mkdir(parents=True)
            (shard_dir / "shard-0000.csv").write_text(
                HEADER + ROWS[0] + ROWS[1],
                encoding="utf-8",
            )
            manifest = _manifest(
                "partial",
                [
                    {
                        "index": 0,
                        "seed": 7,
                        "games": 2,
                        "status": "done",
                        "rows": 4,
                        "csv": "shard-0000.csv",
                        "log": "shard-0000.log",
                        "reason": None,
                    },
                    {
                        "index": 1,
                        "seed": 8,
                        "games": 3,
                        "status": "pending",
                        "rows": 0,
                        "csv": "shard-0001.csv",
                        "log": "shard-0001.log",
                        "reason": "interrupted",
                    },
                ],
            )
            manifest["config"]["games"] = 5
            manifest["config"]["shards"] = 2
            (run_dir / "manifest.json").write_text(json.dumps(manifest), encoding="utf-8")

            readme = report.generate(run_dir)["readme"].read_text(encoding="utf-8")
            self.assertIn("NOT READY", readme)
            self.assertIn("The run is not finished", readme)
            self.assertIn("2 of 2", readme)  # batches done of total
            self.assertNotIn("Every batch finished", readme)

    def test_report_command_writes_and_returns_zero(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            run_dir = _make_run(Path(tmp))
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                code = report.main([run_dir.name, "--runs-dir", str(run_dir.parent)])
            self.assertEqual(code, 0)
            self.assertIn("wrote", output.getvalue())
            self.assertTrue((run_dir / "README.md").is_file())
            self.assertTrue((run_dir / "summary.json").is_file())


if __name__ == "__main__":
    unittest.main()
