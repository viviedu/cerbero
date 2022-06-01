#!/bin/bash
set -euo pipefail

./cerbero-uninstalled -c config/cross-android-universal.cbc package gstreamer-1.0
cp gstreamer-1.0-android-universal-1.20.1.tar.xz "artifacts/${VIVI_FILENAME}"
