#!/usr/bin/env python3
"""Fit the evaluation weights to outcomes instead of guessing them.

Every self-play decision row records the eight evaluation terms from the acting
player's point of view, and every round records who won it. That is a supervised
dataset: a logistic model of "this side wins the round" over those eight terms
gives each term a coefficient, and a coefficient is a weight the engine can use.

The output is reported three ways because they answer different questions:

- raw coefficient: change in log-odds per unit of the term
- contribution sd: coefficient x the term's standard deviation -- how much this
  term actually moves the verdict in real positions, which is the only fair way
  to compare a +-1000 threat term with a 0..7 tempo term
- normalised weight: coefficients rescaled so expectedValue = 1, which is the
  shape the engine's own --weights flag consumes

Standard library only; deterministic.

Usage:
    python3 scripts/fit_weights.py lab/data/*.csv [--json PATH] [--l2 0.01]
"""

from __future__ import annotations

import csv
import glob
import json
import math
import sys
from pathlib import Path

# Harness names, in engine order.
FEATURES = [
    ("mobility", "mobility"),
    ("blocking", "blocking"),
    ("expectedValue", "expected_value"),
    ("closingOpportunity", "closing_opportunity"),
    ("winThreat", "win_threat"),
    ("pipControl", "pip_control"),
    ("tempo", "tempo"),
    ("teamSupport", "team_support"),
]


def load_samples(paths: list[Path]) -> tuple[list[list[float]], list[float]]:
    features: list[list[float]] = []
    labels: list[float] = []
    for path in paths:
        try:
            handle = path.open(newline="", encoding="utf-8")
        except OSError:
            continue
        with handle:
            rows = csv.DictReader(handle)
            per_game: dict[tuple[str, str], tuple[int, int]] = {}
            for row in rows:
                try:
                    player = int(row["player"])
                    game = (path.name, row["game"])
                except (KeyError, TypeError, ValueError):
                    continue
                if game not in per_game:
                    try:
                        count = int(row["participant_count"])
                        sides = [int(row[f"participant_side{p}"]) for p in range(count)]
                        scores = [int(row[f"participant_score{p}"] or 0) for p in range(count)]
                    except (KeyError, TypeError, ValueError):
                        per_game[game] = (0, 0)
                    else:
                        a = b = None
                        for p in range(count):
                            if sides[p] == 0:
                                a = scores[p]
                            elif sides[p] == 1:
                                b = scores[p]
                        per_game[game] = (0 if a is None else a, 0 if b is None else b)
                a, b = per_game[game]
                try:
                    values = [float(row[column] or 0.0) for _, column in FEATURES]
                except (KeyError, TypeError, ValueError):
                    continue
                # A draw is a half-result, not a missing value: soft labels keep
                # the 20-25% of closed rounds in the fit instead of dropping them.
                if a == b:
                    label = 0.5
                else:
                    try:
                        side = int(row[f"participant_side{player}"])
                    except (KeyError, TypeError, ValueError):
                        continue
                    if side == 0:
                        label = 1.0 if a > b else 0.0
                    elif side == 1:
                        label = 1.0 if b > a else 0.0
                    else:
                        continue
                features.append(values)
                labels.append(label)
    return features, labels


def standardise(features: list[list[float]]) -> tuple[list[list[float]], list[float], list[float]]:
    count = len(features)
    width = len(features[0])
    means = [sum(row[k] for row in features) / count for k in range(width)]
    sds = []
    for k in range(width):
        variance = sum((row[k] - means[k]) ** 2 for row in features) / max(1, count - 1)
        sds.append(math.sqrt(variance) if variance > 0 else 1.0)
    scaled = [[(row[k] - means[k]) / sds[k] for k in range(width)] for row in features]
    return scaled, means, sds


def subsample(features: list[list[float]], labels: list[float],
              limit: int) -> tuple[list[list[float]], list[float]]:
    """Deterministic stride sample: same input always gives the same fit."""
    if len(features) <= limit:
        return features, labels
    stride = len(features) / float(limit)
    picked_features = []
    picked_labels = []
    index = 0.0
    while int(index) < len(features) and len(picked_features) < limit:
        i = int(index)
        picked_features.append(features[i])
        picked_labels.append(labels[i])
        index += stride
    return picked_features, picked_labels


def fit(features: list[list[float]], labels: list[float], l2: float,
        iterations: int = 400, rate: float = 1.0) -> tuple[list[float], float, float]:
    width = len(features[0])
    weights = [0.0] * width
    bias = 0.0
    count = len(features)
    loss = 0.0
    for _ in range(iterations):
        grad = [0.0] * width
        grad_bias = 0.0
        loss = 0.0
        for row, label in zip(features, labels):
            score = bias + sum(w * x for w, x in zip(weights, row))
            score = max(-35.0, min(35.0, score))
            prediction = 1.0 / (1.0 + math.exp(-score))
            error = prediction - label
            for k in range(width):
                grad[k] += error * row[k]
            grad_bias += error
            p = min(max(prediction, 1e-12), 1.0 - 1e-12)
            loss -= label * math.log(p) + (1.0 - label) * math.log(1.0 - p)
        for k in range(width):
            weights[k] -= rate * (grad[k] / count + l2 * weights[k])
        bias -= rate * grad_bias / count
    return weights, bias, loss / count


def auc(features: list[list[float]], labels: list[float],
        weights: list[float], bias: float) -> float:
    """Rank-based (Mann-Whitney) AUC with tie handling, O(n log n)."""
    scored = []
    for row, label in zip(features, labels):
        if label == 0.5:
            continue
        scored.append((bias + sum(w * x for w, x in zip(weights, row)), label))
    positives = sum(1 for _, label in scored if label == 1.0)
    negatives = len(scored) - positives
    if not positives or not negatives:
        return float("nan")
    scored.sort()
    rank_sum = 0.0
    index = 0
    while index < len(scored):
        end = index
        while end + 1 < len(scored) and scored[end + 1][0] == scored[index][0]:
            end += 1
        average_rank = (index + end) / 2.0 + 1.0
        for position in range(index, end + 1):
            if scored[position][1] == 1.0:
                rank_sum += average_rank
        index = end + 1
    return (rank_sum - positives * (positives + 1) / 2.0) / (positives * negatives)


def main(argv: list[str]) -> int:
    patterns = [arg for arg in argv[1:] if not arg.startswith("--")]
    if not patterns:
        print(__doc__.strip())
        return 2
    paths: list[Path] = []
    for pattern in patterns:
        matched = [Path(p) for p in glob.glob(pattern)]
        paths.extend(matched if matched else [Path(pattern)])
    json_out = Path(argv[argv.index("--json") + 1]) if "--json" in argv else None
    l2 = float(argv[argv.index("--l2") + 1]) if "--l2" in argv else 0.01
    limit = int(argv[argv.index("--max-rows") + 1]) if "--max-rows" in argv else 40_000

    features, labels = load_samples(paths)
    total = len(features)
    if total < 200:
        print(f"only {total} usable decisions; need at least 200")
        return 1
    features, labels = subsample(features, labels, limit)
    scaled, means, sds = standardise(features)
    weights, bias, loss = fit(scaled, labels, l2)
    quality = auc(scaled, labels, weights, bias)

    raw = [w / sd for w, sd in zip(weights, sds)]
    contributions = [w * sd for w, sd in zip(weights, sds)]
    positive = sum(1 for label in labels if label == 1.0) / len(labels)

    print(f"decisions: {len(features)} (sampled from {total})  files: {len(paths)}")
    print(f"win rate for the acting side: {positive:.4f}")
    print(f"log-loss: {loss:.5f}   AUC: {quality:.4f}")
    print()
    print(f"{'term':<20}{'raw coef':>12}{'contribution sd':>18}{'normalised':>13}")
    print("-" * 63)
    anchor = raw[2]  # expectedValue
    for (name, _), coefficient, contribution in zip(FEATURES, raw, contributions):
        normalised = coefficient / anchor if abs(anchor) > 1e-12 else float("nan")
        print(f"{name:<20}{coefficient:>12.5f}{contribution:>18.4f}{normalised:>13.3f}")

    usable = all(math.isfinite(c) for c in contributions)
    if usable and abs(anchor) > 1e-9:
        text = ",".join(f"{name}={coefficient / anchor:.4f}"
                        for (name, _), coefficient in zip(FEATURES, raw))
        print(f"\nharness weights (expectedValue = 1):\n  --weights \"{text}\"")
    else:
        print("\nexpectedValue carries no signal; no normalised weight set is meaningful")

    if json_out is not None:
        json_out.parent.mkdir(parents=True, exist_ok=True)
        json_out.write_text(json.dumps({
            "decisions": len(features),
            "auc": quality,
            "log_loss": loss,
            "features": [{"term": name, "raw": coefficient, "contribution_sd": contribution}
                         for (name, _), coefficient, contribution in zip(FEATURES, raw, contributions)],
        }, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print(f"\nwrote {json_out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
