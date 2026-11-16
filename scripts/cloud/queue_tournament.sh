#!/usr/bin/env bash
# Launch prepared tournament sessions as Kaggle frees concurrent-kernel slots.
#
# Kaggle allows only a small number of simultaneously running CPU kernels. A push
# beyond that exits zero without creating anything -- `lab cloud push` now catches
# that and fails, but retrying blind would also re-upload a dataset version on
# every attempt. So this waits for one of the already-pushed kernels to leave
# RUNNING before spending a single push.
#
# Usage: scripts/cloud/queue_tournament.sh [run-id] [session ...]
set -uo pipefail

cd "$(dirname "$0")/../.." || exit 1

run_id="${1:-overdrive-rr6-d8x64-n60000-s7000}"
shift || true
if [ "$#" -gt 0 ]; then
  sessions=("$@")
else
  sessions=(0005 0006 0007 0008 0009 0010 0011 0012 0013 0014)
fi

ledger="lab/data/cloud/${run_id}/ledger.json"
poll_seconds="${QUEUE_POLL_SECONDS:-300}"

pushed_kernel_ids() {
  python3 - "$ledger" <<'PY'
import json, sys
try:
    ledger = json.load(open(sys.argv[1]))
except (OSError, ValueError):
    sys.exit(0)
for entry in ledger.get("sessions", {}).values():
    kernel_id = entry.get("kernel_id")
    if entry.get("pushed_at") and kernel_id:
        print(kernel_id)
PY
}

wait_for_slot() {
  while true; do
    while read -r kernel_id; do
      [ -n "$kernel_id" ] || continue
      if ! kaggle kernels status "$kernel_id" 2>/dev/null | grep -q "KernelWorkerStatus.RUNNING"; then
        return 0
      fi
    done < <(pushed_kernel_ids)
    sleep "$poll_seconds"
  done
}

echo "$(date -u +%FT%TZ) queue: run $run_id, sessions ${sessions[*]}"
for session in "${sessions[@]}"; do
  wait_for_slot
  if ./scripts/lab cloud push "$run_id" --session "$session" --yes; then
    echo "$(date -u +%FT%TZ) $session: launched"
  else
    echo "$(date -u +%FT%TZ) $session: push refused; retrying after the next slot"
    sleep "$poll_seconds"
    continue
  fi
done
echo "$(date -u +%FT%TZ) queue: all requested sessions launched"
