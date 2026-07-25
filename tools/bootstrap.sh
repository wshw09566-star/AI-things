#!/usr/bin/env bash
set -euo pipefail
version=4.7.1
version_re=${version//./\\.}
archive="Godot_v${version}-stable_linux.x86_64.zip"
binary_name="Godot_v${version}-stable_linux.x86_64"
url="https://github.com/godotengine/godot/releases/download/${version}-stable/${archive}"
install_dir=/opt/godot
link=/usr/local/bin/godot

if [[ $(id -u) -eq 0 ]]; then
  SUDO=()
else
  command -v sudo >/dev/null || { echo "bootstrap requires root or sudo" >&2; exit 1; }
  SUDO=(sudo)
fi

# Idempotent: a correct existing install is left alone.
if [[ -x "$link" ]] && "$link" --version 2>/dev/null | grep -qE "^${version_re}\.stable\."; then
  printf 'Godot %s already installed at %s\n' "$version" "$link"
  "$link" --version
  exit 0
fi

"${SUDO[@]}" apt-get update -qq
"${SUDO[@]}" env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
  curl unzip xvfb xauth mesa-utils libgl1-mesa-dri libglx-mesa0 python3-pil
tmp_zip=$(mktemp /tmp/godot-XXXXXXXX.zip)
cleanup() { rm -f "$tmp_zip"; }
trap cleanup EXIT
curl -fL --retry 3 -o "$tmp_zip" "$url"
"${SUDO[@]}" mkdir -p "$install_dir"
"${SUDO[@]}" unzip -qo "$tmp_zip" -d "$install_dir"

# Select the exact expected binary instead of `find ... | head -n1`, which is
# both order-dependent (a stale other-version binary could win) and prone to
# SIGPIPE failing the whole script under `set -o pipefail`.
binary="$install_dir/$binary_name"
[[ -f "$binary" ]] || { echo "expected binary missing after unzip: $binary" >&2; exit 1; }
"${SUDO[@]}" chmod +x "$binary"
"${SUDO[@]}" ln -sfn "$binary" "$link"
"$link" --version | grep -qE "^${version_re}\.stable\." || {
  echo "installed engine is not Godot ${version} stable" >&2
  exit 1
}
"$link" --version
