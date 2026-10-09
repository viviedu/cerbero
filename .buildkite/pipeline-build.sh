#!/bin/bash
set -euo pipefail

bootstrap=$(buildkite-agent meta-data get "bootstrap" --default "false")
bootstrap_imx=$(buildkite-agent meta-data get "bootstrap_imx" --default "false")

VIVI_FILENAME="gstreamer-1.0-android-universal-1.26.11-vivi-${BUILDKITE_BUILD_NUMBER}.tar.xz"
VIVI_IMX_FILENAME="gstreamer-1.0-linux-armv7-imx6-1.26.11-vivi-${BUILDKITE_BUILD_NUMBER}.tar.xz"
VIVI_IMX_DEVEL_FILENAME="gstreamer-1.0-linux-armv7-imx6-1.26.11-vivi-${BUILDKITE_BUILD_NUMBER}-devel.tar.xz"

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
      - docker-compose#v5.13.0:
          config: .buildkite/docker-compose.buildkite.yml
          build: bootstrap
          cache-from: bootstrap:${GLOBAL_DOCKER_REGISTRY}/build-cache:${BUILDKITE_PIPELINE_SLUG}-bootstrap
          push: bootstrap:${GLOBAL_DOCKER_REGISTRY}/build-cache:${BUILDKITE_PIPELINE_SLUG}-bootstrap

  - label: ":package: Package"
    key: package
    depends_on: bootstrap
    agents:
      queue: thicc
    command: .buildkite/scripts/package.sh
    plugins:
      - docker-compose#v5.13.0:
          config: .buildkite/docker-compose.buildkite.yml
          build: package
          args:
            - GLOBAL_DOCKER_REGISTRY
            - BUILDKITE_PIPELINE_SLUG
          cache-from: package:${GLOBAL_DOCKER_REGISTRY}/build-cache:${BUILDKITE_PIPELINE_SLUG}-package
          push: package:${GLOBAL_DOCKER_REGISTRY}/build-cache:${BUILDKITE_PIPELINE_SLUG}-package
          run: package
          env:
            - VIVI_FILENAME=${VIVI_FILENAME}
          volumes:
            - ./artifacts:/workspace/artifacts
      - artifacts#v1.9.4:
          upload:
            - artifacts/${VIVI_FILENAME}

  - label: ":boot: i.MX base image"
    key: imx_base
    if: "'${bootstrap_imx}' == 'true'"
    agents:
      queue: thicc
    plugins:
      - docker-compose#v5.13.0:
          config: .buildkite/docker-compose.buildkite.yml
          build: imx-base
          cache-from: imx-base:${GLOBAL_DOCKER_REGISTRY}/build-cache:${BUILDKITE_PIPELINE_SLUG}-imx-base
          push: imx-base:${GLOBAL_DOCKER_REGISTRY}/build-cache:${BUILDKITE_PIPELINE_SLUG}-imx-base

  - label: ":boot: i.MX bootstrap"
    key: imx_bootstrap
    if: "'${bootstrap_imx}' == 'true'"
    depends_on: imx_base
    agents:
      queue: thicc
    plugins:
      - docker-compose#v5.13.0:
          config: .buildkite/docker-compose.buildkite.yml
          build: imx-bootstrap
          args:
            - GLOBAL_DOCKER_REGISTRY
            - BUILDKITE_PIPELINE_SLUG
          cache-from: imx-bootstrap:${GLOBAL_DOCKER_REGISTRY}/build-cache:${BUILDKITE_PIPELINE_SLUG}-imx-bootstrap
          push: imx-bootstrap:${GLOBAL_DOCKER_REGISTRY}/build-cache:${BUILDKITE_PIPELINE_SLUG}-imx-bootstrap

  - label: ":package: i.MX package"
    key: imx_package
    depends_on: imx_bootstrap
    agents:
      queue: thicc
    command: .buildkite/scripts/package-imx.sh
    plugins:
      - docker-compose#v5.13.0:
          config: .buildkite/docker-compose.buildkite.yml
          build: imx-package
          args:
            - GLOBAL_DOCKER_REGISTRY
            - BUILDKITE_PIPELINE_SLUG
          cache-from: imx-package:${GLOBAL_DOCKER_REGISTRY}/build-cache:${BUILDKITE_PIPELINE_SLUG}-imx-package
          push: imx-package:${GLOBAL_DOCKER_REGISTRY}/build-cache:${BUILDKITE_PIPELINE_SLUG}-imx-package
          run: imx-package
          env:
            - VIVI_IMX_FILENAME=${VIVI_IMX_FILENAME}
            - VIVI_IMX_DEVEL_FILENAME=${VIVI_IMX_DEVEL_FILENAME}
          volumes:
            - ./artifacts:/workspace/artifacts
      - artifacts#v1.9.4:
          upload:
            - artifacts/${VIVI_IMX_FILENAME}
            - artifacts/${VIVI_IMX_DEVEL_FILENAME}

  - input: ":rocket: Deploy"
    key: deploy_input

  - label: ":pipeline: Deploy"
    depends_on: deploy_input
    agents:
      queue: v6
    command: ".buildkite/pipeline-deploy.sh | buildkite-agent pipeline upload"
    env:
      VIVI_FILENAME: ${VIVI_FILENAME}
      VIVI_IMX_FILENAME: ${VIVI_IMX_FILENAME}
      VIVI_IMX_DEVEL_FILENAME: ${VIVI_IMX_DEVEL_FILENAME}
EOF
