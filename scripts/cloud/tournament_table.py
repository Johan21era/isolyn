#!/usr/bin/env python3
"""Turn a tournament run's per-session CSVs into an Elo table.

Reads the plan's pairing labels and each fetched session's shard CSVs, and
reports, per pairing: rounds, the A side's score, the implied Elo with a 95%
interval, and the search cost that produced it. Sessions that have not been
fetched yet are listed as pending rather than silently omitted.

Standard library only. Deterministic: no timestamps, no ordering by hash.

Usage:
    python3 scripts/cloud/tournament_table.py lab/data/cloud/<run-id> [--json PATH]
"""

from __future__ import annotations

import csv
import json
import math
import sys
from pathlib import Path


def game_scores(csv_paths: list[Path]) -> dict[tuple[str, str], float]:
    """Score each round for the A side: 1 win, 0.5 drawn/tied, 0 loss."""
    scores: dict[tuple[str, str], float] = {}
    for path in csv_paths:
        try:
            handle = path.open(newline="", encoding="utf-8")
        except OSError:
            continue
        with handle:
            for row in csv.DictReader(handle):
                try:
                    game = row["game"]
                    participants = int(row["participant_count"])
                except (KeyError, TypeError, ValueError):
                    continue
                key = (path.name, game)
                if key in scores:
                    continue
                a = b = None
                for p in range(participants):
                    try:
                        side = int(row[f"participant_side{p}"])
                        score = int(row[f"participant_score{p}"] or 0)
                    except (KeyError, TypeError, ValueError):
                        continue
                    if side == 0:
                        a = score
                    elif side == 1:
                        b = score
                if a is None or b is None:
                    scores[key] = 0.5
                elif a > b:
                    scores[key] = 1.0
                elif a < b:
                    scores[key] = 0.0
                else:
                    scores[key] = 0.5
    return scores


def elo(score: float) -> float:
    score = min(max(score, 1e-9), 1.0 - 1e-9)
    return -400.0 * math.log10(1.0 / score - 1.0)


def cost_summary(csv_paths: list[Path]) -> tuple[float, float]:
    """Mean decisions per round and mean completed depth, from the same rows."""
    decisions: dict[tuple[str, str], int] = {}
    depth_total = 0.0
    depth_rows = 0
    for path in csv_paths:
        try:
            handle = path.open(newline="", encoding="utf-8")
        except OSError:
            continue
        with handle:
            for row in csv.DictReader(handle):
                key = (path.name, row.get("game", ""))
                decisions[key] = decisions.get(key, 0) + 1
                try:
                    depth_total += float(row.get("depth_reached") or 0)
                    depth_rows += 1
                except (TypeError, ValueError):
                    pass
    rounds = len(decisions)
    mean_decisions = sum(decisions.values()) / rounds if rounds else 0.0
    mean_depth = depth_total / depth_rows if depth_rows else 0.0
    return mean_decisions, mean_depth


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print(__doc__.strip())
        return 2
    run_dir = Path(argv[1])
    json_out = None
    if "--json" in argv:
        json_out = Path(argv[argv.index("--json") + 1])

    plan_path = run_dir / "plan.json"
    if not plan_path.is_file():
        print(f"no plan.json in {run_dir}; this is not a cloud run directory")
        return 2
    plan = json.loads(plan_path.read_text(encoding="utf-8"))
    sessions = plan.get("sessions", [])

    rows = []
    for session in sessions:
        session_dir = run_dir / "sessions" / session["id"]
        csv_paths = sorted(session_dir.glob("shard-*.csv"))
        label = session.get("label") or session["id"]
        if not csv_paths:
            rows.append({"session": session["id"], "pairing": label, "state": "pending"})
            continue
        scores = game_scores(csv_paths)
        n = len(scores)
        if n == 0:
            rows.append({"session": session["id"], "pairing": label, "state": "empty"})
            continue
        total = sum(scores.values())
        mean = total / n
        var = sum((s - mean) ** 2 for s in scores.values()) / (n - 1) if n > 1 else 0.0
        se = math.sqrt(var / n)
        mean_decisions, mean_depth = cost_summary(csv_paths)
        rows.append({
            "session": session["id"],
            "pairing": label,
            "state": "measured",
            "rounds": n,
            "score": mean,
            "elo": elo(mean),
            "elo_low": elo(mean - 1.96 * se),
            "elo_high": elo(mean + 1.96 * se),
            "decisions_per_round": mean_decisions,
            "mean_depth": mean_depth,
        })

    measured = [row for row in rows if row["state"] == "measured"]
    print(f"run {plan.get('run_id')}  source {str(plan.get('source_commit'))[:12]}")
    print(f"{len(measured)}/{len(rows)} pairing(s) measured\n")
    header = f"{'session':<8}{'pairing':<26}{'rounds':>8}{'score':>9}{'Elo':>9}{'95% CI':>20}{'dec/rd':>8}{'depth':>7}"
    print(header)
    print("-" * len(header))
    for row in rows:
        if row["state"] != "measured":
            print(f"{row['session']:<8}{row['pairing']:<26}{row['state']:>8}")
            continue
        ci = f"[{row['elo_low']:+.1f}, {row['elo_high']:+.1f}]"
        print(f"{row['session']:<8}{row['pairing']:<26}{row['rounds']:>8}"
              f"{row['score']:>9.4f}{row['elo']:>+9.1f}{ci:>20}"
              f"{row['decisions_per_round']:>8.1f}{row['mean_depth']:>7.1f}")

    # A star of pairings all against one common engine gives a standings table
    # directly; a full round-robin needs pairwise chaining, which is reported
    # as-is rather than approximated here.
    anchors: dict[str, int] = {}
    for row in measured:
        if "-vs-" not in row["pairing"]:
            continue
        anchors[row["pairing"].split("-vs-")[0]] = anchors.get(row["pairing"].split("-vs-")[0], 0) + 1
    if anchors:
        anchor, count = max(anchors.items(), key=lambda item: item[1])
        if count == len(measured) and len(measured) > 1:
            print(f"\nstandings, anchored at {anchor} = 0 Elo (all pairings include it):")
            for row in measured:
                if not row["pairing"].startswith(anchor + "-vs-"):
                    continue
                name = row["pairing"].split("-vs-", 1)[1]
                print(f"  {name:<12}{row['elo']:+.1f} Elo vs {anchor}"
                      f"  [{row['elo_low']:+.1f}, {row['elo_high']:+.1f}]")

    if json_out is not None:
        json_out.parent.mkdir(parents=True, exist_ok=True)
        json_out.write_text(json.dumps({"run_id": plan.get("run_id"), "pairings": rows},
                                       indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print(f"\nwrote {json_out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
