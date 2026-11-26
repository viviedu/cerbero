#!/bin/bash
# Run smoke-checks.sh on a runtime tarball in a throwaway container of the sysroot image (dome-os plus the Debian
# packages it will gain). Usage: SYSROOT_IMAGE=... imx-debian/smoke-test.sh <runtime-tarball>
set -uo pipefail
tarball="${1:?usage: smoke-test.sh <runtime-tarball>}"
: "${SYSROOT_IMAGE:?set SYSROOT_IMAGE to the image built from imx-debian/Dockerfile.sysroot}"
[ -f "$tarball" ] || { echo "no such tarball: $tarball" >&2; exit 1; }
tarball="$(cd "$(dirname "$tarball")" && pwd)/$(basename "$tarball")"
checks="$(cd "$(dirname "$0")" && pwd)/smoke-checks.sh"
results="$(dirname "$tarball")/SMOKE-RESULTS.txt"
docker run --rm --platform linux/arm/v7 -v "$tarball":/gst.tar.xz:ro -v "$checks":/smoke-checks.sh:ro \
  "$SYSROOT_IMAGE" bash /smoke-checks.sh /gst.tar.xz | tee "$results"
status=${PIPESTATUS[0]}
echo "exit: $status" | tee -a "$results"
exit "$status"
