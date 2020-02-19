#!/bin/bash
set -euo pipefail

for file in "$@"; do
  echo "- <a href=\"${BUILDKITE_ARTIFACT_UPLOAD_DESTINATION}/${file}\">${file}</a>"
done | buildkite-agent annotate --context links --style success --append
