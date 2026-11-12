"""Read the C++ self-play CSV without inventing a second game engine.

The C++ harness owns moves, legality and scoring. This module only folds its
per-move rows into one record per game for offline analysis.
"""

from __future__ import annotations

import csv
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class GameRecord:
    game: int
    seed: int
    mode: str
    outcome: str
    deciding_player: int
    participant_count: int
    initial_hands: tuple[int, ...]
    final_hands: tuple[int, ...]
    participant_scores: tuple[int, ...]
    decisions: int
    participant_sides: tuple[int, ...] = ()
    config_a: tuple[int, int] = (0, 0)
    config_b: tuple[int, int] = (0, 0)


def _int(row: dict[str, str], name: str) -> int:
    try:
        return int(row[name])
    except KeyError as exc:
        raise ValueError(f"self-play CSV is missing {name!r}") from exc
    except ValueError as exc:
        raise ValueError(f"self-play CSV has a non-integer {name!r}: {row[name]!r}") from exc


def _fixed_ints(row: dict[str, str], prefix: str, count: int = 4) -> tuple[int, ...]:
    return tuple(_int(row, f"{prefix}{i}") for i in range(count))


def _optional_int(row: dict[str, str], name: str, default: int = 0) -> int:
    value = row.get(name)
    if value is None or value == "":
        return default
    try:
        return int(value)
    except ValueError as exc:
        raise ValueError(f"self-play CSV has a non-integer {name!r}: {value!r}") from exc


def load_games(path: str | Path) -> list[GameRecord]:
    """Return one GameRecord per game, preserving file order.

    A game is represented by its first move row; every row repeats the same
    final summary, so taking the first is deterministic. Empty games cannot
    exercise a real move and are rejected rather than fabricated.
    """
    path = Path(path)
    with path.open(newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        if reader.fieldnames is None:
            raise ValueError(f"{path}: empty CSV")
        rows = list(reader)

    if not rows:
        return []

    seen: dict[int, GameRecord] = {}
    for row in rows:
        game = _int(row, "game")
        if game in seen:
            continue
        seen[game] = GameRecord(
            game=game,
            seed=_int(row, "seed"),
            mode=row["mode"],
            outcome=row["outcome"],
            deciding_player=_int(row, "deciding_player"),
            participant_count=_int(row, "participant_count"),
            initial_hands=_fixed_ints(row, "initial_hand"),
            final_hands=_fixed_ints(row, "final_hand"),
            participant_scores=_fixed_ints(row, "participant_score"),
            decisions=sum(1 for r in rows if _int(r, "game") == game),
            participant_sides=tuple(_optional_int(row, f"participant_side{i}") for i in range(4)),
            config_a=(
                _optional_int(row, "config_a_depth"),
                _optional_int(row, "config_a_determinizations"),
            ),
            config_b=(
                _optional_int(row, "config_b_depth"),
                _optional_int(row, "config_b_determinizations"),
            ),
        )
    return list(seen.values())


def participant_for_player(mode: str, player: int) -> int:
    """2v2 partners are 0/2 and 1/3; other modes are one participant/player."""
    if mode == "2v2":
        return player % 2
    return player


def initial_value_for_participant(game: GameRecord, participant: int) -> int:
    if game.mode == "2v2":
        return game.initial_hands[participant] + game.initial_hands[participant + 2]
    return game.initial_hands[participant]