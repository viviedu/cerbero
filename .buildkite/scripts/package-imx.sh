#!/bin/bash
set -euo pipefail

# Same reasoning as package.sh: the bootstrap image's cookbook marks every recipe built and COPYed
# patch changes evade mtime-based change detection, so force-rebuild the Vivi-patched recipes.
VIVI_PATCHED_RECIPES=(
  gst-plugins-base-1.0
  gst-plugins-good-1.0
  gst-plugins-bad-1.0
)
CFG=config/cross-lin-imx6.cbc
./cerbero-uninstalled -c "$CFG" buildone "${VIVI_PATCHED_RECIPES[@]}"

# Gate: every library must be ARMv7 hard-float NEON and need no glibc newer than the box's 2.36
docker/imx-cross/check-elf.sh build/dist/linux_armv7/lib/arm-linux-gnueabihf

# The gstreamer-1.0 package strips the runtime tarball when the imx variant is on
./cerbero-uninstalled -c "$CFG" package gstreamer-1.0
mkdir -p artifacts
runtime=$(ls -t gstreamer-1.0-linux-armv7-*.tar.xz | grep -v -- '-devel' | head -n1)
devel=$(ls -t gstreamer-1.0-linux-armv7-*-devel.tar.xz | head -n1)
echo "Packaging ${runtime} -> artifacts/${VIVI_IMX_FILENAME}"
cp "$runtime" "artifacts/${VIVI_IMX_FILENAME}"
echo "Packaging ${devel} -> artifacts/${VIVI_IMX_DEVEL_FILENAME}"
cp "$devel" "artifacts/${VIVI_IMX_DEVEL_FILENAME}"
