#!/bin/bash
set -euo pipefail

cat <<EOF
env:
  BUILDKITE_ARTIFACT_UPLOAD_DESTINATION: s3://vivi-devops-packages/gstreamer/
  BUILDKITE_S3_DEFAULT_REGION: ap-southeast-2
  VIVI_DOWNLOADS_PREFIX: https://vivi-devops-packages.s3-ap-southeast-2.amazonaws.com/gstreamer/

steps:
  - label: ":s3: Deploy"
    depends_on:
      - package
    agents:
      queue: v6
    command: .buildkite/scripts/links.sh ${VIVI_FILENAME}
    plugins:
      - artifacts#v1.9.4:
          download:
            - from: artifacts/${VIVI_FILENAME}
              to: ${VIVI_FILENAME}
          upload:
            - ${VIVI_FILENAME}
EOF
