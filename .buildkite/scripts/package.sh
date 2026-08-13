#!/bin/bash
set -euo pipefail

# Force-rebuild Vivi-patched recipes: the bootstrap image's cookbook marks them
# built, and COPYed recipe/patch changes evade its mtime-gated change detection.
#
# One buildone invocation PER recipe, not one invocation for all. All gst
# recipes share a single monorepo checkout (custom.GStreamer config_src_dir),
# and cerbero dedups extracts per config_src_dir within an invocation
# (Source._extract_done), so in a combined run only the FIRST recipe's extract
# executes — it wipes the shared tree and applies only its own patches, and
# every later recipe compiles unpatched (vivi-274 shipped with no androidmedia
# patches this way). A fresh invocation per recipe empties the dedup set, and
# extract never short-circuits for recipes with patches, so each recipe
# re-checkouts the tree and applies its own patches before compiling. Earlier
# recipes' artifacts are already installed to the prefix and survive the wipe.
VIVI_PATCHED_RECIPES=(
  gst-plugins-base-1.0
  gst-plugins-good-1.0
  gst-plugins-bad-1.0
)
for recipe in "${VIVI_PATCHED_RECIPES[@]}"; do
  ./cerbero-uninstalled -c config/cross-android-universal.cbc buildone "${recipe}"
done

./cerbero-uninstalled -c config/cross-android-universal.cbc package gstreamer-1.0
mkdir -p artifacts
# cerbero appends its own package revision to the version (e.g. 1.26.11.1), so
# match the produced full (non-runtime) tarball rather than hardcoding a version.
src=$(ls -t gstreamer-1.0-android-universal-*.tar.xz | grep -v -- '-runtime' | head -n1)
echo "Packaging ${src} -> artifacts/${VIVI_FILENAME}"
cp "$src" "artifacts/${VIVI_FILENAME}"
