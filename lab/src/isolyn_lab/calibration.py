"""Aggregate self-play games into a small, honest calibration report.

This is intentionally analysis-only. It never chooses a move, validates a
move, or scores a round; those facts come from the C++ CSV.
"""

from __future__ import annotations

import math
from collections import Counter
from collections.abc import Iterable
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


def _weighted_ranks(counts: Counter[int]) -> dict[int, float]:
    """Average ranks for tied values from occurrence counts."""
    ranks: dict[int, float] = {}
    before = 0
    for value in sorted(counts):
        count = counts[value]
        ranks[value] = before + (count + 1) / 2.0
        before += count
    return ranks


def _spearman_counts(pairs: Counter[tuple[int, int]]) -> float | None:
    """Exact Spearman rho from a contingency table of (x, y) counts.

    The report only needs the rank correlation, not the original rows. Counting
    distinct pairs keeps memory bounded by the value range instead of by the
    number of games, which is what makes a multi-million-row evaluation
    possible. The rank formula is the same average-rank definition as
    `spearman`, including ties.
    """
    samples = sum(pairs.values())
    if samples < 2:
        return None
    x_counts: Counter[int] = Counter()
    y_counts: Counter[int] = Counter()
    for (x, y), count in pairs.items():
        x_counts[x] += count
        y_counts[y] += count
    ranks_x = _weighted_ranks(x_counts)
    ranks_y = _weighted_ranks(y_counts)
    mean_rank = (samples + 1) / 2.0
    numerator = 0.0
    for (x, y), count in pairs.items():
        numerator += count * (ranks_x[x] - mean_rank) * (ranks_y[y] - mean_rank)
    denom_x = sum(count * (ranks_x[x] - mean_rank) ** 2 for x, count in x_counts.items())
    denom_y = sum(count * (ranks_y[y] - mean_rank) ** 2 for y, count in y_counts.items())
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


def analyze(games: Iterable[GameRecord]) -> CalibrationReport:
    """Aggregate one pass; a generator is accepted so large files stream."""
    outcomes: Counter[str] = Counter()
    wins: Counter[int] = Counter()
    points: Counter[int] = Counter()
    initial: Counter[int] = Counter()
    participant_games: Counter[int] = Counter()
    side_games: Counter[int] = Counter()
    side_wins: Counter[int] = Counter()
    side_points: Counter[int] = Counter()
    side_initial: Counter[int] = Counter()
    points_pairs: Counter[tuple[int, int]] = Counter()
    win_pairs: Counter[tuple[int, int]] = Counter()
    game_count = 0
    decision_count = 0
    first: GameRecord | None = None

    for game in games:
        game_count += 1
        decision_count += game.decisions
        if first is None:
            first = game
        outcomes[game.outcome] += 1
        if game.outcome == "in_progress":
            continue
        winner = participant_for_player(game.mode, game.deciding_player)
        for participant in range(game.participant_count):
            initial_pips = initial_value_for_participant(game, participant)
            score = game.participant_scores[participant]
            participant_games[participant] += 1
            points[participant] += score
            initial[participant] += initial_pips
            if participant == winner:
                wins[participant] += 1

            side = game.participant_sides[participant] if participant < len(game.participant_sides) else 0
            side_games[side] += 1
            side_points[side] += score
            side_initial[side] += initial_pips
            if participant == winner:
                side_wins[side] += 1

            # Correlation is computed only for complete games; an unfinished
            # round has no legitimate outcome label to learn from. Count pairs
            # instead of retaining one tuple per participant per game.
            points_pairs[(initial_pips, score)] += 1
            win_pairs[(initial_pips, 1 if participant == winner else 0)] += 1

    elo = None
    elo_low = None
    elo_high = None
    if 0 in side_games and 1 in side_games and side_games[0] == side_games[1] > 0:
        total = side_games[0]
        elo = elo_from_score(side_wins[0] / total)
        elo_low, elo_high = elo_interval(side_wins[0], total)
    return CalibrationReport(
        games=game_count,
        decisions=decision_count,
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
        initial_vs_points=_spearman_counts(points_pairs),
        initial_vs_win=_spearman_counts(win_pairs),
        correlation_samples=sum(points_pairs.values()),
    )


def report_to_dict(report: CalibrationReport, mode: str, input_path: str | None = None) -> dict:
    """Machine-readable report, used by the app's Analyses tab.

    Floats stay unrounded here; formatting is the caller's business, and rounding
    a confidence interval before display would be a quiet loss of information.
    """

    def stats(entry: ParticipantStats, label: str) -> dict:
        low, high = wilson_interval(entry.wins, entry.games)
        return {
            "label": label,
            "games": entry.games,
            "wins": entry.wins,
            "win_rate": entry.win_rate,
            "win_low": low,
            "win_high": high,
            "average_points": entry.average_points,
            "average_initial_pips": entry.average_initial_pips,
        }

    payload = {
        "input": input_path,
        "mode": mode,
        "games": report.games,
        "decisions": report.decisions,
        "outcomes": report.outcomes,
        "config_a": {"depth": report.config_a[0], "determinizations": report.config_a[1]},
        "config_b": {"depth": report.config_b[0], "determinizations": report.config_b[1]},
        "participants": [
            stats(entry, participant_label(mode, entry.participant))
            for entry in report.participants
        ],
        "sides": [
            stats(entry, "A" if entry.participant == 0 else "B")
            for entry in report.sides
        ],
        "spearman": {
            "initial_vs_points": report.initial_vs_points,
            "initial_vs_win": report.initial_vs_win,
            "samples": report.correlation_samples,
        },
        "elo": None,
    }
    if (
        len(report.sides) == 2
        and report.sides[0].games == report.sides[1].games
        and report.sides[0].games > 0
    ):
        side_a = report.sides[0]
        payload["elo"] = {
            "a_vs_b": report.elo_a_vs_b,
            "low": report.elo_low,
            "high": report.elo_high,
            "games": side_a.games,
            "score_a": side_a.wins / side_a.games,
        }
    return payload


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