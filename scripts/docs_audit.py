#!/usr/bin/env python3
"""Documentation closeout gate for IsolynV2.0.

This is the gate that OPS-10 in docs/history/fix-log.md reported as missing and
therefore SKIPPED. It checks the properties the documentation architecture
actually claims, so a closeout can report a real verdict instead of a manual
review.

Checks
------
1. link-resolution   Every relative markdown link resolves to a file.
2. path-resolution   Every `docs/...` path mentioned in backticks resolves.
3. status-headers    Every living document declares a Status line near the top.
4. register          Every document under docs/ appears in docs/README.md.
5. banners           Every document under docs/history/ declares its provenance.
6. stale-numbers     Known-superseded figures do not appear in living documents.

Exit status is 0 only when every check passes. Fenced code blocks are ignored,
because they legitimately contain C++/Swift syntax that looks like markdown.

Usage:  python3 scripts/docs_audit.py [-v]
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DOCS = ROOT / "docs"
INDEX = DOCS / "README.md"

LIVING_DIRS = ("architecture", "engineering", "design", "subsystems", "roadmaps")
GENERATED_DIRS = ("graphify-out",)
SKIP_DIRS = {".git", "build", ".build", ".swiftpm", "graphify-out", "node_modules", ".freebuff"}

# Figures that were measured wrong at some point and are now corrected. If one
# reappears in a living document, the documentation has regressed.
STALE_NUMBERS = [
    "426 checks", "426/426",
    "68 tests", "494 checks", "95 checks",
    "380 checks", "68 checks",
    "3,766", "5,869", "20,284", "1,640",
    "is now **directionally monotonic**",
]

LINK_RE = re.compile(r"\]\(([^)\s]+)\)")
# Any repo-relative path in backticks that names a real file. Glob patterns
# (containing *) are ignored: they are queries, not references.
CODE_PATH_RE = re.compile(
    r"`((?:docs|Sources|Tests|scripts|lab|tools|Accelerator|Assets)/[^`\n\s]+?\."
    r"(?:md|pdf|swift|cpp|hpp|h|sh|py|plist|json|icns|png))`"
)


def strip_fences(text: str) -> str:
    out, fenced = [], False
    for line in text.splitlines():
        if line.lstrip().startswith("```"):
            fenced = not fenced
            out.append("")
            continue
        out.append("" if fenced else line)
    return "\n".join(out)


def all_docs() -> list[Path]:
    found = []
    for path in ROOT.rglob("*.md"):
        if any(part in SKIP_DIRS for part in path.relative_to(ROOT).parts):
            continue
        found.append(path)
    return sorted(found)


def main() -> int:
    verbose = "-v" in sys.argv
    failures: dict[str, list[str]] = {
        "link-resolution": [],
        "path-resolution": [],
        "status-headers": [],
        "register": [],
        "banners": [],
        "stale-numbers": [],
    }
    docs = all_docs()
    index_text = strip_fences(INDEX.read_text(encoding="utf-8")) if INDEX.exists() else ""

    for path in docs:
        rel = path.relative_to(ROOT).as_posix()
        raw = path.read_text(encoding="utf-8")
        text = strip_fences(raw)

        # 1. relative links
        for target in LINK_RE.findall(text):
            if target.startswith(("http://", "https://", "mailto:", "#")):
                continue
            resolved = (path.parent / target.split("#")[0]).resolve()
            if not resolved.exists():
                failures["link-resolution"].append(f"{rel} -> {target}")

        # 2. repo paths written in backticks
        for target in CODE_PATH_RE.findall(text):
            if "*" in target or "<" in target or "{" in target:
                continue
            if not (ROOT / target).exists():
                failures["path-resolution"].append(f"{rel} -> {target}")

        # 3. status header on living documents
        parts = path.relative_to(DOCS).parts if DOCS in path.parents else ()
        if parts and parts[0] in LIVING_DIRS:
            head = "\n".join(raw.splitlines()[:12]).lower()
            if "status:" not in head:
                failures["status-headers"].append(rel)

        # 4. register entry for anything under docs/
        if parts and rel != "docs/README.md":
            docs_relative = "/".join(parts)
            if docs_relative not in index_text and rel not in index_text:
                failures["register"].append(rel)

        # 5. provenance banner for history
        if parts and parts[0] == "history":
            head = "\n".join(raw.splitlines()[:12]).lower()
            if not any(k in head for k in ("historical", "status:", "completed plan", "retired")):
                failures["banners"].append(rel)

        # 6. stale figures in living documents
        if parts and parts[0] in LIVING_DIRS or rel == "README.md":
            for fig in STALE_NUMBERS:
                if fig in text:
                    failures["stale-numbers"].append(f"{rel}: {fig!r}")

    total = sum(len(v) for v in failures.values())
    print("Documentation closeout gate")
    print(f"  documents scanned : {len(docs)}")
    print(f"  living dirs       : {', '.join(LIVING_DIRS)}")
    for name, hits in failures.items():
        status = "PASS" if not hits else f"FAIL ({len(hits)})"
        print(f"  {name:<18}: {status}")
        if hits and (verbose or name != "stale-numbers"):
            for h in hits[:20]:
                print(f"      {h}")
    print()
    if total:
        print(f"RESULT: FAIL — {total} documentation issue(s)")
        return 1
    print("RESULT: PASS — links, paths, status headers, register, banners and figures are consistent")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
