#!/bin/bash
set -euo pipefail

./cerbero-uninstalled -c config/cross-android-universal.cbc package gstreamer-1.0
cp gstreamer-1.0-android-universal-1.16.1.tar.bz2 "artifacts/${VIVI_FILENAME}"
