#!/bin/bash
# Run a command inside the i.MX cross-build image with the repo mounted at /workspace.
set -euo pipefail
cd "$(dirname "$0")/../.."
docker build --pull --platform linux/arm64 -q -t vivi/cerbero-imx-cross docker/imx-cross >/dev/null
tty=""; [ -t 0 ] && tty="-t"
exec docker run --rm -i $tty --platform linux/arm64 \
  -v "$PWD":/workspace -v cerbero-imx-build:/workspace/build \
  -w /workspace vivi/cerbero-imx-cross bash -lc "$*"
