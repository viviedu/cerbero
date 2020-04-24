#!/bin/bash
set -euo pipefail

bootstrap=$(buildkite-agent meta-data get "bootstrap" --default "false")

VIVI_FILENAME="gstreamer-1.0-android-universal-1.16.2-vivi-${BUILDKITE_BUILD_NUMBER}.tar.bz2"

cat <<EOF
env:
  BUILDKITE_ARTIFACT_UPLOAD_DESTINATION: s3://vivi-buildkite-artifacts/${BUILDKITE_BUILD_ID}
  BUILDKITE_S3_DEFAULT_REGION: ap-southeast-2

steps:
  - label: ":boot: Bootstrap"
    key: bootstrap
    if: "'${bootstrap}' == 'true'"
    agents:
      queue: thicc
    plugins:
      - docker-compose#v3.2.0:
          config: .buildkite/docker-compose.buildkite.yml
          build: bootstrap
          image-repository: ${GLOBAL_DOCKER_REGISTRY}/build-cache
          image-name: ${BUILDKITE_PIPELINE_SLUG}-bootstrap
          cache-from: bootstrap:${GLOBAL_DOCKER_REGISTRY}/build-cache:${BUILDKITE_PIPELINE_SLUG}-bootstrap

  - label: ":package: Package"
    key: package
    depends_on: bootstrap
    agents:
      queue: thicc
    command: .buildkite/scripts/package.sh
    plugins:
      - viviedu/docker-compose#dd0a3f4:
          config: .buildkite/docker-compose.buildkite.yml
          build: package
          args:
            - GLOBAL_DOCKER_REGISTRY
            - BUILDKITE_PIPELINE_SLUG
          image-repository: ${GLOBAL_DOCKER_REGISTRY}/build-cache
          image-name: ${BUILDKITE_PIPELINE_SLUG}-package
          cache-from: package:${GLOBAL_DOCKER_REGISTRY}/build-cache:${BUILDKITE_PIPELINE_SLUG}-package
          run: package
          env:
            - VIVI_FILENAME=${VIVI_FILENAME}
          volumes:
            - ./artifacts:/workspace/artifacts
      - artifacts#v1.2.0:
          upload:
            - artifacts/${VIVI_FILENAME}

  - input: ":rocket: Deploy"
    key: deploy_input

  - label: ":pipeline: Deploy"
    depends_on: deploy_input
    agents:
      queue: v3
    command: ".buildkite/pipeline-deploy.sh | buildkite-agent pipeline upload"
    env:
      VIVI_FILENAME: ${VIVI_FILENAME}
EOF
