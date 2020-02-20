#!/bin/bash
set -euo pipefail

for file in "$@"; do
  echo "- <a href=\"${VIVI_DOWNLOADS_PREFIX}/${file}\">${file}</a>"
done | buildkite-agent annotate --context links --style success --append
