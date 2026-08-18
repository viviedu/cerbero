#!/bin/bash
set -euo pipefail

# Force-rebuild the Vivi-patched recipes. The bootstrap image's cookbook marks
# every recipe built, and COPYed recipe/patch changes evade its mtime-gated
# change detection, so without this a package run just re-tars the bootstrap
# prefix (~5h to rebuild via bootstrap otherwise). Safe in tarball mode: each
# recipe extracts its own source tree and applies its own patches. (In git
# mode this was NOT safe - all gst recipes share one monorepo checkout and
# only the first extract's patches survive; see recipes/custom.py.)
VIVI_PATCHED_RECIPES=(
  gst-plugins-base-1.0
  gst-plugins-good-1.0
  gst-plugins-bad-1.0
)
./cerbero-uninstalled -c config/cross-android-universal.cbc buildone "${VIVI_PATCHED_RECIPES[@]}"

./cerbero-uninstalled -c config/cross-android-universal.cbc package gstreamer-1.0
mkdir -p artifacts
# cerbero appends its own package revision to the version (e.g. 1.26.11.1), so
# match the produced full (non-runtime) tarball rather than hardcoding a version.
src=$(ls -t gstreamer-1.0-android-universal-*.tar.xz | grep -v -- '-runtime' | head -n1)
echo "Packaging ${src} -> artifacts/${VIVI_FILENAME}"
cp "$src" "artifacts/${VIVI_FILENAME}"
