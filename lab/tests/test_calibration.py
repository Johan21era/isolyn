from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from isolyn_lab import calibration, dataset


HEADER = (
    "game,seed,mode,outcome,deciding_player,participant_count,"
    "initial_hand0,initial_hand1,initial_hand2,initial_hand3,"
    "final_hand0,final_hand1,final_hand2,final_hand3,"
    "participant_score0,participant_score1,participant_score2,participant_score3\n"
)


class CalibrationTests(unittest.TestCase):
    def test_load_folds_move_rows_and_analyze_counts_wins(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "selfplay.csv"
            path.write_text(
                HEADER
                + "0,7,1v1,domino,0,2,10,20,0,0,0,20,0,0,0,10,0,0\n"
                + "0,7,1v1,domino,0,2,10,20,0,0,0,20,0,0,0,10,0,0\n"
                + "1,7,1v1,closed,1,2,15,5,0,0,15,0,0,0,8,0,0,0\n",
                encoding="utf-8",
            )

            games = dataset.load_games(path)
            self.assertEqual(len(games), 2)
            self.assertEqual(games[0].decisions, 2)
            self.assertEqual(games[0].initial_hands, (10, 20, 0, 0))

            report = calibration.analyze(games)
            self.assertEqual(report.games, 2)
            self.assertEqual(report.decisions, 3)
            self.assertEqual(report.outcomes, {"closed": 1, "domino": 1})
            by_participant = {p.participant: p for p in report.participants}
            self.assertEqual(by_participant[0].wins, 1)
            self.assertEqual(by_participant[1].wins, 1)
            self.assertEqual(by_participant[0].average_initial_pips, 12.5)

    def test_spearman_handles_ties_and_no_variance(self) -> None:
        self.assertIsNone(calibration.spearman([1, 1, 1], [2, 3, 4]))
        self.assertAlmostEqual(calibration.spearman([1, 2, 3], [3, 2, 1]), -1.0)

    def test_elo_and_wilson_interval(self) -> None:
        self.assertAlmostEqual(calibration.elo_from_score(0.75), 190.8486, places=3)
        self.assertIsNone(calibration.elo_from_score(0.0))
        low, high = calibration.wilson_interval(75, 100)
        self.assertLess(low, 0.75)
        self.assertGreater(high, 0.75)
        elo_low, elo_high = calibration.elo_interval(75, 100)
        self.assertLess(elo_low, 190.85)
        self.assertGreater(elo_high, 190.85)

    def test_head_to_head_fields_are_grouped_by_search_side(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "h2h.csv"
            header = (
                "game,seed,mode,config_a_depth,config_a_determinizations,"
                "config_b_depth,config_b_determinizations,"
                "participant_side0,participant_side1,participant_side2,participant_side3,"
                "outcome,deciding_player,participant_count,"
                "initial_hand0,initial_hand1,initial_hand2,initial_hand3,"
                "final_hand0,final_hand1,final_hand2,final_hand3,"
                "participant_score0,participant_score1,participant_score2,participant_score3\n"
            )
            path.write_text(
                header
                + "0,1,1v1,2,2,4,8,0,1,0,0,domino,0,2,10,20,0,0,0,20,0,0,0,10,0,0\n"
                + "1,1,1v1,2,2,4,8,1,0,0,0,domino,0,2,15,5,0,0,15,0,0,0,8,0,0,0\n",
                encoding="utf-8",
            )

            report = calibration.analyze(dataset.load_games(path))
            self.assertEqual([(s.participant, s.wins) for s in report.sides], [(0, 1), (1, 1)])
            self.assertEqual(report.config_a, (2, 2))
            self.assertEqual(report.config_b, (4, 8))


if __name__ == "__main__":
    unittest.main()