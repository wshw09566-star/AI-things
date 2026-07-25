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
printf '%s\n' '[FUZZ M0] lint must not fail open when the checkout path contains an excluded name'
mkdir -p "$tmp/addons/checkout/src" "$tmp/.git-ish"
printf 'extends Spatial\nfunc f():\n\tyield(self, "x")\n' > "$tmp/addons/checkout/src/legacy.gd"
if python3 tools/api_drift_lint.py "$tmp/addons/checkout" >"$tmp/parts.out" 2>"$tmp/parts.err"; then
  echo 'Lint ignored drift because an ancestor directory was named addons' >&2
  exit 1
fi
grep -q 'API DRIFT LINT FAILED' "$tmp/parts.err"

printf '%s\n' '[FUZZ M0] lint must still skip in-repo vendor addons'
mkdir -p "$tmp/repo/addons/vendor"
printf 'extends Spatial\n' > "$tmp/repo/addons/vendor/legacy.gd"
python3 tools/api_drift_lint.py "$tmp/repo" >"$tmp/vendor.out" 2>&1 || { cat "$tmp/vendor.out" >&2; echo 'Lint should skip vendored addons' >&2; exit 1; }

printf '%s\n' '[FUZZ M0] lint must not false positive on valid Godot 4 code or prose'
mkdir -p "$tmp/modern"
cat > "$tmp/modern/modern.gd" <<'GD'
extends Node3D
# Reference: the Spatial audio and KinematicBody notes are Godot 3 history only.
@export var speed: int = 3
var caption := "Spatial survey, legacy Reference build"

func _ready() -> void:
	var node := preload("res://scenes/bootstrap.tscn").instantiate()
	node.tree_exited.connect(_on_done)
	await get_tree().process_frame
	get_viewport().set_input_as_handled()

func _on_done() -> void:
	pass
GD
python3 tools/api_drift_lint.py "$tmp/modern" >"$tmp/modern.out" 2>"$tmp/modern.err" || {
  cat "$tmp/modern.err" >&2
  echo 'Lint reported valid Godot 4 code as drift' >&2
  exit 1
}

printf '%s\n' '[FUZZ M0] lint self-test must assert per-pattern coverage'
python3 tools/api_drift_lint.py --self-test "$tmp/modern" >"$tmp/selftest.out" 2>&1
grep -q 'per-pattern fixtures' "$tmp/selftest.out"
grep -q 'negative fixtures' "$tmp/selftest.out"

printf '%s\n' '[FUZZ M0] run.sh must reject a missing option value with exit 64 and no lock wait'
runsh_start=$(date +%s)
set +e
HOLLOW_SURVEY_LOCK="$tmp/usage.lock" ./tools/run.sh capture --output >"$tmp/usage.out" 2>"$tmp/usage.err"
usage_status=$?
set -e
runsh_elapsed=$(( $(date +%s) - runsh_start ))
if [ "$usage_status" -ne 64 ]; then
  echo "run.sh missing-value exit was $usage_status, expected 64" >&2
  cat "$tmp/usage.err" >&2
  exit 1
fi
if [ "$runsh_elapsed" -ge 10 ]; then
  echo "run.sh validated arguments only after contending for the lock (${runsh_elapsed}s)" >&2
  exit 1
fi
grep -q 'missing value for --output' "$tmp/usage.err"

printf '%s\n' '[FUZZ M0] run.sh must reject unknown commands and options with exit 64'
set +e
HOLLOW_SURVEY_LOCK="$tmp/usage.lock" ./tools/run.sh bogus >/dev/null 2>&1
bogus_status=$?
HOLLOW_SURVEY_LOCK="$tmp/usage.lock" ./tools/run.sh capture --nope 1 >/dev/null 2>&1
bogus_option_status=$?
set -e
[ "$bogus_status" -eq 64 ] || { echo "unknown command exit was $bogus_status" >&2; exit 1; }
[ "$bogus_option_status" -eq 64 ] || { echo "unknown option exit was $bogus_option_status" >&2; exit 1; }

printf '%s\n' '[FUZZ M0] bootstrap must be idempotent on an already-correct install'
if [ -x /usr/local/bin/godot ] && /usr/local/bin/godot --version 2>/dev/null | grep -qE '^4\.7\.1\.stable\.'; then
  ./tools/bootstrap.sh >"$tmp/bootstrap.out" 2>"$tmp/bootstrap.err" || { cat "$tmp/bootstrap.err" >&2; echo 'bootstrap.sh failed on an already-correct install' >&2; exit 1; }
  grep -q 'already installed' "$tmp/bootstrap.out"
  grep -q '^4\.7\.1\.stable\.' "$tmp/bootstrap.out"
else
  echo 'SKIP bootstrap idempotency probe (no 4.7.1 install present)'
fi

printf 'M0 HARNESS ADVERSARIAL PASS (%ss serialized wait)\n' "$elapsed"
