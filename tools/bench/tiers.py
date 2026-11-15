#!/usr/bin/env python3
"""Measure the seven difficulty tiers under one fixed workload.

Each tier runs as the same number of independent one-worker self-play shards.
That keeps the measurements comparable: a shard owns one search lane and one
transposition table, so peak RSS is not confused with lane count. The raw
self-play CSV, stderr log and `/usr/bin/time -l` record are kept for every
shard; the summary CSV is derived from those files.

Usage:
    python3 tools/bench/tiers.py --binary tools/selfplay/build/selfplay \
        --games 10000 --shards 8 --seed 4100 --label after --output-dir /tmp/...
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

TIERS = (
    ("casual", 2, 8),
    ("club", 3, 16),
    ("elite", 4, 24),
    ("expert", 5, 40),
    ("master", 8, 64),
    ("legendary", 24, 80),
    ("mythical", 48, 160),
)

_TIME_RE = re.compile(r"([0-9.]+)\s+real\s+([0-9.]+)\s+user\s+([0-9.]+)\s+sys")
_RSS_RE = re.compile(r"(\d+)\s+maximum resident set size")
_FOOTPRINT_RE = re.compile(r"(\d+)\s+peak memory footprint")
_DECISIONS_RE = re.compile(r"decisions:\s*(\d+)")


def parse_time_record(path: Path) -> dict:
    text = path.read_text(encoding="utf-8", errors="replace")
    match = _TIME_RE.search(text)
    if not match:
        raise SystemExit(f"{path}: no real/user/sys record")
    rss = _RSS_RE.search(text)
    footprint = _FOOTPRINT_RE.search(text)
    return {
        "real_seconds": float(match.group(1)),
        "user_seconds": float(match.group(2)),
        "sys_seconds": float(match.group(3)),
        "max_rss_bytes": int(rss.group(1)) if rss else 0,
        "peak_footprint_bytes": int(footprint.group(1)) if footprint else 0,
    }


def count_rows(path: Path) -> int:
    with path.open("rb") as handle:
        return max(0, sum(1 for _ in handle) - 1)


def sum_csv_columns(path: Path) -> dict:
    totals = {"decisions_csv": 0, "nodes": 0, "tt_hits": 0, "exact_endgame": 0}
    with path.open("r", newline="", encoding="utf-8") as handle:
        for row in csv.DictReader(handle):
            totals["decisions_csv"] += 1
            totals["nodes"] += int(row["nodes"])
            totals["tt_hits"] += int(row["tt_hits"])
            totals["exact_endgame"] += int(row["exact_endgame"])
    return totals


def start_shard(binary: Path, tier: str, depth: int, samples: int, games: int,
                seed: int, shard: int, root: Path) -> dict:
    shard_dir = root / "shards" / tier
    shard_dir.mkdir(parents=True, exist_ok=True)
    csv_path = shard_dir / f"shard-{shard:02d}.csv"
    log_path = shard_dir / f"shard-{shard:02d}.log"
    time_path = shard_dir / f"shard-{shard:02d}.time"
    command = [
        "/usr/bin/time", "-l", "-o", str(time_path),
        str(binary),
        "--games", str(games),
        "--depth", str(depth),
        "--determinizations", str(samples),
        "--workers", "1",
        "--opponent-depth", str(depth),
        "--opponent-determinizations", str(samples),
        "--opponent-workers", "1",
        "--seed", str(seed + shard),
        "--output", str(csv_path),
    ]
    log = log_path.open("w", encoding="utf-8")
    process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT)
    return {
        "process": process,
        "log": log,
        "tier": tier,
        "shard": shard,
        "seed": seed + shard,
        "games": games,
        "csv_path": csv_path,
        "time_path": time_path,
        "log_path": log_path,
    }


def run_tier(binary: Path, tier: str, depth: int, samples: int, games: int,
             shards: int, seed: int, root: Path, overlap: int) -> dict:
    started = time.monotonic()
    pending = [
        games // shards + (1 if shard < games % shards else 0)
        for shard in range(shards)
    ]
    running = []
    records = []

    next_shard = 0
    while next_shard < shards or running:
        while next_shard < shards and len(running) < overlap:
            job = start_shard(binary, tier, depth, samples, pending[next_shard],
                              seed, next_shard, root)
            running.append(job)
            next_shard += 1

        still_running = []
        for job in running:
            code = job["process"].poll()
            if code is None:
                still_running.append(job)
                continue
            job["log"].close()
            if code != 0:
                raise SystemExit(
                    f"{tier} shard {job['shard']}: exit {code}; see {job['log_path']}"
                )
            record = parse_time_record(job["time_path"])
            record.update({
                "tier": tier,
                "shard": job["shard"],
                "seed": job["seed"],
                "games": job["games"],
                "csv_path": job["csv_path"],
                "log_path": job["log_path"],
            })
            records.append(record)
        running = still_running
        if running:
            time.sleep(0.25)

    # Stop the clock before reading any per-shard output, so CSV parsing cannot
    # steal CPU from the next tier or inflate this tier's wall time.
    wall = time.monotonic() - started
    if len(records) != shards:
        raise SystemExit(f"{tier}: expected {shards} shard records, got {len(records)}")

    csv_totals = {"decisions_csv": 0, "nodes": 0, "tt_hits": 0, "exact_endgame": 0}
    decisions = 0
    for record in records:
        csv_path = record.pop("csv_path")
        log_path = record.pop("log_path")
        record["csv_rows"] = count_rows(csv_path)
        log_text = log_path.read_text(encoding="utf-8", errors="replace")
        match = _DECISIONS_RE.search(log_text)
        record["decisions"] = int(match.group(1)) if match else 0
        for key, value in sum_csv_columns(csv_path).items():
            csv_totals[key] += value
        decisions += record["decisions"]

    games_done = sum(record["games"] for record in records)
    rss = [record["max_rss_bytes"] for record in records]
    footprint = [record["peak_footprint_bytes"] for record in records]
    return {
        "tier": tier,
        "depth": depth,
        "determinizations": samples,
        "games": games_done,
        "decisions": decisions,
        "wall_seconds": round(wall, 3),
        "games_per_second": round(games_done / wall, 4) if wall > 0 else 0.0,
        "max_rss_bytes": max(rss) if rss else 0,
        "mean_rss_bytes": sum(rss) // len(rss) if rss else 0,
        "max_peak_footprint_bytes": max(footprint) if footprint else 0,
        "nodes": csv_totals["nodes"],
        "tt_hits": csv_totals["tt_hits"],
        "exact_endgame_decisions": csv_totals["exact_endgame"],
        "nodes_per_game": round(csv_totals["nodes"] / games_done, 2) if games_done else 0.0,
        "nodes_per_second": round(csv_totals["nodes"] / wall, 2) if wall > 0 else 0.0,
        "shards": shards,
        "seed": seed,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", type=Path, required=True)
    parser.add_argument("--games", type=int, default=10000,
                        help="games per tier (split across shards)")
    parser.add_argument("--shards", type=int, default=8)
    parser.add_argument("--overlap", type=int, default=8)
    parser.add_argument("--seed", type=int, default=4100)
    parser.add_argument("--label", required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--tiers", default=",".join(tier[0] for tier in TIERS))
    args = parser.parse_args()

    binary = args.binary.resolve()
    if not binary.is_file():
        raise SystemExit(f"binary not found: {binary}")
    if args.games < args.shards:
        raise SystemExit("--games must be at least --shards")
    if args.shards < 1 or args.overlap < 1:
        raise SystemExit("--shards and --overlap must be positive")

    root = args.output_dir.resolve()
    root.mkdir(parents=True, exist_ok=True)
    selected = set(args.tiers.split(","))
    unknown = selected - {tier[0] for tier in TIERS}
    if unknown:
        raise SystemExit(f"unknown tier(s): {', '.join(sorted(unknown))}")

    summaries = []
    for tier, depth, samples in TIERS:
        if tier not in selected:
            continue
        print(f"{args.label}: {tier} depth {depth} / {samples} samples, "
              f"{args.games} games over {args.shards} shards", flush=True)
        summary = run_tier(
            binary, tier, depth, samples, args.games, args.shards,
            args.seed, root, min(args.overlap, args.shards),
        )
        summaries.append(summary)
        print(
            f"  {summary['games_per_second']:.2f} games/s, "
            f"{summary['wall_seconds']:.1f}s wall, "
            f"peak RSS {summary['max_rss_bytes'] / 1024 / 1024:.1f} MiB",
            flush=True,
        )

    summary_path = root / "summary.csv"
    fieldnames = list(summaries[0].keys()) if summaries else []
    with summary_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(summaries)
    (root / "config.json").write_text(
        json.dumps({
            "label": args.label,
            "binary": str(binary),
            "games_per_tier": args.games,
            "shards": args.shards,
            "overlap": args.overlap,
            "seed": args.seed,
            "tiers": summaries,
        }, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"wrote {summary_path}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
