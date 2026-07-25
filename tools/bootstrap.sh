#!/usr/bin/env bash
set -euo pipefail
version=4.7.1
archive="Godot_v${version}-stable_linux.x86_64.zip"
url="https://github.com/godotengine/godot/releases/download/${version}-stable/${archive}"
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq curl unzip xvfb xauth mesa-utils libgl1-mesa-dri libglx-mesa0
curl -fL --retry 3 -o "/tmp/$archive" "$url"
sudo mkdir -p /opt/godot
sudo unzip -qo "/tmp/$archive" -d /opt/godot
binary=$(find /opt/godot -maxdepth 1 -type f -name 'Godot*' | head -n1)
sudo chmod +x "$binary"
sudo ln -sf "$binary" /usr/local/bin/godot
/usr/local/bin/godot --version
