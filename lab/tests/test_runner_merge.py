from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from isolyn_lab import runner


HEADER = (
    "game,seed,mode,outcome,deciding_player,participant_count,"
    "initial_hand0,initial_hand1,initial_hand2,initial_hand3,"
    "final_hand0,final_hand1,final_hand2,final_hand3,"
    "participant_score0,participant_score1,participant_score2,participant_score3\n"
)
ROW = "{game},{seed},1v1,domino,0,2,10,20,0,0,0,20,0,0,0,10,0,0\n"


class MergeTests(unittest.TestCase):
    def _run(self, tmp: str, shards: list[tuple[int, int, int]]) -> tuple[Path, str]:
        """Build a manifest with (index, seed, games) shards, each with 2 rows/game."""
        root = Path(tmp)
        run_dir = root / "merge-test"
        shard_dir = run_dir / "shards"
        shard_dir.mkdir(parents=True)
        entries = []
        for index, seed, games in shards:
            csv_name = f"shard-{index:04d}.csv"
            lines = [HEADER]
            for game in range(games):
                lines.append(ROW.format(game=game, seed=seed))
                lines.append(ROW.format(game=game, seed=seed))
            (shard_dir / csv_name).write_text("".join(lines), encoding="utf-8")
            entries.append(
                {
                    "index": index,
                    "seed": seed,
                    "games": games,
                    "status": "done",
                    "csv": csv_name,
                }
            )
        manifest = {"run_id": "merge-test", "shards": entries}
        (run_dir / "manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
        return run_dir, "merge-test"

    def test_merge_renumbers_games_and_keeps_shard_seeds(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            run_dir, run_id = self._run(tmp, [(0, 10, 2), (1, 11, 2)])
            output = run_dir / "merged.csv"
            with mock.patch.object(runner, "RUNS", Path(tmp)):
                self.assertEqual(runner._merge(run_id, output), 0)

            lines = output.read_text(encoding="utf-8").splitlines()
            self.assertEqual(lines[0] + "\n", HEADER)
            rows = [line.split(",") for line in lines[1:]]
            self.assertEqual([int(row[0]) for row in rows], [0, 0, 1, 1, 2, 2, 3, 3])
            self.assertEqual([int(row[1]) for row in rows], [10, 10, 10, 10, 11, 11, 11, 11])
            self.assertFalse(output.with_name("merged.csv.tmp").exists())

    def test_merge_falls_back_for_a_reordered_schema(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            run_dir, run_id = self._run(tmp, [(0, 10, 1)])
            shard = run_dir / "shards" / "shard-0000.csv"
            header = "seed,game,mode,outcome,deciding_player,participant_count," \
                "initial_hand0,initial_hand1,initial_hand2,initial_hand3," \
                "final_hand0,final_hand1,final_hand2,final_hand3," \
                "participant_score0,participant_score1,participant_score2,participant_score3\n"
            shard.write_text(
                header + "0,0,1v1,domino,0,2,10,20,0,0,0,20,0,0,0,10,0,0\n",
                encoding="utf-8",
            )
            output = run_dir / "merged.csv"
            with mock.patch.object(runner, "RUNS", Path(tmp)):
                self.assertEqual(runner._merge(run_id, output), 0)

            lines = output.read_text(encoding="utf-8").splitlines()
            self.assertEqual(lines[0].split(",")[:2], ["seed", "game"])
            self.assertEqual(lines[1].split(",")[:2], ["10", "0"])


if __name__ == "__main__":
    unittest.main()
