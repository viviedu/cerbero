#!/bin/bash
set -euo pipefail

./cerbero-uninstalled -c config/cross-android-universal.cbc package gstreamer-1.0
mkdir -p artifacts
# cerbero appends its own package revision to the version (e.g. 1.26.11.1), so
# match the produced full (non-runtime) tarball rather than hardcoding a version.
src=$(ls -t gstreamer-1.0-android-universal-*.tar.xz | grep -v -- '-runtime' | head -n1)
echo "Packaging ${src} -> artifacts/${VIVI_FILENAME}"
cp "$src" "artifacts/${VIVI_FILENAME}"
