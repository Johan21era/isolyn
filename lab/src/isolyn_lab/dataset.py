"""Read the C++ self-play CSV without inventing a second game engine.

The C++ harness owns moves, legality and scoring. This module only folds its
per-move rows into one record per game for offline analysis.

The harness writes every row of a game contiguously, so the fold is a single
pass and needs memory for one game at a time. A file whose game ids go backwards
is rejected instead of being silently mis-folded: that is not an output shape
the harness or the shard merger produces.
"""

from __future__ import annotations

import csv
from collections.abc import Iterator
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


_REQUIRED = (
    "game",
    "seed",
    "mode",
    "outcome",
    "deciding_player",
    "participant_count",
    "initial_hand0",
    "initial_hand1",
    "initial_hand2",
    "initial_hand3",
    "final_hand0",
    "final_hand1",
    "final_hand2",
    "final_hand3",
    "participant_score0",
    "participant_score1",
    "participant_score2",
    "participant_score3",
)


def _field(row: list[str], index: dict[str, int], name: str, path: Path) -> str:
    try:
        return row[index[name]]
    except IndexError as exc:
        raise ValueError(f"{path}: row has {len(row)} columns, missing {name!r}") from exc


def _int(row: list[str], index: dict[str, int], name: str, path: Path) -> int:
    value = _field(row, index, name, path)
    try:
        return int(value)
    except ValueError as exc:
        raise ValueError(f"{path}: non-integer {name!r}: {value!r}") from exc


def _optional_int(row: list[str], index: dict[str, int], name: str, path: Path, default: int = 0) -> int:
    column = index.get(name)
    if column is None or column >= len(row) or row[column] == "":
        return default
    try:
        return int(row[column])
    except ValueError as exc:
        raise ValueError(f"{path}: non-integer {name!r}: {row[column]!r}") from exc


def _fixed_ints(row: list[str], prefix: str, index: dict[str, int], path: Path) -> tuple[int, ...]:
    return tuple(_int(row, index, f"{prefix}{i}", path) for i in range(4))


def _record(row: list[str], decisions: int, index: dict[str, int], path: Path) -> GameRecord:
    return GameRecord(
        game=_int(row, index, "game", path),
        seed=_int(row, index, "seed", path),
        mode=_field(row, index, "mode", path),
        outcome=_field(row, index, "outcome", path),
        deciding_player=_int(row, index, "deciding_player", path),
        participant_count=_int(row, index, "participant_count", path),
        initial_hands=_fixed_ints(row, "initial_hand", index, path),
        final_hands=_fixed_ints(row, "final_hand", index, path),
        participant_scores=_fixed_ints(row, "participant_score", index, path),
        decisions=decisions,
        participant_sides=tuple(
            _optional_int(row, index, f"participant_side{i}", path) for i in range(4)
        ),
        config_a=(
            _optional_int(row, index, "config_a_depth", path),
            _optional_int(row, index, "config_a_determinizations", path),
        ),
        config_b=(
            _optional_int(row, index, "config_b_depth", path),
            _optional_int(row, index, "config_b_determinizations", path),
        ),
    )


def _columns(header: list[str], path: Path) -> dict[str, int]:
    index = {name: position for position, name in enumerate(header)}
    missing = [name for name in _REQUIRED if name not in index]
    if missing:
        raise ValueError(f"{path}: self-play CSV is missing {', '.join(missing)}")
    return index


def iter_games(path: str | Path) -> Iterator[GameRecord]:
    """Yield one GameRecord per game, in file order, in one pass.

    A game is represented by its first move row; every row repeats the same
    final summary, so taking the first is deterministic. Empty games cannot
    exercise a real move and are rejected rather than fabricated.
    """
    path = Path(path)
    with path.open(newline="", encoding="utf-8") as handle:
        reader = csv.reader(handle)
        try:
            header = next(reader)
        except StopIteration:
            raise ValueError(f"{path}: empty CSV") from None
        if not header:
            raise ValueError(f"{path}: empty CSV header")
        index = _columns(header, path)

        current_game: int | None = None
        current_row: list[str] | None = None
        decisions = 0
        for row in reader:
            if not row:
                continue
            game = _int(row, index, "game", path)
            if current_game is None:
                current_game = game
                current_row = row
                decisions = 1
                continue
            if game == current_game:
                decisions += 1
                continue
            if game < current_game:
                raise ValueError(
                    f"{path}: game {game} appears after game {current_game}; "
                    "rows must be grouped by increasing game id"
                )
            assert current_row is not None
            yield _record(current_row, decisions, index, path)
            current_game = game
            current_row = row
            decisions = 1

        if current_row is not None:
            yield _record(current_row, decisions, index, path)


def load_games(path: str | Path) -> list[GameRecord]:
    """Return one GameRecord per game, preserving file order."""
    return list(iter_games(path))


def participant_for_player(mode: str, player: int) -> int:
    """2v2 partners are 0/2 and 1/3; other modes are one participant/player."""
    if mode == "2v2":
        return player % 2
    return player


def initial_value_for_participant(game: GameRecord, participant: int) -> int:
    if game.mode == "2v2":
        return game.initial_hands[participant] + game.initial_hands[participant + 2]
    return game.initial_hands[participant]
