#!/bin/bash
# Run a command inside the i.MX build container with the repo mounted at /workspace.
# SYSROOT_IMAGE is the image built from imx-debian/Dockerfile.sysroot (local tag or registry digest).
set -euo pipefail
cd "$(dirname "$0")/.."
: "${SYSROOT_IMAGE:?set SYSROOT_IMAGE to the image built from imx-debian/Dockerfile.sysroot}"
native="linux/$(docker version -f '{{.Server.Arch}}')"
# a debian:bookworm cached for another platform would otherwise be reused and the whole build emulated
docker pull -q --platform "${native}" debian:bookworm >/dev/null
docker build -q --platform "${native}" --build-arg SYSROOT_IMAGE="${SYSROOT_IMAGE}" -t vivi/gst-imx-debian imx-debian >/dev/null
tty=""; [ -t 0 ] && tty="-t"
exec docker run --rm -i $tty \
  -v "$PWD":/workspace -v gst-imx-debian-build:/build \
  -w /workspace vivi/gst-imx-debian bash -lc "$*"
