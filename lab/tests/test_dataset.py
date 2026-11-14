from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from isolyn_lab import dataset


HEADER = (
    "game,seed,mode,outcome,deciding_player,participant_count,"
    "initial_hand0,initial_hand1,initial_hand2,initial_hand3,"
    "final_hand0,final_hand1,final_hand2,final_hand3,"
    "participant_score0,participant_score1,participant_score2,participant_score3\n"
)


class DatasetTests(unittest.TestCase):
    def test_fold_counts_every_row_once(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "selfplay.csv"
            path.write_text(
                HEADER
                + "0,7,1v1,domino,0,2,10,20,0,0,0,20,0,0,0,10,0,0\n"
                + "0,7,1v1,domino,0,2,10,20,0,0,0,20,0,0,0,10,0,0\n"
                + "0,7,1v1,domino,0,2,10,20,0,0,0,20,0,0,0,10,0,0\n"
                + "1,8,1v1,closed,1,2,15,5,0,0,15,0,0,0,8,0,0,0\n",
                encoding="utf-8",
            )

            games = dataset.load_games(path)
            self.assertEqual([game.game for game in games], [0, 1])
            self.assertEqual([game.decisions for game in games], [3, 1])
            self.assertEqual(games[0].initial_hands, (10, 20, 0, 0))
            self.assertEqual(games[1].seed, 8)

    def test_iter_games_does_not_require_a_list(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "selfplay.csv"
            path.write_text(
                HEADER
                + "4,7,1v1,domino,0,2,10,20,0,0,0,20,0,0,0,10,0,0\n"
                + "5,7,1v1,domino,0,2,10,20,0,0,0,20,0,0,0,10,0,0\n",
                encoding="utf-8",
            )

            games = dataset.iter_games(path)
            first = next(games)
            self.assertEqual(first.game, 4)
            self.assertEqual(first.decisions, 1)
            self.assertEqual(next(games).game, 5)

    def test_out_of_order_games_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "selfplay.csv"
            path.write_text(
                HEADER
                + "0,7,1v1,domino,0,2,10,20,0,0,0,20,0,0,0,10,0,0\n"
                + "1,7,1v1,domino,0,2,10,20,0,0,0,20,0,0,0,10,0,0\n"
                + "0,7,1v1,domino,0,2,10,20,0,0,0,20,0,0,0,10,0,0\n",
                encoding="utf-8",
            )
            with self.assertRaisesRegex(ValueError, "grouped by increasing game id"):
                dataset.load_games(path)

    def test_header_order_is_read_not_assumed(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "reordered.csv"
            path.write_text(
                "seed,mode,game,outcome,deciding_player,participant_count,"
                "initial_hand0,initial_hand1,initial_hand2,initial_hand3,"
                "final_hand0,final_hand1,final_hand2,final_hand3,"
                "participant_score0,participant_score1,participant_score2,participant_score3\n"
                "9,1v1v1,2,closed,1,3,1,2,3,0,9,8,7,0,4,5,6,0\n",
                encoding="utf-8",
            )
            game = dataset.load_games(path)[0]
            self.assertEqual((game.game, game.seed, game.mode), (2, 9, "1v1v1"))
            self.assertEqual(game.initial_hands, (1, 2, 3, 0))
            self.assertEqual(game.participant_scores, (4, 5, 6, 0))

    def test_empty_csv_is_rejected_but_header_only_is_empty(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            empty = Path(tmp) / "empty.csv"
            empty.write_text("", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "empty CSV"):
                dataset.load_games(empty)

            header_only = Path(tmp) / "header.csv"
            header_only.write_text(HEADER, encoding="utf-8")
            self.assertEqual(dataset.load_games(header_only), [])


if __name__ == "__main__":
    unittest.main()
