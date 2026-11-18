#!/bin/bash
# Run the cerbero i.MX runtime tarball inside a linux/arm/v7 debian:bookworm container and smoke-test it.
set -uo pipefail
tarball="${1:?usage: smoke-test.sh <runtime-tarball>}"
[ -f "$tarball" ] || { echo "no such tarball: $tarball" >&2; exit 1; }
tarball="$(cd "$(dirname "$tarball")" && pwd)/$(basename "$tarball")"
results="$(dirname "$tarball")/SMOKE-RESULTS.txt"
docker run --rm -i --platform linux/arm/v7 -v "$tarball":/gst.tar.xz:ro debian:bookworm bash -s <<'EOF' | tee "$results"
set -uo pipefail
apt-get update -qq >/dev/null && apt-get install -y -qq xz-utils ca-certificates libpulse0 >/dev/null 2>&1
mkdir -p /opt/gst && tar xJf /gst.tar.xz -C /opt/gst
export LD_LIBRARY_PATH=/opt/gst/lib/arm-linux-gnueabihf
export GST_PLUGIN_PATH=/opt/gst/lib/arm-linux-gnueabihf/gstreamer-1.0
export GST_PLUGIN_SYSTEM_PATH=
export GIO_EXTRA_MODULES=/opt/gst/lib/arm-linux-gnueabihf/gio/modules
export SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
export PATH=/opt/gst/bin:$PATH
export GST_REGISTRY=/tmp/gst-registry.bin
fail=0
check() { local name=$1; shift; if "$@"; then echo "PASS $name"; else echo "FAIL $name"; fail=1; fi; }
echo "host: $(uname -m) $(ldd --version | head -1)"
# Plugin registry loads and holds at least 150 plugins (the 1.20.1 box has 194)
count=$(gst-inspect-1.0 2>/dev/null | tail -1 | sed -n 's/.*Total count: \([0-9]*\) plugins.*/\1/p')
echo "plugins: ${count:-0}"
check inspect-count [ "${count:-0}" -ge 150 ]
# No plugin was blacklisted, i.e. every .so loaded and resolved its dependencies
check no-blacklist [ "$(gst-inspect-1.0 -b 2>/dev/null | grep -c '\.so')" -eq 0 ]
# The plugins vivi-box uses are present
req_ok=0; for p in coreelements playback soup hls rtsp mpegtsdemux isomp4 libav opus pango; do gst-inspect-1.0 "$p" >/dev/null 2>&1 || { echo "  missing plugin: $p"; req_ok=1; }; done
check required [ "$req_ok" -eq 0 ]
# Video pipeline runs: raw buffers flow through videoconvert
check videotest gst-launch-1.0 -q videotestsrc num-buffers=30 ! videoconvert ! fakesink
# Audio pipeline runs: opus encode and decode round-trip
check audio-opus gst-launch-1.0 -q audiotestsrc num-buffers=100 ! opusenc ! opusdec ! fakesink
# Vivi patch 0002: textoverlay accepts shaded-background on a BGRA stream
check textoverlay-alpha gst-launch-1.0 -q videotestsrc num-buffers=5 ! video/x-raw,format=BGRA ! textoverlay text=vivi shaded-background=true ! fakesink
# Vivi patch 0001: playsink was built to use imxipuvideotransform (a string, not a symbol, so grep)
check playsink-imx [ "$(grep -ac imxipuvideotransform /opt/gst/lib/arm-linux-gnueabihf/gstreamer-1.0/libgstplayback.so)" -ge 1 ]
# souphttpsrc over HTTPS: bundled libsoup 3, OpenSSL, glib-networking and the CA bundle work
check https timeout 60 gst-launch-1.0 -q souphttpsrc location=https://gstreamer.freedesktop.org/ ! fakesink
# libgstreamer resolves glib from the tarball, not from the host
check glib-resolves bash -c "ldd /opt/gst/lib/arm-linux-gnueabihf/libgstreamer-1.0.so.0 | grep libglib-2.0 | grep -q /opt/gst"
# The test container has the box glibc (2.36), so loader results carry over
check glibc-host bash -c "ldd --version | head -1 | grep -q 2.36"
echo "glib bundled: $(ls /opt/gst/lib/arm-linux-gnueabihf/libglib-2.0.so.0.*)"
echo "libsoup bundled: $(ls /opt/gst/lib/arm-linux-gnueabihf/libsoup-*.so.* 2>/dev/null | tr '\n' ' ')"
exit $fail
EOF
status=${PIPESTATUS[0]}
echo "exit: $status" | tee -a "$results"
exit "$status"
