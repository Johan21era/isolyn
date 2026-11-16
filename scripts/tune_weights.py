#!/usr/bin/env python3
"""Tune evaluation weights against wins instead of against correlation.

E-104 established that a weight set fitted to "who won from this position" loses
9 Elo when transplanted into search, because predicting an outcome and ranking
moves are different problems. The only objective that cannot be gamed that way is
the one the engine is judged by: play games, count wins.

This drives the self-play harness with SPSA -- two evaluations per iteration at
theta +/- c*delta, both with the *same* seeds so the comparison is paired and the
deal noise cancels instead of dominating. Every evaluation is appended to a JSONL
ledger, so a campaign can be stopped, inspected and resumed without losing work.

Anchors: winThreat and expectedValue stay at 1.0. They are the two terms the
engine's strength is known to rest on, and letting a noisy tuner move them turns
a local search into a lottery.

Usage:
    # one iteration, 1000 paired rounds per side of the gradient
    python3 scripts/tune_weights.py --rounds 1000 --iterations 1

    # resume a campaign, inspect the ledger
    python3 scripts/tune_weights.py --rounds 3000 --iterations 5 --state lab/data/tuning/spsa.jsonl
"""

from __future__ import annotations

import csv
import json
import math
import random
import subprocess
import sys
import time
from pathlib import Path

HARNESS = Path("tools/selfplay/build/selfplay")

# name, start, low, high. winThreat/expectedValue deliberately absent: anchors.
PARAMETERS = [
    ("mobility", 1.0, 0.05, 12.0),
    ("blocking", 1.0, 0.0, 8.0),
    ("pipControl", 0.5, 0.0, 12.0),
    ("closingOpportunity", 1.0, 0.0, 8.0),
]


def weights_text(theta: list[float]) -> str:
    parts = [f"expectedValue=1.0", "winThreat=1.0"]
    for (name, _, _, _), value in zip(PARAMETERS, theta):
        parts.append(f"{name}={value:.4f}")
    return ",".join(parts)


def round_scores(path: Path) -> list[float]:
    """One score per round, from side 0's point of view."""
    seen: dict[int, float] = {}
    with path.open(newline="", encoding="utf-8") as handle:
        for row in csv.DictReader(handle):
            try:
                game = int(row["game"])
            except (KeyError, TypeError, ValueError):
                continue
            if game in seen:
                continue
            try:
                count = int(row["participant_count"])
            except (KeyError, TypeError, ValueError):
                continue
            a = b = None
            for p in range(count):
                try:
                    side = int(row[f"participant_side{p}"])
                    score = int(row[f"participant_score{p}"] or 0)
                except (KeyError, TypeError, ValueError):
                    continue
                if side == 0:
                    a = score
                elif side == 1:
                    b = score
            if a is None or b is None or a == b:
                seen[game] = 0.5
            else:
                seen[game] = 1.0 if a > b else 0.0
    return list(seen.values())


def play(theta: list[float], seed: int, rounds: int, depth: int, detections: int,
         output: Path) -> list[float]:
    command = [
        str(HARNESS),
        "--depth", str(depth), "--determinizations", str(detections),
        "--opponent-depth", str(depth), "--opponent-determinizations", str(detections),
        "--games", str(rounds), "--seed", str(seed),
        "--weights", weights_text(theta), "--output", str(output),
    ]
    subprocess.run(command, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return round_scores(output)


def main(argv: list[str]) -> int:
    def option(name: str, default: float) -> float:
        return float(argv[argv.index(name) + 1]) if name in argv else default

    rounds = int(option("--rounds", 1000))
    iterations = int(option("--iterations", 1))
    depth = int(option("--depth", 8))
    detections = int(option("--determinizations", 64))
    seed_base = int(option("--seed", 900))
    state_path = Path(argv[argv.index("--state") + 1]) if "--state" in argv \
        else Path("lab/data/tuning/spsa.jsonl")

    theta = [start for _, start, _, _ in PARAMETERS]
    history: list[dict] = []
    if state_path.exists():
        for line in state_path.read_text(encoding="utf-8").splitlines():
            if line.strip():
                history.append(json.loads(line))
        if history:
            theta = history[-1]["theta_next"]
            print(f"resumed at iteration {len(history)}: {weights_text(theta)}")

    state_path.parent.mkdir(parents=True, exist_ok=True)
    if not HARNESS.exists():
        print(f"harness missing at {HARNESS}; build it first")
        return 1

    rng = random.Random(seed_base)
    # SPSA gain sequences (Spall's recommended defaults).
    a, c, alpha, gamma, big_a = 0.6, 0.5, 0.602, 0.101, 10.0

    for step in range(iterations):
        index = len(history) + step
        delta = [rng.choice((-1.0, 1.0)) for _ in PARAMETERS]
        c_k = c / (step + 1 + big_a) ** gamma
        a_k = a / (step + 1 + big_a) ** alpha

        plus = [min(high, max(low, v + c_k * d))
                for (_, _, low, high), v, d in zip(PARAMETERS, theta, delta)]
        minus = [min(high, max(low, v - c_k * d))
                 for (_, _, low, high), v, d in zip(PARAMETERS, theta, delta)]

        seed = seed_base + index * 2  # paired: both sides see the same deals
        began = time.time()
        plus_scores = play(plus, seed, rounds, depth, detections,
                           Path(f"/tmp/spsa_{index}_plus.csv"))
        minus_scores = play(minus, seed, rounds, depth, detections,
                            Path(f"/tmp/spsa_{index}_minus.csv"))
        elapsed = time.time() - began

        # Paired difference: same deals, so only the weights differ.
        paired = [p - m for p, m in zip(plus_scores, minus_scores)]
        n = len(paired)
        mean = sum(paired) / n if n else 0.0
        variance = sum((x - mean) ** 2 for x in paired) / max(1, n - 1)
        error = math.sqrt(variance / n) if n else float("inf")

        gradient = [mean / (2.0 * c_k * d) if d else 0.0 for d in delta]
        next_theta = [min(high, max(low, v + a_k * g))
                      for (_, _, low, high), v, g in zip(PARAMETERS, theta, gradient)]

        record = {
            "iteration": index,
            "rounds": rounds,
            "seed": seed,
            "seconds": round(elapsed, 1),
            "theta": theta,
            "theta_next": next_theta,
            "delta": delta,
            "pair_mean": mean,
            "pair_se": error,
            "paired_elo": -400.0 * math.log10(1.0 / min(max(0.5 + mean / 2.0, 1e-9), 1 - 1e-9) - 1.0),
            "weights": weights_text(next_theta),
        }
        with state_path.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(record) + "\n")
        history.append(record)
        theta = next_theta

        print(f"[{index}] {elapsed:.0f}s  paired diff {mean:+.4f} (SE {error:.4f})  "
              f"-> {weights_text(theta)}")

    print(f"\nledger: {state_path}")
    print(f"best weights so far: {weights_text(theta)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
