#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
fail() { printf 'DOCTOR FAIL: %s\n' "$*" >&2; exit 1; }
for cmd in git python3 flock xvfb-run file; do command -v "$cmd" >/dev/null || fail "missing command: $cmd"; done
GODOT_BIN=${GODOT_BIN:-/usr/local/bin/godot}
[[ -x "$GODOT_BIN" ]] || fail "Godot missing or not executable at $GODOT_BIN"
version=$($GODOT_BIN --version)
[[ "$version" == 4.7.1.stable.* ]] || fail "expected Godot 4.7.1 stable, got $version"
[[ -f project.godot ]] || fail "project.godot missing"
[[ -f addons/gdUnit4.PINNED ]] || fail "GdUnit4 pin missing"
[[ -f addons/gdUnit4/plugin.cfg ]] || fail "GdUnit4 addon missing"
free_kb=$(df -Pk . | awk 'NR==2 {print $4}')
(( free_kb >= 1048576 )) || fail "less than 1 GiB free"
repo_bytes=$(du -sb . --exclude=.git --exclude=.godot | awk '{print $1}')
(( repo_bytes < 500000000 )) || fail "repository is >= 500 MB ($repo_bytes bytes)"
python3 tools/api_drift_lint.py --self-test .
printf 'Godot %s\n' "$version"
printf 'Repo bytes %s; free KiB %s\n' "$repo_bytes" "$free_kb"
printf 'DOCTOR OK\n'
