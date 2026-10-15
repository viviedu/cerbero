#!/bin/bash
# Diff the plugin set in a cerbero runtime tarball against a dome-os gstreamer-1.0 plugin directory.
set -euo pipefail
tarball="${1:?usage: plugin-diff.sh <runtime-tarball> <dome-os-plugin-dir>}"
domedir="${2:?usage: plugin-diff.sh <runtime-tarball> <dome-os-plugin-dir>}"
[ -f "$tarball" ] || { echo "no such tarball: $tarball" >&2; exit 1; }
[ -d "$domedir" ] || { echo "no such directory: $domedir" >&2; exit 1; }
out="$(dirname "$tarball")"
tar tf "$tarball" | grep 'gstreamer-1.0/libgst[^/]*\.so$' | sed 's#.*/libgst##; s#\.so$##' | sort > "$out/plugins-cerbero.txt"
ls "$domedir" | sed 's/^libgst//; s/\.so$//' | sort > "$out/plugins-dome-os.txt"
comm -13 "$out/plugins-cerbero.txt" "$out/plugins-dome-os.txt" > "$out/plugins-missing.txt"
comm -23 "$out/plugins-cerbero.txt" "$out/plugins-dome-os.txt" > "$out/plugins-new.txt"
echo "cerbero: $(wc -l < "$out/plugins-cerbero.txt")  dome-os: $(wc -l < "$out/plugins-dome-os.txt")  missing: $(wc -l < "$out/plugins-missing.txt")  new: $(wc -l < "$out/plugins-new.txt")"
