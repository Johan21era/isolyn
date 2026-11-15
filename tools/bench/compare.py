#!/usr/bin/env python3
"""Compare two `tools/bench/tiers.py` result directories."""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path


def load(root: Path) -> dict:
    with (root / "summary.csv").open("r", newline="", encoding="utf-8") as handle:
        return {row["tier"]: row for row in csv.DictReader(handle)}


def pct(before: float, after: float) -> str:
    if before == 0:
        return "n/a"
    # For RAM, a negative percentage is the desired reduction.
    return f"{(after - before) / before * 100:+.1f}%"


def mib(value: float) -> str:
    return f"{value / 1024 / 1024:.1f}"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--before", type=Path, required=True)
    parser.add_argument("--after", type=Path, required=True)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()

    before = load(args.before)
    after = load(args.after)
    if list(before) != list(after):
        raise SystemExit("the two runs cover different tiers or tier order")

    rows = []
    for tier in before:
        old, new = before[tier], after[tier]
        old_rate = float(old["games_per_second"])
        new_rate = float(new["games_per_second"])
        old_wall = float(old["wall_seconds"])
        new_wall = float(new["wall_seconds"])
        old_peak = int(old["max_rss_bytes"])
        new_peak = int(new["max_rss_bytes"])
        old_mean = int(old["mean_rss_bytes"])
        new_mean = int(new["mean_rss_bytes"])
        rows.append({
            "tier": tier,
            "depth": int(old["depth"]),
            "determinizations": int(old["determinizations"]),
            "games": int(old["games"]),
            "before_games_per_second": old_rate,
            "after_games_per_second": new_rate,
            "speedup": round(new_rate / old_rate, 4) if old_rate else 0.0,
            "before_wall_seconds": old_wall,
            "after_wall_seconds": new_wall,
            "before_peak_rss_bytes": old_peak,
            "after_peak_rss_bytes": new_peak,
            "peak_rss_change_pct": round((new_peak - old_peak) / old_peak * 100, 2) if old_peak else 0.0,
            "before_mean_rss_bytes": old_mean,
            "after_mean_rss_bytes": new_mean,
            "mean_rss_change_pct": round((new_mean - old_mean) / old_mean * 100, 2) if old_mean else 0.0,
            "before_nodes": int(old["nodes"]),
            "after_nodes": int(new["nodes"]),
            "before_tt_hits": int(old["tt_hits"]),
            "after_tt_hits": int(new["tt_hits"]),
        })

    total_games = sum(row["games"] for row in rows)
    total_before_wall = sum(row["before_wall_seconds"] for row in rows)
    total_after_wall = sum(row["after_wall_seconds"] for row in rows)
    total_before_nodes = sum(row["before_nodes"] for row in rows)
    total_after_nodes = sum(row["after_nodes"] for row in rows)

    lines = [
        "# Five-tier benchmark comparison",
        "",
        "| Tier | Depth / worlds | Before games/s | After games/s | Speedup | Before wall | After wall | "
        "Before peak RSS | After peak RSS | Peak Δ | Before mean RSS | After mean RSS | Mean Δ |",
        "|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for row in rows:
        lines.append(
            f"| {row['tier']} | {row['depth']}/{row['determinizations']} "
            f"| {row['before_games_per_second']:.2f} | {row['after_games_per_second']:.2f} "
            f"| {row['speedup']:.2f}× | {row['before_wall_seconds']:.1f}s | {row['after_wall_seconds']:.1f}s "
            f"| {mib(row['before_peak_rss_bytes'])} MiB | {mib(row['after_peak_rss_bytes'])} MiB "
            f"| {pct(row['before_peak_rss_bytes'], row['after_peak_rss_bytes'])} "
            f"| {mib(row['before_mean_rss_bytes'])} MiB | {mib(row['after_mean_rss_bytes'])} MiB "
            f"| {pct(row['before_mean_rss_bytes'], row['after_mean_rss_bytes'])} |"
        )

    lines += [
        "",
        f"**Games:** {total_games:,} per arm  ",
        f"**Wall:** {total_before_wall / 60:.1f} min before, {total_after_wall / 60:.1f} min after  ",
        f"**Aggregate throughput:** {total_games / total_before_wall:.2f} → "
        f"{total_games / total_after_wall:.2f} games/s "
        f"({(total_games / total_after_wall) / (total_games / total_before_wall):.2f}×)  ",
        f"**Nodes:** {total_before_nodes:,} before, {total_after_nodes:,} after "
        f"({(total_after_nodes - total_before_nodes) / total_before_nodes * 100:+.1f}%)",
        "",
        "Peak RSS is the maximum `/usr/bin/time -l` maximum resident set size across the "
        "eight independent one-worker shards in a tier. Mean RSS is the arithmetic mean "
        "of those eight processes.",
        "",
    ]

    text = "\n".join(lines)
    print(text)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text, encoding="utf-8")
        args.output.with_suffix(".json").write_text(
            json.dumps({
                "before": str(args.before),
                "after": str(args.after),
                "total_games": total_games,
                "rows": rows,
            }, indent=2) + "\n",
            encoding="utf-8",
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
