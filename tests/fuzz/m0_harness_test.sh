#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$ROOT"
tmp=$(mktemp -d)
cleanup() { rm -rf "$tmp"; }
trap cleanup EXIT

printf '%s\n' '[FUZZ M0] API drift must fail closed'
mkdir -p "$tmp/project"
printf 'extends Spatial\nfunc old_api(): yield(self, "done")\n' > "$tmp/project/probe.gd"
if python3 tools/api_drift_lint.py "$tmp/project" >"$tmp/drift.out" 2>"$tmp/drift.err"; then
  echo 'API drift probe was accepted' >&2
  exit 1
fi
grep -q 'API DRIFT LINT FAILED' "$tmp/drift.err"

printf '%s\n' '[FUZZ M0] doctor must reject a missing engine'
if GODOT_BIN="$tmp/missing-godot" ./tools/doctor.sh >"$tmp/doctor.out" 2>"$tmp/doctor.err"; then
  echo 'Doctor accepted a missing Godot binary' >&2
  exit 1
fi
grep -q 'Godot missing or not executable' "$tmp/doctor.err"

printf '%s\n' '[FUZZ M0] stale lock file must not remain locked'
stale="$tmp/stale.lock"
touch "$stale"
exec 7>"$stale"
flock -n 7
flock -u 7

printf '%s\n' '[FUZZ M0] live lock must serialize contenders'
live="$tmp/live.lock"
(
  exec 8>"$live"
  flock 8
  sleep 2
) & holder=$!
sleep 0.2
start=$(date +%s)
(
  exec 9>"$live"
  flock -w 10 9
)
elapsed=$(( $(date +%s) - start ))
wait "$holder"
if [ "$elapsed" -lt 1 ]; then
  echo "Lock contender did not wait: ${elapsed}s" >&2
  exit 1
fi
printf 'M0 HARNESS ADVERSARIAL PASS (%ss serialized wait)\n' "$elapsed"
