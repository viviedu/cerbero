#!/bin/bash
set -euo pipefail

bootstrap=$(buildkite-agent meta-data get "bootstrap" --default "false")

VIVI_FILENAME="gstreamer-1.0-android-universal-1.26.11-vivi-${BUILDKITE_BUILD_NUMBER}.tar.xz"
VIVI_IMX_FILENAME="gstreamer-1.0-linux-armv7-imx6-1.26.11-vivi-${BUILDKITE_BUILD_NUMBER}.tar.xz"
VIVI_IMX_DEVEL_FILENAME="gstreamer-1.0-linux-armv7-imx6-1.26.11-vivi-${BUILDKITE_BUILD_NUMBER}-devel.tar.xz"

# The i.MX build links against the dome-os rootfs at this commit; dome-os publishes the image (rootfs-image.sh)
dome_os_commit=3654a29f312b
dome_os_image="${VIVI_DOME_OS_IMAGE:-${GLOBAL_DOCKER_REGISTRY}/build-cache:dome-os-rootfs-${dome_os_commit}}"
sysroot_image="${GLOBAL_DOCKER_REGISTRY}/build-cache:${BUILDKITE_PIPELINE_SLUG}-imx-sysroot-${dome_os_commit}"
imx_build_image="${GLOBAL_DOCKER_REGISTRY}/build-cache:${BUILDKITE_PIPELINE_SLUG}-imx-build"
imx_name="${VIVI_IMX_FILENAME%.tar.xz}"

cat <<EOF
env:
  BUILDKITE_ARTIFACT_UPLOAD_DESTINATION: s3://vivi-buildkite-artifacts/${BUILDKITE_BUILD_ID}
  BUILDKITE_S3_DEFAULT_REGION: ap-southeast-2

steps:
  - label: ":android: Android bootstrap"
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

  - label: ":android: Android package"
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

  - label: ":boot: i.MX sysroot image"
    key: imx_sysroot
    agents:
      queue: thicc
    env:
      DOME_OS_IMAGE: ${dome_os_image}
    plugins:
      - docker-compose#v5.13.0:
          config: .buildkite/docker-compose.buildkite.yml
          build: imx-sysroot
          cache-from: imx-sysroot:${sysroot_image}
          push: imx-sysroot:${sysroot_image}

  - label: ":package: i.MX package"
    key: imx_package
    depends_on: imx_sysroot
    agents:
      queue: thicc
    command: .buildkite/scripts/package-imx.sh
    env:
      SYSROOT_IMAGE: ${sysroot_image}
    plugins:
      - docker-compose#v5.13.0:
          config: .buildkite/docker-compose.buildkite.yml
          build: imx-build
          cache-from: imx-build:${imx_build_image}
          push: imx-build:${imx_build_image}
          run: imx-build
          env:
            - BUILDKITE_BUILD_NUMBER
            - GST_OUT_DIR=/workspace/artifacts
          volumes:
            - ./:/workspace
      - artifacts#v1.9.4:
          upload:
            - artifacts/${VIVI_IMX_FILENAME}
            - artifacts/${VIVI_IMX_DEVEL_FILENAME}
            - artifacts/${imx_name}-debian-runtime-deps.txt
            - artifacts/${imx_name}-dome-os-missing-packages.txt

  - label: ":test_tube: i.MX smoke test"
    key: imx_smoke
    depends_on: imx_package
    agents:
      queue: thicc
    command: /workspace/imx-debian/smoke-checks.sh /workspace/artifacts/${VIVI_IMX_FILENAME}
    env:
      SYSROOT_IMAGE: ${sysroot_image}
    plugins:
      - artifacts#v1.9.4:
          download:
            - artifacts/${VIVI_IMX_FILENAME}
      - docker-compose#v5.13.0:
          config: .buildkite/docker-compose.buildkite.yml
          run: imx-smoke
          volumes:
            - ./:/workspace

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
