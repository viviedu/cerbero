#!/bin/bash
# Runs inside the imx-build container with the checkout mounted at /workspace
set -euo pipefail
cd "$(dirname "$0")/../.."

imx-debian/build.sh
imx-debian/check.sh
