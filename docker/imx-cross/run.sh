#!/bin/bash
# Run a command inside the i.MX cross-build image with the repo mounted at /workspace.
# The platform is pinned to the host: smoke-test.sh pulls the linux/arm/v7 debian:bookworm, which would otherwise
# become the base of this image and turn the cross build into a native ARMv7 one.
set -euo pipefail
cd "$(dirname "$0")/../.."
docker build --pull -q --platform "linux/$(docker version -f '{{.Server.Arch}}')" -t vivi/cerbero-imx-cross docker/imx-cross >/dev/null
tty=""; [ -t 0 ] && tty="-t"
exec docker run --rm -i $tty \
  -v "$PWD":/workspace -v cerbero-imx-build:/workspace/build \
  -w /workspace vivi/cerbero-imx-cross bash -lc "$*"
