#!/usr/bin/env python3
"""Rulebook gate for IsolynV2.0.

docs/rules/RULEBOOK.md is the top authority in this project: it defines the
game, and the code is judged against it. A rulebook nobody checks is
decoration, so this gate refuses the build unless every rule is real:

Checks
------
1. ids              Every row is R-NN, unique, and numbered without gaps.
2. status           Status is one of ENFORCED / VARIANT / GAP / OPEN.
3. code-anchors     ENFORCED and VARIANT rules name code files that exist.
4. assertions       ENFORCED and VARIANT rules name `path :: section` anchors
                    whose file exists and whose text contains that section.
5. known-gaps       Every GAP and OPEN rule is listed under "Known gaps", and
                    every entry there names a rule that exists.
6. no-silent-holes  GAP/OPEN rules carry no assertion anchor (a hole is
                    declared, never papered over).

The rulebook is allowed to contain GAP and OPEN rules -- but only visibly, and
`--strict` fails if any remain, so raising the bar is a one-flag decision.

Usage:  python3 scripts/rules_audit.py [--strict] [-v] [--rulebook PATH]

`--rulebook` exists so the gate can be tested against a deliberately broken
copy: a gate that has never rejected anything is not known to work.

Exit status is 0 only when every check passes.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RULEBOOK = ROOT / "docs" / "rules" / "RULEBOOK.md"

STATUSES = {"ENFORCED", "VARIANT", "GAP", "OPEN"}
GAP_STATUSES = {"GAP", "OPEN"}
ROW_RE = re.compile(r"^\|\s*(R-\d{2})\s*\|")
ID_RE = re.compile(r"R-\d{2}")


def cells(line: str) -> list[str]:
    """Split a markdown table row into its cells."""
    return [c.strip() for c in line.strip().strip("|").split("|")]


def anchor_of(cell: str) -> tuple[str, str] | None:
    """Interpret `path :: section` as (path, section)."""
    text = cell.strip().strip("`")
    if "::" not in text:
        return None
    path, _, section = text.partition("::")
    return path.strip().strip("`"), section.strip().strip("`")


def main() -> int:
    verbose = "-v" in sys.argv
    strict = "--strict" in sys.argv
    rulebook = RULEBOOK
    if "--rulebook" in sys.argv:
        override = sys.argv[sys.argv.index("--rulebook") + 1]
        rulebook = Path(override).resolve()

    if not rulebook.exists():
        print(f"Rulebook gate\n  missing: {rulebook}")
        print("RESULT: FAIL — the rulebook does not exist")
        return 1

    raw = rulebook.read_text(encoding="utf-8")
    lines = raw.splitlines()

    failures: dict[str, list[str]] = {
        "ids": [],
        "status": [],
        "code-anchors": [],
        "assertions": [],
        "known-gaps": [],
        "no-silent-holes": [],
    }

    rules: dict[str, dict[str, str]] = {}
    order: list[str] = []

    for line in lines:
        if not ROW_RE.match(line):
            continue
        row = cells(line)
        if len(row) < 5:
            failures["ids"].append(f"malformed row (needs 5 cells): {line[:80]}")
            continue
        rid, text, status, code, assertion = row[0], row[1], row[2], row[3], row[4]
        if rid in rules:
            failures["ids"].append(f"{rid}: duplicate id")
            continue
        rules[rid] = {
            "text": text,
            "status": status,
            "code": code,
            "assertion": assertion,
        }
        order.append(rid)

    if not rules:
        failures["ids"].append("no rule rows found — the table is missing or malformed")

    # 1. sequential, gap-free numbering
    for expected, rid in enumerate(order, start=1):
        want = f"R-{expected:02d}"
        if rid != want:
            failures["ids"].append(f"expected {want}, found {rid} (numbering must be contiguous)")
            break

    # 2..4, 6. per-rule checks
    for rid in order:
        rule = rules[rid]
        status = rule["status"]

        if status not in STATUSES:
            failures["status"].append(f"{rid}: unknown status {status!r}")
            continue

        code = rule["code"].strip().strip("`")
        code_paths = re.findall(r"`(Sources/[^`]+)`", rule["code"])
        if status in {"ENFORCED", "VARIANT"}:
            if not code_paths:
                failures["code-anchors"].append(f"{rid}: no code anchor in backticks")
            for path in code_paths:
                if not (ROOT / path).exists():
                    failures["code-anchors"].append(f"{rid}: {path} does not exist")

        assertion = rule["assertion"].strip()
        parsed = anchor_of(assertion)
        if status in {"ENFORCED", "VARIANT"}:
            if parsed is None:
                failures["assertions"].append(
                    f"{rid}: no `path :: section` assertion anchor"
                )
            else:
                path, section = parsed
                target = ROOT / path
                if not target.exists():
                    failures["assertions"].append(f"{rid}: {path} does not exist")
                elif section not in target.read_text(encoding="utf-8"):
                    failures["assertions"].append(
                        f"{rid}: {path} does not contain {section!r}"
                    )
        elif status in GAP_STATUSES:
            # 6. a declared hole must not pretend to be asserted
            if parsed is not None:
                failures["no-silent-holes"].append(
                    f"{rid}: status {status} must not carry an assertion anchor"
                )

    # 5. known-gaps section
    known: set[str] = set()
    in_gaps = False
    for line in lines:
        if line.startswith("## Known gaps"):
            in_gaps = True
            continue
        if in_gaps and line.startswith("## "):
            break
        if in_gaps:
            known.update(ID_RE.findall(line))

    for rid in order:
        if rules[rid]["status"] in GAP_STATUSES and rid not in known:
            failures["known-gaps"].append(f"{rid}: {rules[rid]['status']} rule is not listed under Known gaps")
    for rid in sorted(known):
        if rid not in rules:
            failures["known-gaps"].append(f"Known gaps names {rid}, which is not a rule")

    counts = {s: sum(1 for r in rules.values() if r["status"] == s) for s in sorted(STATUSES)}
    total_issues = sum(len(v) for v in failures.values())

    print("Rulebook gate")
    try:
        shown = rulebook.relative_to(ROOT).as_posix()
    except ValueError:
        shown = str(rulebook)
    print(f"  rulebook        : {shown}")
    print(f"  rules           : {len(rules)}")
    for status in ("ENFORCED", "VARIANT"):
        print(f"  {status.lower():<15}: {counts[status]}")
    print(f"  gaps            : {counts['GAP']}")
    print(f"  open            : {counts['OPEN']}")
    for name, hits in failures.items():
        state = "PASS" if not hits else f"FAIL ({len(hits)})"
        print(f"  {name:<15} : {state}")
        if hits and verbose:
            for h in hits:
                print(f"      {h}")
    print()

    if total_issues:
        if not verbose:
            for name, hits in failures.items():
                for h in hits[:8]:
                    print(f"  [{name}] {h}")
        print(f"RESULT: FAIL — {total_issues} rulebook issue(s)")
        return 1

    if strict and (counts["GAP"] or counts["OPEN"]):
        print(
            "RESULT: FAIL — strict mode: "
            f"{counts['GAP']} gap(s) and {counts['OPEN']} open rule(s) remain"
        )
        return 1

    print(
        "RESULT: PASS — every enforced rule names real code and a real assertion; "
        f"{counts['GAP'] + counts['OPEN']} declared hole(s)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
