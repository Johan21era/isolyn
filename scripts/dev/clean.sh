#!/usr/bin/env bash
# One-command restore to steady-state folder size (owner directive, OPS-03).
#
# Deletes ONLY regenerable compiler output:
#   .build/   -- SwiftPM cache (recreated by any swift build/test)
#   build/    -- test binaries, sanitizer objects (recreated by the run_*.sh scripts)
#   .DS_Store -- Finder cruft
#
# Sources, tests, docs, git history are NEVER touched.
# Both paths are gitignored, so this cannot lose version-controlled work.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

before=$(du -sh . 2>/dev/null | cut -f1)
rm -rf .build build
find . -name ".DS_Store" -not -path "./.git/*" -delete 2>/dev/null || true
after=$(du -sh . 2>/dev/null | cut -f1)

echo "cleaned: $before -> $after"
echo "verify integrity anytime with: git status && ./scripts/ci/test_engine.sh"
