"""Aggregate self-play games into a small, honest calibration report.

This is intentionally analysis-only. It never chooses a move, validates a
move, or scores a round; those facts come from the C++ CSV.
"""

from __future__ import annotations

import math
from collections import Counter
from dataclasses import dataclass

from .dataset import GameRecord, initial_value_for_participant, participant_for_player


@dataclass(frozen=True)
class ParticipantStats:
    participant: int
    games: int
    wins: int
    points: int
    initial_pips: int

    @property
    def win_rate(self) -> float:
        return self.wins / self.games if self.games else 0.0

    @property
    def average_points(self) -> float:
        return self.points / self.games if self.games else 0.0

    @property
    def average_initial_pips(self) -> float:
        return self.initial_pips / self.games if self.games else 0.0


@dataclass(frozen=True)
class CalibrationReport:
    games: int
    decisions: int
    outcomes: dict[str, int]
    participants: tuple[ParticipantStats, ...]
    sides: tuple[ParticipantStats, ...]
    config_a: tuple[int, int]
    config_b: tuple[int, int]
    elo_a_vs_b: float | None
    elo_low: float | None
    elo_high: float | None
    initial_vs_points: float | None
    initial_vs_win: float | None
    correlation_samples: int


def _rank(values: list[float]) -> list[float]:
    """Average ranks, so ties do not bias Spearman's rho."""
    order = sorted(range(len(values)), key=lambda i: values[i])
    ranks = [0.0] * len(values)
    i = 0
    while i < len(order):
        j = i + 1
        while j < len(order) and values[order[j]] == values[order[i]]:
            j += 1
        average = (i + 1 + j) / 2.0
        for k in range(i, j):
            ranks[order[k]] = average
        i = j
    return ranks


def spearman(xs: list[float], ys: list[float]) -> float | None:
    if len(xs) != len(ys) or len(xs) < 2:
        return None
    rx = _rank(xs)
    ry = _rank(ys)
    mean_x = sum(rx) / len(rx)
    mean_y = sum(ry) / len(ry)
    numerator = sum((x - mean_x) * (y - mean_y) for x, y in zip(rx, ry))
    denom_x = sum((x - mean_x) ** 2 for x in rx)
    denom_y = sum((y - mean_y) ** 2 for y in ry)
    denominator = (denom_x * denom_y) ** 0.5
    if denominator == 0:
        return None
    return numerator / denominator


def wilson_interval(wins: int, games: int, z: float = 1.96) -> tuple[float, float]:
    """95% Wilson score interval for a binomial win rate."""
    if games <= 0:
        return (0.0, 1.0)
    p = wins / games
    denominator = 1.0 + z * z / games
    centre = (p + z * z / (2.0 * games)) / denominator
    margin = z * math.sqrt((p * (1.0 - p) + z * z / (4.0 * games)) / games) / denominator
    return (max(0.0, centre - margin), min(1.0, centre + margin))


def elo_from_score(score: float) -> float | None:
    """Elo difference corresponding to a win/score rate; None at 0 or 1."""
    if score <= 0.0 or score >= 1.0:
        return None
    return 400.0 * math.log10(score / (1.0 - score))


def elo_interval(wins: int, games: int) -> tuple[float | None, float | None]:
    low, high = wilson_interval(wins, games)
    return (elo_from_score(low), elo_from_score(high))


def participant_label(mode: str, participant: int) -> str:
    if mode == "2v2":
        return "Team A" if participant == 0 else "Team B"
    return f"Player {participant + 1}"


def analyze(games: list[GameRecord]) -> CalibrationReport:
    outcomes: Counter[str] = Counter()
    wins: Counter[int] = Counter()
    points: Counter[int] = Counter()
    initial: Counter[int] = Counter()
    participant_games: Counter[int] = Counter()
    side_games: Counter[int] = Counter()
    side_wins: Counter[int] = Counter()
    side_points: Counter[int] = Counter()
    side_initial: Counter[int] = Counter()
    xs: list[float] = []
    ys_points: list[float] = []
    ys_win: list[float] = []

    for game in games:
        outcomes[game.outcome] += 1
        if game.outcome == "in_progress":
            continue
        winner = participant_for_player(game.mode, game.deciding_player)
        for participant in range(game.participant_count):
            participant_games[participant] += 1
            points[participant] += game.participant_scores[participant]
            initial[participant] += initial_value_for_participant(game, participant)
            if participant == winner:
                wins[participant] += 1

            side = game.participant_sides[participant] if participant < len(game.participant_sides) else 0
            side_games[side] += 1
            side_points[side] += game.participant_scores[participant]
            side_initial[side] += initial_value_for_participant(game, participant)
            if participant == winner:
                side_wins[side] += 1

            # Correlation is computed only for complete games; an unfinished
            # round has no legitimate outcome label to learn from.
            xs.append(float(initial_value_for_participant(game, participant)))
            ys_points.append(float(game.participant_scores[participant]))
            ys_win.append(1.0 if participant == winner else 0.0)

    first = games[0] if games else None
    side_by_id = {
        side.participant: side
        for side in (
            ParticipantStats(
                participant=s,
                games=side_games[s],
                wins=side_wins[s],
                points=side_points[s],
                initial_pips=side_initial[s],
            )
            for s in sorted(side_games)
        )
    }
    elo = None
    elo_low = None
    elo_high = None
    if 0 in side_by_id and 1 in side_by_id:
        side_a = side_by_id[0]
        side_b = side_by_id[1]
        if side_a.games == side_b.games and side_a.games > 0:
            total = side_a.games
            elo = elo_from_score(side_a.wins / total)
            elo_low, elo_high = elo_interval(side_a.wins, total)
    return CalibrationReport(
        games=len(games),
        decisions=sum(game.decisions for game in games),
        outcomes=dict(sorted(outcomes.items())),
        participants=tuple(
            ParticipantStats(
                participant=p,
                games=participant_games[p],
                wins=wins[p],
                points=points[p],
                initial_pips=initial[p],
            )
            for p in sorted(participant_games)
        ),
        sides=tuple(
            ParticipantStats(
                participant=s,
                games=side_games[s],
                wins=side_wins[s],
                points=side_points[s],
                initial_pips=side_initial[s],
            )
            for s in sorted(side_games)
        ),
        config_a=first.config_a if first else (0, 0),
        config_b=first.config_b if first else (0, 0),
        elo_a_vs_b=elo,
        elo_low=elo_low,
        elo_high=elo_high,
        initial_vs_points=spearman(xs, ys_points),
        initial_vs_win=spearman(xs, ys_win),
        correlation_samples=len(xs),
    )


def render(report: CalibrationReport, mode: str = "unknown") -> str:
    lines = [
        "Isolyn calibration report",
        f"mode: {mode}",
        f"games: {report.games}",
        f"decisions: {report.decisions}",
        f"config A: depth={report.config_a[0]}, determinizations={report.config_a[1]}",
        f"config B: depth={report.config_b[0]}, determinizations={report.config_b[1]}",
        "outcomes: " + ", ".join(f"{k}={v}" for k, v in report.outcomes.items()),
        "",
        f"{'participant':<14} {'games':>6} {'wins':>6} {'win%':>7} {'avg pts':>8} {'avg start':>10}",
    ]
    for p in report.participants:
        label = participant_label(mode, p.participant)
        lines.append(
            f"{label:<14} {p.games:>6} {p.wins:>6} {p.win_rate * 100:>6.1f}% "
            f"{p.average_points:>8.2f} {p.average_initial_pips:>10.2f}"
        )
    if any(side.participant == 1 for side in report.sides):
        lines.extend(["", "Head-to-head by search side:",
                      f"{'side':<14} {'games':>6} {'wins':>6} {'win%':>7} {'avg pts':>8} {'avg start':>10}"])
        for side in report.sides:
            label = "A" if side.participant == 0 else "B"
            lines.append(
                f"{label:<14} {side.games:>6} {side.wins:>6} {side.win_rate * 100:>6.1f}% "
                f"{side.average_points:>8.2f} {side.average_initial_pips:>10.2f}"
            )
        side_games = [side.games for side in report.sides if side.participant in (0, 1)]
        total = side_games[0] if len(side_games) == 2 and side_games[0] == side_games[1] else 0
        if total > 0:
            elo_text = "undefined (undefeated/winless)" if report.elo_a_vs_b is None else f"{report.elo_a_vs_b:+.1f}"
            ci_text = (
                "n/a"
                if report.elo_low is None or report.elo_high is None
                else f"[{report.elo_low:+.1f}, {report.elo_high:+.1f}]"
            )
            lines.append(
                f"Elo(A vs B): {elo_text}  95% CI: {ci_text}  (n={total}, score A={sum(s.wins for s in report.sides if s.participant == 0) / total:.3f})"
            )
    lines.append("")
    lines.append(
        f"Spearman(initial pips, round points) = {report.initial_vs_points!r} "
        f"(n={report.correlation_samples})"
    )
    lines.append(
        f"Spearman(initial pips, win) = {report.initial_vs_win!r} "
        f"(n={report.correlation_samples})"
    )
    lines.append("")
    lines.append("A positive points correlation means worse starting hands tended to score more")
    lines.append("points against the opponent; a negative win correlation is the same signal.")
    return "\n".join(lines)