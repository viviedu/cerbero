#!/bin/bash
set -euo pipefail

./cerbero-uninstalled -c config/cross-android-universal.cbc package gstreamer-1.0
mkdir -p artifacts
cp gstreamer-1.0* artifacts/
