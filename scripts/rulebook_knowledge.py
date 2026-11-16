#!/usr/bin/env python3
"""How much of the rulebook does the engine actually USE?

`rules_audit.py` answers "is every rule implemented, with an assertion?". That is
a legality question. It is not a strength question: an engine can implement a rule
perfectly and never let it influence a single move.

This audit answers the second question, per rule, in three levels:

  LEGALITY_ONLY  the rule is implemented, but nothing on the decision path calls
                 its mechanism -- the engine obeys it and ignores it.
  PATH_VISIBLE   a file on the decision path enforces it, so it can affect search.
  VALUED         an evaluation term rewards or punishes the position the rule
                 describes, so the rule can change which move looks best.

The distinction between PATH_VISIBLE and VALUED is the one that matters: a rule the
search *obeys* but the evaluator does not *price* is obeyed at every node and never
sought. R-18 (the one-domino rule) is the clear example -- it constrains every
search node, and no term in the evaluation says "being in this situation is bad".

Symbol-level evidence is used where the rulebook names a symbol, because file-level
membership overstates: `GameState.cpp` is on the decision path for the simulator,
yet `privateLockedPair` (R-17) exists for the UI's private overlay.

Usage:
    python3 scripts/rulebook_knowledge.py [-v]
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RULEBOOK = ROOT / "docs" / "rules" / "RULEBOOK.md"

# Files whose behaviour determines what the engine plays. A rule enforced here can
# change a decision; a rule enforced only in the bridge, the app, or the dealer
# cannot.
DECISION_PATH = [
    "Sources/IsolynEngine/SearchEngine.cpp",
    "Sources/IsolynEngine/include/SearchEngine.hpp",
    "Sources/IsolynEngine/EvaluationEngine.cpp",
    "Sources/IsolynEngine/include/EvaluationEngine.hpp",
    "Sources/IsolynEngine/MoveGenerator.cpp",
    "Sources/IsolynEngine/GameState.cpp",
    "Sources/IsolynEngine/SimulationEngine.cpp",
    "Sources/IsolynEngine/BeliefState.cpp",
    "Sources/IsolynEngine/ProbabilityEngine.cpp",
]

# Rules whose content is rewarded or punished by a named evaluation term, with the
# reason. Hand-maintained on purpose: this is a claim about meaning, and a regex
# cannot make it. Every entry must name a term that exists in EvaluationWeights.
VALUED = {
    "R-02": ("winThreat, closingOpportunity", "emptying the hand and closing are priced directly"),
    "R-03": ("expectedValue", "the opponent's remaining pips are what a 1v1 win pays"),
    "R-05": ("expectedValue, teamSupport", "team totals and the partner's mobility"),
    "R-16": ("mobility", "a stuck player has fewer legal placements"),
    "R-19": ("expectedValue", "hand value is the sum of pips, double blank included"),
    "R-20": ("expectedValue", "a standard win pays the opponent's total, same as a close"),
    "R-11": ("mobility", "opening choice is searched as a placement like any other"),
}

# Mechanisms the search reimplements rather than calls. Static matching cannot see
# these, so they are recorded with their evidence; without them the audit would
# under-report the engine's real knowledge, and an audit that flatters the engine
# is worse than none.
PATH_OVERRIDES = {
    "R-15": ("SearchEngine root draw candidate",
             "Config::maxVoluntaryDraws makes a draw a competing root action"),
    "R-14": ("MatchController precondition",
             "forced draws are resolved before search sees the state"),
}

ROW_RE = re.compile(r"^\|\s*(R-\d{2})\s*\|")
CODE_RE = re.compile(r"`([^`]+)`")
SYMBOL_RE = re.compile(r"\(([A-Za-z_][A-Za-z0-9_]*)\)")


def read_cells(line: str) -> list[str]:
    return [cell.strip() for cell in line.strip().strip("|").split("|")]


def main() -> int:
    verbose = "-v" in sys.argv
    if not RULEBOOK.exists():
        print(f"missing rulebook: {RULEBOOK}")
        return 1

    path_text = {}
    for relative in DECISION_PATH:
        target = ROOT / relative
        if target.exists():
            path_text[relative] = target.read_text(encoding="utf-8", errors="ignore")

    rows = []
    for line in RULEBOOK.read_text(encoding="utf-8").splitlines():
        match = ROW_RE.match(line)
        if not match:
            continue
        cells = read_cells(line)
        if len(cells) < 4:
            continue
        rows.append({
            "id": cells[0],
            "rule": cells[1],
            "status": cells[2],
            "enforced": cells[3],
        })

    levels = {}
    evidence = {}
    for row in rows:
        if row["status"] != "ENFORCED":
            levels[row["id"]] = row["status"]
            continue
        cell = row["enforced"]
        symbols = SYMBOL_RE.findall(cell)
        files = [token for token in CODE_RE.findall(cell) if "/" in token]

        hits = []
        for symbol in symbols:
            for relative, text in path_text.items():
                if symbol in text:
                    hits.append(f"{symbol} in {relative}")

        if not hits:
            on_path = [f for f in files if any(f.endswith(Path(p).name) for p in DECISION_PATH)]
            if on_path:
                hits = [f"file {f}" for f in on_path]

        if row["id"] in PATH_OVERRIDES:
            symbol, why = PATH_OVERRIDES[row["id"]]
            hits = hits + [f"{symbol}: {why}"]

        if row["id"] in VALUED:
            levels[row["id"]] = "VALUED"
        elif hits:
            levels[row["id"]] = "PATH_VISIBLE"
        else:
            levels[row["id"]] = "LEGALITY_ONLY"
        evidence[row["id"]] = hits

    width = max(len(r["rule"]) for r in rows)
    print(f"{'rule':<6}{'level':<15}rule")
    print("-" * (6 + 15 + min(width, 60)))
    for row in rows:
        level = levels[row["id"]]
        text = row["rule"] if len(row["rule"]) <= 60 else row["rule"][:57] + "..."
        print(f"{row['id']:<6}{level:<15}{text}")
        if verbose:
            if row["id"] in VALUED:
                terms, why = VALUED[row["id"]]
                print(f"{'':<6}{'':<15}  priced by {terms}: {why}")
            for hit in evidence.get(row["id"], []):
                print(f"{'':<6}{'':<15}  {hit}")

    enforced = [r for r in rows if r["status"] == "ENFORCED"]
    counts = {}
    for row in enforced:
        counts[levels[row["id"]]] = counts.get(levels[row["id"]], 0) + 1

    print()
    print(f"rules: {len(rows)}   enforced: {len(enforced)}")
    for level in ("VALUED", "PATH_VISIBLE", "LEGALITY_ONLY"):
        print(f"  {level:<15}{counts.get(level, 0)}")
    unpriced = [r["id"] for r in enforced if levels[r["id"]] == "PATH_VISIBLE"]
    invisible = [r["id"] for r in enforced if levels[r["id"]] == "LEGALITY_ONLY"]
    print()
    print(f"obeyed but unpriced: {', '.join(unpriced) if unpriced else 'none'}")
    print(f"not on the decision path at all: {', '.join(invisible) if invisible else 'none'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
