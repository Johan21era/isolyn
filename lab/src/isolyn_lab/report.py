"""Human-readable reports for finished and interrupted self-play runs.

The raw shard CSV is the evidence. This module never edits it. It folds the
completed shards with the same :mod:`dataset` reader used by analysis, then
writes a small, rebuildable package beside the evidence:

    README.md    the "start here" explanation for a person
    summary.json the same facts for the app or a script
    games.csv    one tidy row per hand, when the run is small enough

The report is deliberately cautious. A finished smoke batch is called a smoke
batch, not a strength result; an incomplete batch is not called finished; and
the reproduction command is derived from the recorded configuration rather than
guessed from the current checkout.
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import re
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

from . import calibration, dataset
from .dataset import GameRecord, initial_value_for_participant

ROOT = Path(__file__).resolve().parents[3]
RUNS = Path(os.environ.get("ISOLYN_RUNS_DIR") or (ROOT / "lab" / "data" / "runs"))
REPORT_SCHEMA = 1
RUN_ID_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,80}$")
# A tidy table is useful for a normal experiment. A five-million-hand corpus
# would make a second multi-gigabyte file for no analytical benefit, so the
# automatic report keeps the aggregate and lets the owner force the table.
GAMES_CSV_LIMIT = 100_000
KNOWN_OUTCOMES = {"domino", "closed", "in_progress"}


def _now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def _atomic_text(path: Path, text: str) -> None:
    temporary = path.with_name("." + path.name + ".tmp")
    temporary.write_text(text, encoding="utf-8")
    os.replace(temporary, path)


def _atomic_json(path: Path, value: dict) -> None:
    _atomic_text(path, json.dumps(value, indent=2, sort_keys=True) + "\n")


def _check(level: str, title: str, detail: str, action: str = "") -> dict:
    return {"level": level, "title": title, "detail": detail, "action": action}


def _mode_plain(mode: str) -> str:
    return {
        "1v1": "1v1 — two players",
        "1v1v1": "1v1v1 — three players, each for themselves",
        "2v2": "2v2 — two teams of two",
    }.get(mode, mode)


def _outcome_plain(outcome: str) -> str:
    return {
        "domino": "Domino win — a player emptied their hand",
        "closed": "Closed hand — no legal play remained",
        "in_progress": "Unfinished — the hand stopped before a result",
    }.get(outcome, outcome.replace("_", " "))


def _outcome_meaning(outcome: str) -> str:
    return {
        "domino": "A player played their last tile and won the hand.",
        "closed": "No legal play remained; the lower remaining hand won.",
        "in_progress": "The hand stopped before anyone won.",
    }.get(outcome, "This result label is not explained by the report.")


def _participant_count(mode: str) -> int:
    return {"1v1": 2, "1v1v1": 3, "2v2": 2}.get(mode, 2)


def _participant_label(mode: str, participant: int) -> str:
    return calibration.participant_label(mode, participant)


def _column_key(label: str) -> str:
    return label.lower().replace(" ", "_").replace("-", "_")


def _winner(game: GameRecord) -> int | None:
    """Return the unique winner, using the shared rulebook-aware helper."""
    return calibration.winner_for_game(game)


def _what_happened(game: GameRecord, winner: int | None) -> str:
    if game.outcome == "in_progress":
        return "Hand stopped before a result"
    if winner is None:
        return "No unique winner (tie or tied closing hands)"
    label = _participant_label(game.mode, winner)
    if game.outcome == "domino":
        return f"{label} emptied their hand"
    if game.outcome == "closed":
        return f"Board closed; {label} won on points"
    return f"{label} won"


def _state(manifest: dict, run_dir: Path) -> tuple[str, int, int, int]:
    shards = manifest.get("shards") or []
    done = sum(1 for shard in shards if shard.get("status") == "done")
    failed = sum(1 for shard in shards if shard.get("status") == "failed")
    pending = len(shards) - done - failed
    if failed:
        state = "failed"
    elif shards and done == len(shards):
        state = "complete"
    elif (run_dir / "run.lock").exists() or any(
        shard.get("status") == "running" for shard in shards
    ):
        state = "running"
    else:
        state = "incomplete"
    return state, done, failed, pending


def _empty_participant() -> dict:
    return {"games": 0, "wins": 0, "points": 0, "initial_pips": 0}


def _participant_rows(stats: dict[int, dict], labels: list[str]) -> list[dict]:
    rows = []
    for index in sorted(stats):
        item = stats[index]
        games = item["games"]
        rows.append(
            {
                "participant": index,
                "label": labels[index] if index < len(labels) else f"Participant {index + 1}",
                "games": games,
                "wins": item["wins"],
                "win_rate": item["wins"] / games if games else 0.0,
                "average_points": item["points"] / games if games else 0.0,
                "average_initial_pips": item["initial_pips"] / games if games else 0.0,
            }
        )
    return rows


def _reproduce_command(manifest: dict, run_dir: Path) -> str:
    config = manifest.get("config") or {}
    parts = [
        "./scripts/lab run",
        f"--games {config.get('games', 0)}",
        f"--mode {config.get('mode', '1v1')}",
        f"--depth {config.get('depth', 1)}",
        f"--determinizations {config.get('determinizations', 1)}",
        f"--workers {config.get('workers', 1)}",
        f"--seed {config.get('seed', 0)}",
        f"--shards {config.get('shards', 0)}",
        f"--games-per-shard {config.get('games_per_shard', 5000)}",
        f"--run-id {manifest.get('run_id', 'run')}-repeat",
        f"--runs-dir {run_dir.parent}",
    ]
    opponent_depth = config.get("opponent_depth")
    opponent_samples = config.get("opponent_determinizations")
    if opponent_depth is not None and opponent_depth != config.get("depth"):
        parts.append(f"--opponent-depth {opponent_depth}")
    if opponent_samples is not None and opponent_samples != config.get("determinizations"):
        parts.append(f"--opponent-determinizations {opponent_samples}")
    if config.get("time_ms") is not None:
        parts.append(f"--time-ms {config['time_ms']}")
    if config.get("voluntary_draw") is not None:
        parts.append(f"--voluntary-draw {config['voluntary_draw']}")
    if config.get("opponent_voluntary_draw") is not None:
        parts.append(f"--opponent-voluntary-draw {config['opponent_voluntary_draw']}")
    return " \\\n  ".join(parts)


def _checks(
    manifest: dict,
    state: str,
    done: int,
    failed: int,
    pending: int,
    games: int,
    expected_games: int,
    incomplete: int,
    decisions: int,
    rows_declared: int,
    unknown_outcomes: Counter[str],
    issues: list[str],
    config: dict,
) -> list[dict]:
    checks: list[dict] = []
    total = done + failed + pending

    if state == "complete":
        checks.append(
            _check(
                "pass",
                "Every batch finished",
                f"{done}/{total} batches are marked done, with no failed batch.",
            )
        )
    elif state == "running":
        checks.append(
            _check(
                "warn",
                "The run is still active",
                f"{done}/{total} batches are done; this report is a snapshot and leaves unfinished batches out.",
                "Wait for the run to finish, then run `./scripts/lab report <run-id>` again.",
            )
        )
    else:
        checks.append(
            _check(
                "fail",
                "The run is not finished",
                f"{done}/{total} batches are done, {pending} are still pending, and {failed} failed.",
                "Resume the same run command, or inspect `runner.log` and the failed batch log before trusting any result.",
            )
        )

    if failed:
        checks.append(
            _check(
                "fail",
                "At least one batch failed",
                f"{failed} batch(es) did not complete. Their output is not included in the tables.",
                "Open the failed batch log under `shards/`, fix the cause, and resume the run.",
            )
        )
    if issues:
        for issue in issues[:8]:
            checks.append(_check("fail", "Data check", issue, "Inspect the raw CSV and `manifest.json`; do not edit the evidence."))
        if len(issues) > 8:
            checks.append(_check("fail", "More data problems", f"{len(issues) - 8} additional check(s) failed.", "Inspect `summary.json` for the complete report state."))

    if games == 0:
        checks.append(
            _check(
                "fail",
                "No hands could be read",
                "The report found no complete hand records in the finished batches.",
                "Check that a finished batch has a CSV with at least one game row.",
            )
        )
    elif state == "complete" and games != expected_games:
        checks.append(
            _check(
                "fail",
                "Hand count does not match the plan",
                f"The manifest planned {expected_games} hands, but {games} were read from the finished CSVs.",
                "Re-run the affected batch or inspect the CSV; do not treat this as a complete run.",
            )
        )

    if incomplete:
        checks.append(
            _check(
                "fail",
                "Some hands did not finish",
                f"{incomplete} hand(s) are marked unfinished, so they have no legitimate winner.",
                "Keep them out of any comparison and inspect the corresponding batch log.",
            )
        )

    if rows_declared and decisions != rows_declared:
        checks.append(
            _check(
                "warn",
                "Decision rows differ from the manifest",
                f"The manifest records {rows_declared} rows; the readable games contain {decisions} decisions.",
                "Check for a truncated or old batch before using the counts.",
            )
        )

    if unknown_outcomes:
        checks.append(
            _check(
                "fail",
                "Unknown result label",
                "The CSV contains outcome(s) this report does not recognise: "
                + ", ".join(sorted(unknown_outcomes)),
                "Treat the batch as suspect until the schema is explained.",
            )
        )

    depth = int(config.get("depth") or 0)
    samples = int(config.get("determinizations") or 0)
    if games < 100:
        checks.append(
            _check(
                "warn",
                "This is a smoke test",
                f"Only {games} hands were played. That can prove the wiring works; it cannot compare players or settings.",
                "Run a larger batch (at least 10,000 hands) before drawing any comparison.",
            )
        )
    elif games < 1_000:
        checks.append(
            _check(
                "warn",
                "The sample is very small",
                f"{games} hands is not enough for a stable comparison.",
                "Use at least 10,000 hands for a preliminary comparison, and more for a narrow one.",
            )
        )
    elif games < 10_000:
        checks.append(
            _check(
                "warn",
                "The sample is still small",
                f"{games} hands can show a large difference, but it cannot resolve a small one.",
                "Repeat or extend the run before making a strength claim.",
            )
        )
    else:
        checks.append(
            _check(
                "pass",
                "Descriptive sample",
                f"{games:,} hands is enough to describe what happened in this batch. It is not proof of strength.",
            )
        )

    if depth <= 2 or samples <= 2:
        checks.append(
            _check(
                "warn",
                "Very shallow search",
                f"Depth {depth} / {samples} samples is a fast wiring check, not a realistic playing strength.",
                "Use at least depth 8 / 64 samples for a reference run.",
            )
        )
    elif depth < 8 or samples < 64:
        checks.append(
            _check(
                "warn",
                "Below the reference search settings",
                f"Depth {depth} / {samples} samples is cheaper than the reference depth 8 / 64.",
                "Compare against the reference settings before drawing conclusions about strength.",
            )
        )
    else:
        checks.append(
            _check(
                "pass",
                "Reference search settings",
                "Depth 8 / 64 samples is the lab's reference configuration; this run still measures self-play, not human strength.",
            )
        )

    side_a = (
        config.get("depth"),
        config.get("determinizations"),
        config.get("workers"),
    )
    opponent_workers = config.get("opponent_workers")
    if opponent_workers is None:
        opponent_workers = config.get("workers")
    side_b = (
        config.get("opponent_depth"),
        config.get("opponent_determinizations"),
        opponent_workers,
    )
    if side_a == side_b:
        checks.append(
            _check(
                "pass",
                "Both sides used the same settings",
                "This is self-play consistency. It is not an A-versus-B strength comparison.",
            )
        )
    else:
        checks.append(
            _check(
                "pass",
                "Two search settings were compared",
                "Side A and side B differ. The sample-size checks still limit what can be concluded.",
            )
        )

    if config.get("seed") is not None:
        checks.append(
            _check(
                "pass",
                "Seed is recorded",
                f"Seed {config['seed']} is in the manifest. The same configuration and seed reproduce the same deals.",
            )
        )

    return checks


def _verdict(state: str, games: int, config: dict, checks: list[dict]) -> str:
    if state != "complete":
        return "NOT READY — this batch is incomplete; do not use it as a finished result."
    if any(check["level"] == "fail" for check in checks):
        return "CAUTION — the batch finished, but at least one data check failed."
    if games < 100 or int(config.get("depth") or 0) <= 2 or int(config.get("determinizations") or 0) <= 2:
        return "SMOKE TEST — the machinery worked, but this is not evidence about playing strength."
    if games < 10_000:
        return "PRELIMINARY — the batch finished, but the sample is too small for a strong claim."
    return "COMPLETE — these are descriptive results, not proof of playing strength."


def _render_readme(
    summary: dict,
    run_dir: Path,
    games_csv: Path | None,
) -> str:
    config = summary["config"]
    counts = summary["counts"]
    checks = summary["checks"]
    participants = summary["participants"]
    sides = summary["sides"]
    outcomes = summary["outcomes"]
    mode = config.get("mode", "?")
    games = counts["games_observed"]
    lines: list[str] = [
        f"# Start here — {summary['run_id']}",
        "",
        f"**Verdict:** {summary['verdict']}",
        "",
        f"**What this is:** {summary['description']}",
        "",
        f"**Folder:** `{run_dir}`",
        "",
        f"**Generated:** {summary['generated_at']} from `manifest.json` and the finished shard CSVs.",
        "",
        "This file is generated. It is safe to delete and rebuild with:",
        "",
        "```bash",
        f"./scripts/lab report {summary['run_id']} --runs-dir {run_dir.parent}",
        "```",
        "",
        "The raw CSV files are the evidence. This report does not change them.",
        "",
        "## The ten-second version",
        "",
        f"- **Mode:** {_mode_plain(mode)}",
        f"- **Hands recorded:** {games:,} ({counts['games_finished']:,} finished, {counts['incomplete']:,} unfinished)",
        f"- **Search:** depth {config.get('depth')} / {config.get('determinizations')} hidden-world samples / "
        f"{config.get('workers')} {'worker' if config.get('workers') == 1 else 'workers'}",
        f"- **Decisions:** {counts['decisions']:,} tile plays or draws",
        f"- **Batches:** {counts['batches_done']} of {counts['batches_total']} done",
        "",
    ]

    if participants:
        winners = [item for item in participants if item["wins"]]
        if winners:
            winner_text = ", ".join(
                f"{item['label']} won {item['wins']} of {item['games']}"
                for item in winners
            )
        else:
            winner_text = "No unique winner was recorded."
        lines.extend([f"**Who won:** {winner_text}", ""])

    lines.extend(
        [
            "**What that means:** " + summary["meaning"],
            "",
            "## What happened",
            "",
            "| Measure | Value | Plain meaning |",
            "|---|---:|---|",
            f"| Hands recorded | {games:,} | Each row group is one hand/round. |",
            f"| Finished hands | {counts['games_finished']:,} | A hand with a domino or closed result. |",
            f"| Unfinished hands | {counts['incomplete']:,} | Stopped early; not a result. |",
            f"| Decisions | {counts['decisions']:,} | One tile play or draw choice. |",
            f"| Average decisions per hand | {counts['average_decisions']:.1f} | How long a hand lasted. |",
            f"| Declared CSV rows | {counts['rows_declared']:,} | The row count recorded by the runner. |",
            "",
        ]
    )

    if outcomes:
        lines.extend(
            [
                "### Results at a glance",
                "",
                "| Result | Hands | Plain meaning |",
                "|---|---:|---|",
            ]
        )
        for outcome, count in sorted(outcomes.items()):
            lines.append(f"| {_outcome_plain(outcome)} | {count:,} | {_outcome_meaning(outcome)} |")
        lines.append("")

    if participants:
        lines.extend(
            [
                "### Per-participant table",
                "",
                "| Participant | Hands | Wins | Win rate | Average points | Average starting pips |",
                "|---|---:|---:|---:|---:|---:|",
            ]
        )
        for item in participants:
            lines.append(
                f"| {item['label']} | {item['games']:,} | {item['wins']:,} | "
                f"{item['win_rate'] * 100:.1f}% | {item['average_points']:.2f} | "
                f"{item['average_initial_pips']:.1f} |"
            )
        lines.extend(
            [
                "",
                "A win is credited only when the final summary has a unique winner. "
                "Unfinished hands are counted as played but not as wins.",
                "",
            ]
        )

    if sides and len(sides) > 1 and config.get("opponent_depth") != config.get("depth"):
        lines.extend(
            [
                "### Side A versus side B",
                "",
                "| Side | Hands | Wins | Win rate | Average points |",
                "|---|---:|---:|---:|---:|",
            ]
        )
        for item in sides:
            lines.append(
                f"| {item['label']} | {item['games']:,} | {item['wins']:,} | "
                f"{item['win_rate'] * 100:.1f}% | {item['average_points']:.2f} |"
            )
        lines.extend(
            [
                "",
                "The engine alternates which physical seat gets side A, so a first-player "
                "advantage is not silently assigned to one configuration.",
                "",
            ]
        )

    good = [check for check in checks if check["level"] == "pass"]
    attention = [check for check in checks if check["level"] in ("warn", "fail")]

    lines.extend(["## What is good", ""])
    if good:
        for check in good:
            lines.append(f"- **{check['title']}.** {check['detail']}")
    else:
        lines.append("- The report could be built from the recorded files.")
    lines.append("")

    lines.extend(["## What needs attention", ""])
    if attention:
        for check in attention:
            line = f"- **{check['title']}** ({check['level']}). {check['detail']}"
            if check.get("action"):
                line += f" Action: {check['action']}"
            lines.append(line)
    else:
        lines.append("- No structural problems were found in the readable data.")
    lines.append("")

    lines.extend(["## What to do next", ""])
    actions = []
    for check in attention:
        action = check.get("action")
        if action and action not in actions:
            actions.append(action)
    if not actions:
        actions.append("Keep the raw CSVs and rerun `./scripts/lab report <run-id>` after any new batch.")
    for action in actions:
        lines.append(f"1. {action}")
    lines.append("")

    lines.extend(
        [
            "## How to reproduce",
            "",
            "The command below uses the recorded configuration and a new run id so it cannot overwrite this folder:",
            "",
            "```bash",
            summary["reproduce_command"],
            "```",
            "",
            "The seed controls the deals. The same configuration and seed should produce the same decisions; "
            "worker count must not change a chosen move.",
            "",
            "## Where everything is",
            "",
            "| File or folder | What it is |",
            "|---|---|",
            "| `README.md` | This explanation. Generated; safe to rebuild. |",
            "| `summary.json` | The same facts for the app or a script. |",
            "| `games.csv` | One row per hand, when the run is small enough for a tidy table. |",
            "| `manifest.json` | The runner's machine record: batches, seeds, status and row counts. |",
            "| `shards/` | The raw per-batch CSVs and their logs. This is the evidence. |",
            "| `runner.log` | The runner's progress log. |",
            "",
        ]
    )
    if games_csv is None:
        lines.extend(
            [
                "`games.csv` was omitted because this batch is larger than "
                f"{GAMES_CSV_LIMIT:,} hands. The aggregate report and raw shards are still complete.",
                "",
            ]
        )

    lines.extend(
        [
            "## What not to conclude",
            "",
            summary["caution"],
            "",
            "## Words used here",
            "",
            "- **Hand**: one deal, from opening tile to a domino or closed result. The CSV calls this a `game`; the rulebook calls it a hand or round.",
            "- **Decision**: one tile play or one draw choice. The CSV has one row per decision.",
            "- **Depth**: how many moves ahead the search looks. A low depth is fast and weak.",
            "- **Samples / hidden worlds**: how many possible hidden-hand arrangements the search considers. Fewer samples means a noisier decision.",
            "- **Seed**: the number that makes the deal sequence reproducible.",
            "- **Side A / side B**: the two search configurations. The engine alternates the physical seats.",
            "- **Batch / shard**: a group of hands run by one worker process. A run can have many batches.",
            "- **Domino win**: a player emptied their hand.",
            "- **Closed hand**: no legal play remained. The lower remaining hand wins; 1v1 and 2v2 award the loser's total, while 1v1v1 gives the lowest hand zero and adds every other hand's value.",
            "- **Starting / ending pips**: the pip total in a participant's hand at the start and end of the hand. Lower is better.",
            "",
            "## If something looks wrong",
            "",
            "Open `runner.log` first, then the relevant `shards/shard-XXXX.log`. "
            "Do not edit a raw CSV to make a report look nicer: that would destroy the evidence. "
            "Rebuild this report with the command above instead.",
            "",
        ]
    )
    return "\n".join(lines)


def generate(
    run_dir: str | Path,
    manifest: dict | None = None,
    *,
    force_games_csv: bool = False,
) -> dict:
    """Write README.md, summary.json and (when appropriate) games.csv.

    Returns the artifact paths. The raw shard CSVs are opened read-only.
    """
    run_dir = Path(run_dir)
    if manifest is None:
        manifest_path = run_dir / "manifest.json"
        if not manifest_path.is_file():
            raise ValueError(f"no manifest.json in {run_dir}")
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if not isinstance(manifest, dict):
        raise ValueError("manifest must be a JSON object")
    config = dict(manifest.get("config") or {})
    mode = config.get("mode", "1v1")
    run_id = str(manifest.get("run_id") or run_dir.name)
    expected_participants = _participant_count(mode)
    labels = [_participant_label(mode, index) for index in range(expected_participants)]
    keys = [_column_key(label) for label in labels]

    shards = list(manifest.get("shards") or [])
    state, done, failed, pending = _state(manifest, run_dir)
    issues: list[str] = []
    parse_errors: list[str] = []
    outcomes: Counter[str] = Counter()
    unknown_outcomes: Counter[str] = Counter()
    participant_stats: dict[int, dict] = {}
    side_stats: dict[int, dict] = {}
    games_observed = 0
    decisions = 0
    incomplete = 0
    finished_games = 0
    rows_declared = sum(int(shard.get("rows") or 0) for shard in shards if shard.get("status") == "done")
    expected_games = int(config.get("games") or sum(int(shard.get("games") or 0) for shard in shards))
    games_csv_enabled = force_games_csv or expected_games <= GAMES_CSV_LIMIT
    games_csv_path = run_dir / "games.csv"
    temporary_games = run_dir / ".games.csv.tmp"

    fieldnames = [
        "batch",
        "hand",
        "seed",
        "mode",
        "outcome",
        "what_happened",
        "winner",
        "deciding_player",
        "decisions",
        "config_a_depth",
        "config_a_samples",
        "config_b_depth",
        "config_b_samples",
    ]
    for key in keys:
        fieldnames.extend([f"{key}_points", f"{key}_starting_pips", f"{key}_ending_pips"])

    games_writer = None
    games_handle = None
    try:
        if games_csv_enabled:
            games_handle = temporary_games.open("w", newline="", encoding="utf-8")
            games_writer = csv.DictWriter(games_handle, fieldnames=fieldnames, lineterminator="\n")
            games_writer.writeheader()

        for shard in shards:
            if shard.get("status") != "done":
                continue
            csv_name = shard.get("csv")
            if not csv_name:
                issues.append(f"Batch {shard.get('index', '?')} has no CSV filename in the manifest.")
                continue
            csv_path = run_dir / "shards" / str(csv_name)
            if not csv_path.is_file():
                issues.append(f"Batch {shard.get('index', '?')} is marked done but {csv_path.name} is missing.")
                continue
            expected_seed = shard.get("seed")
            shard_expected = int(shard.get("games") or 0)
            shard_games = 0
            last_game: int | None = None
            try:
                for game in dataset.iter_games(csv_path):
                    if game.mode != mode:
                        issues.append(
                            f"Batch {shard.get('index', '?')} says mode {game.mode}, but the run is {mode}."
                        )
                    if expected_seed is not None and game.seed != int(expected_seed):
                        issues.append(
                            f"Batch {shard.get('index', '?')} has seed {game.seed}, expected {expected_seed}."
                        )
                    if last_game is not None and game.game != last_game + 1:
                        issues.append(
                            f"Batch {shard.get('index', '?')} has a gap: hand {last_game} is followed by {game.game}."
                        )
                    last_game = game.game
                    count = game.participant_count
                    if count != expected_participants:
                        issues.append(
                            f"Batch {shard.get('index', '?')} hand {game.game} has {count} participants; expected {expected_participants}."
                        )
                    outcomes[game.outcome] += 1
                    if game.outcome not in KNOWN_OUTCOMES:
                        unknown_outcomes[game.outcome] += 1
                    if game.outcome == "in_progress":
                        incomplete += 1
                    else:
                        finished_games += 1
                    games_observed += 1
                    shard_games += 1
                    decisions += game.decisions
                    winner = _winner(game)
                    winner_label = _participant_label(mode, winner) if winner is not None else ""
                    deciding_label = (
                        _participant_label(mode, game.deciding_player)
                        if 0 <= game.deciding_player < expected_participants
                        else ""
                    )
                    for participant in range(expected_participants):
                        stats = participant_stats.setdefault(participant, _empty_participant())
                        stats["games"] += 1
                        if participant < count:
                            stats["points"] += int(game.participant_scores[participant])
                            stats["initial_pips"] += initial_value_for_participant(game, participant)
                            if winner == participant:
                                stats["wins"] += 1
                            side = (
                                game.participant_sides[participant]
                                if participant < len(game.participant_sides)
                                else participant
                            )
                            side_stats.setdefault(side, _empty_participant())
                            side_item = side_stats[side]
                            side_item["games"] += 1
                            side_item["points"] += int(game.participant_scores[participant])
                            side_item["initial_pips"] += initial_value_for_participant(game, participant)
                            if winner == participant:
                                side_item["wins"] += 1
                    if games_writer is not None:
                        row = {
                            "batch": shard.get("index", 0),
                            "hand": game.game,
                            "seed": game.seed,
                            "mode": game.mode,
                            "outcome": game.outcome,
                            "what_happened": _what_happened(game, winner),
                            "winner": winner_label,
                            "deciding_player": deciding_label,
                            "decisions": game.decisions,
                            "config_a_depth": game.config_a[0],
                            "config_a_samples": game.config_a[1],
                            "config_b_depth": game.config_b[0],
                            "config_b_samples": game.config_b[1],
                        }
                        for participant, key in enumerate(keys):
                            row[f"{key}_points"] = (
                                game.participant_scores[participant]
                                if participant < len(game.participant_scores)
                                else ""
                            )
                            row[f"{key}_starting_pips"] = (
                                initial_value_for_participant(game, participant)
                                if participant < count
                                else ""
                            )
                            row[f"{key}_ending_pips"] = (
                                game.final_hands[participant]
                                if participant < len(game.final_hands)
                                else ""
                            )
                        games_writer.writerow(row)
                if shard_games != shard_expected:
                    issues.append(
                        f"Batch {shard.get('index', '?')} planned {shard_expected} hands but contains {shard_games}."
                    )
            except (OSError, ValueError, csv.Error) as exc:
                parse_errors.append(f"Batch {shard.get('index', '?')}: {exc}")
    finally:
        if games_handle is not None:
            games_handle.close()

    if parse_errors:
        issues.extend(parse_errors)

    if games_csv_enabled and not parse_errors:
        os.replace(temporary_games, games_csv_path)
        games_csv: Path | None = games_csv_path
    else:
        # A malformed shard must not leave a tidy-looking partial table behind.
        temporary_games.unlink(missing_ok=True)
        games_csv_path.unlink(missing_ok=True)
        games_csv = None

    participant_rows = _participant_rows(participant_stats, labels)
    side_rows = _participant_rows(side_stats, ["A", "B", "C", "D"])
    checks = _checks(
        manifest,
        state,
        done,
        failed,
        pending,
        games_observed,
        expected_games,
        incomplete,
        decisions,
        rows_declared,
        unknown_outcomes,
        issues,
        config,
    )
    verdict = _verdict(state, games_observed, config, checks)
    average_decisions = decisions / games_observed if games_observed else 0.0

    if state != "complete":
        meaning = "This is a partial snapshot. Only batches marked done were read."
        caution = (
            "Do not use this folder as a finished comparison. Unfinished batches are not in the tables, "
            "and the missing hands are not a random sample."
        )
        description = "A self-play batch that is not finished yet."
    elif games_observed < 100 or int(config.get("depth") or 0) <= 2 or int(config.get("determinizations") or 0) <= 2:
        meaning = (
            "The run completed, but it is a wiring check. The settings are deliberately cheap and the "
            "sample is far too small to tell whether one side is stronger."
        )
        caution = (
            "Do not say one player or search setting is stronger from this run. With this few hands and "
            "this shallow search, the result is mostly noise plus a check that the machinery works."
        )
        description = "A small, cheap self-play smoke test used to prove the pipeline works."
    elif games_observed < 10_000:
        meaning = (
            "The run completed and the data is readable, but the sample is small. It can show a large "
            "difference and cannot reliably resolve a small one."
        )
        caution = (
            "Do not treat the win-rate table as a strength measurement. It is a description of this "
            "sample, and a small sample can move a lot when the seed changes."
        )
        description = "A completed self-play sample, large enough to inspect but not to settle a close question."
    else:
        meaning = "The run completed and the data is readable. The tables describe this sample."
        caution = (
            "This is self-play, not a human test. A descriptive advantage here is not a promise against "
            "people, and it is not evidence merely because the CSV is large."
        )
        description = "A completed self-play batch with readable, verified-by-shape output."

    summary = {
        "schema": REPORT_SCHEMA,
        "run_id": run_id,
        "generated_at": _now(),
        "status": state,
        "verdict": verdict,
        "description": description,
        "meaning": meaning,
        "caution": caution,
        "config": config,
        "counts": {
            "games_expected": expected_games,
            "games_observed": games_observed,
            "games_finished": finished_games,
            "incomplete": incomplete,
            "decisions": decisions,
            "average_decisions": average_decisions,
            "batches_total": len(shards),
            "batches_done": done,
            "batches_failed": failed,
            "batches_pending": pending,
            "rows_declared": rows_declared,
        },
        "outcomes": dict(sorted(outcomes.items())),
        "participants": participant_rows,
        "sides": side_rows,
        "checks": checks,
        "reproduce_command": _reproduce_command(manifest, run_dir),
        "files": {
            "readme": "README.md",
            "summary": "summary.json",
            "games_csv": games_csv.name if games_csv else None,
            "manifest": "manifest.json",
            "shards": "shards/",
            "runner_log": "runner.log",
        },
    }

    readme = _render_readme(summary, run_dir, games_csv)
    _atomic_json(run_dir / "summary.json", summary)
    _atomic_text(run_dir / "README.md", readme)
    return {
        "readme": run_dir / "README.md",
        "summary": run_dir / "summary.json",
        "games_csv": games_csv,
    }


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="lab report",
        description="Write a plain-language README, summary and games table for one run.",
    )
    parser.add_argument("run_id")
    parser.add_argument("--runs-dir", type=Path, help="directory containing run folders")
    parser.add_argument(
        "--games-csv",
        action="store_true",
        help=f"write games.csv even above the automatic {GAMES_CSV_LIMIT:,}-hand limit",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    if not RUN_ID_PATTERN.match(args.run_id):
        print(f"invalid run id {args.run_id!r}", file=sys.stderr)
        return 2
    root = (args.runs_dir or RUNS).resolve()
    run_dir = root / args.run_id
    if not run_dir.is_dir():
        print(f"no such run: {run_dir}", file=sys.stderr)
        return 2
    try:
        paths = generate(run_dir, force_games_csv=args.games_csv)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"could not write report: {exc}", file=sys.stderr)
        return 2
    print(f"wrote {paths['readme']}")
    print(f"wrote {paths['summary']}")
    if paths["games_csv"] is not None:
        print(f"wrote {paths['games_csv']}")
    else:
        print(f"games.csv omitted above {GAMES_CSV_LIMIT:,} hands; pass --games-csv to force it")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
