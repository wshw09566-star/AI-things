#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
export HOME=${HOLLOW_SURVEY_HOME:-/tmp/hollow-survey-home}
mkdir -p "$HOME"
GODOT_BIN=${GODOT_BIN:-/usr/local/bin/godot}
LOCK_FILE=${HOLLOW_SURVEY_LOCK:-/tmp/hollow-survey-godot.lock}
AGENT_NAME=${HOLLOW_SURVEY_AGENT:-producer}
case "$AGENT_NAME" in
  engineer) DISPLAY_NO=91 ;;
  design) DISPLAY_NO=92 ;;
  qa) DISPLAY_NO=93 ;;
  infra|bug-hunter) DISPLAY_NO=94 ;;
  *) DISPLAY_NO=90 ;;
esac

usage() { echo "usage: tools/run.sh test|capture [--output PATH] [--width N] [--height N]" >&2; }
need_value() { # need_value <flag> <remaining-arg-count>
  (( $2 >= 2 )) || { echo "missing value for $1" >&2; usage; exit 64; }
}

command=${1:-}
[[ -n "$command" ]] || { usage; exit 64; }
shift

# Arguments are validated BEFORE taking the global Godot lock, so a usage error
# returns 64 immediately instead of blocking up to 120s behind another agent.
output="artifacts/m0-smoke.png"; width=640; height=360
case "$command" in
  test) : ;;
  capture)
    while (($#)); do
      case "$1" in
        --output) need_value "$1" "$#"; output=$2; shift 2 ;;
        --width) need_value "$1" "$#"; width=$2; shift 2 ;;
        --height) need_value "$1" "$#"; height=$2; shift 2 ;;
        *) echo "unknown capture option: $1" >&2; exit 64 ;;
      esac
    done
    [[ "$width" =~ ^[0-9]+$ && "$height" =~ ^[0-9]+$ ]] || { echo "invalid dimensions" >&2; exit 64; }
    [[ -n "$output" ]] || { echo "empty output path" >&2; exit 64; }
    ;;
  *) echo "unknown command: $command" >&2; usage; exit 64 ;;
esac

exec 9>"$LOCK_FILE"
flock -w 120 9 || { echo "Timed out waiting for Godot lock: $LOCK_FILE" >&2; exit 73; }

case "$command" in
  test)
    # Import once so a clean clone has the GDScript global class cache required by GdUnit4.
    GODOT_SILENCE_ROOT_WARNING=1 "$GODOT_BIN" --headless --editor --path . --quit-after 1 >/dev/null
    GODOT_SILENCE_ROOT_WARNING=1 "$GODOT_BIN" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a tests "$@"
    bash tests/fuzz/m0_harness_test.sh
    ;;
  capture)
    mkdir -p "$(dirname "$output")"
    rm -f "$output"
    xvfb-run -n "$DISPLAY_NO" --server-args="-screen 0 ${width}x${height}x24 -nolisten tcp" \
      env LIBGL_ALWAYS_SOFTWARE=1 MESA_LOADER_DRIVER_OVERRIDE=llvmpipe \
      env GODOT_SILENCE_ROOT_WARNING=1 "$GODOT_BIN" --path . --resolution "${width}x${height}" --position 0,0 -- --output "$output"
    [[ -s "$output" ]] || { echo "capture missing: $output" >&2; exit 1; }
    ;;
esac
