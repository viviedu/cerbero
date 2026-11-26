#!/bin/bash
# The smoke checks: install the runtime tarball the way the dome-os switch will and test it with no environment variables.
# Runs inside a container of the sysroot image; smoke-test.sh starts one. Usage: smoke-checks.sh <runtime-tarball>
set -uo pipefail

tarball="${1:?usage: smoke-checks.sh <runtime-tarball>}"
[ -f "$tarball" ] || { echo "no such tarball: $tarball" >&2; exit 1; }
tarball=$(realpath "$tarball")
# It rearranges /usr/local, so it only runs in a throwaway container of the sysroot image
if [ ! -f /.dockerenv ] || [ ! -f /var/lib/vivi-sysroot/dome-os-packages.txt ]; then
  echo "smoke-checks.sh must run in a container of the sysroot image" >&2
  exit 1
fi
lib=/usr/local/lib/arm-linux-gnueabihf
plugins=$lib/gstreamer-1.0

# What the dome-os switch takes out: GStreamer 1.20.1, except the gstreamer-imx and nice plugins, and the hand-built
# libraries only it used. Files are moved aside inside this throwaway container, never deleted.
mkdir -p /quarantine/plugins /quarantine/lib /quarantine/lib-top /quarantine/bin
cd "$lib" || exit 1
find gstreamer-1.0 -mindepth 1 -maxdepth 1 ! -name 'libgstimx*.so' ! -name 'libgstnice.so' -exec mv -t /quarantine/plugins {} +
find . -maxdepth 1 \( -name 'libgst*.so*' -o -name 'libges*.so*' \) -exec mv -t /quarantine/lib {} +
for s in libavcodec.so.58 libavformat.so.58 libavfilter.so.7 libavutil.so.56 libswresample.so.3 libswscale.so.5 \
         libavdevice.so.58 libpostproc.so.55 libnice.so.10 libsrtp2.so.1 libjson-glib-1.0.so.0 libsoup-2.4.so.1 \
         libsoup-gnome-2.4.so.1 libavtp.so.0 libmicrodns.so.0 libopenjp2.so.2 libjpeg.so.8 libdv.so.4; do
  find . -maxdepth 1 -name "$s*" -exec mv -t /quarantine/lib {} +
  find /usr/local/lib -maxdepth 1 -name "$s*" -exec mv -t /quarantine/lib-top {} +
done
find /usr/local/bin -maxdepth 1 \( -name 'gst-*' -o -name 'ges-*' \) -exec mv -t /quarantine/bin {} +
mv /usr/local/libexec/gstreamer-1.0 /quarantine/libexec-gstreamer-1.0

tar -xJf "$tarball" -C /usr/local || exit 1
ldconfig 2>/dev/null

fail=0
check() { local name=$1; shift; if "$@"; then echo "PASS $name"; else echo "FAIL $name"; fail=1; fi; }
from_debian() { ldd "$1" | grep -F "$2" | grep -q -E '=> /(usr/)?lib/arm-linux-gnueabihf/'; }

echo "host: $(uname -m), Debian $(cat /etc/debian_version), $(ldd --version | head -1)"
# The tests run as dome-os will: no GStreamer or loader variables
check no-environment bash -c '[ -z "$(env | grep -E "^(GST_|LD_LIBRARY_PATH|GIO_EXTRA_MODULES|SSL_CERT_FILE)")" ]'
check version bash -c 'gst-inspect-1.0 --version | grep -q "GStreamer 1.26.11"'
count=$(gst-inspect-1.0 2>/dev/null | tail -1 | sed -n 's/.*Total count: \([0-9]*\) plugins.*/\1/p')
echo "plugins: ${count:-0}"
# Registry loads the tarball's plugins plus dome-os's gstreamer-imx and nice plugins
check inspect-count [ "${count:-0}" -ge 190 ]
# No plugin was blacklisted, i.e. every .so loaded and resolved its dependencies against dome-os's libraries
check no-blacklist [ "$(gst-inspect-1.0 -b 2>/dev/null | grep -c '\.so')" -eq 0 ]
# Every Debian package the build lists is installed at exactly that version
deps_installed() {
  local bad=0 package version have
  while IFS='=' read -r package version; do
    have=$(dpkg-query -W -f '${Version}' "$package" 2>/dev/null)
    [ "$have" = "$version" ] || { echo "  $package: need $version, have ${have:-none}"; bad=1; }
  done < /usr/local/share/vivi-gstreamer/debian-runtime-deps.txt
  return $bad
}
check runtime-deps deps_installed
# Nothing in the tarball is left with an unresolved library
unresolved() { [ -z "$(tar -tJf "$tarball" | grep -E '\.so(\.|$)' | sed 's|^\./|/usr/local/|' | xargs ldd 2>/dev/null | grep 'not found')" ]; }
check nothing-unresolved unresolved
# The security-relevant libraries are Debian's, not copies under /usr/local
check glib-from-debian from_debian $lib/libgstreamer-1.0.so.0 libglib-2.0.so.0
check openssl-from-debian from_debian $plugins/libgstdtls.so libssl.so.3
check ffmpeg-from-debian from_debian $plugins/libgstlibav.so libavcodec.so.59
check libnice-from-debian from_debian $lib/libgstwebrtcnice-1.0.so.0 libnice.so.10
check libsrtp-from-debian from_debian $plugins/libgstsrtp.so libsrtp2.so.1
# The elements vivi-box uses exist, including dome-os's own gstreamer-imx 0.13 and nice plugins on the new core
req_ok=0; for e in playbin3 souphttpsrc hlsdemux2 rtspsrc tsdemux qtdemux avdec_h264 opusdec textoverlay pulsesink \
                   webrtcbin dtlsdec srtpdec nicesrc nicesink imxvpudec imxg2dvideosink; do
  gst-inspect-1.0 --exists "$e" 2>/dev/null || { echo "  missing element: $e"; req_ok=1; }
done
check required-elements [ "$req_ok" -eq 0 ]
# Video pipeline runs: raw buffers flow through videoconvert
check videotest gst-launch-1.0 -q videotestsrc num-buffers=30 ! videoconvert ! fakesink
# H.264 round-trip through x264 and Debian's ffmpeg
check h264 gst-launch-1.0 -q videotestsrc num-buffers=30 ! x264enc ! h264parse ! avdec_h264 ! fakesink
# Audio pipeline runs: opus encode and decode round-trip
check audio-opus gst-launch-1.0 -q audiotestsrc num-buffers=100 ! opusenc ! opusdec ! fakesink
# Vivi patch 0002: textoverlay accepts shaded-background on a BGRA stream
check textoverlay-alpha gst-launch-1.0 -q videotestsrc num-buffers=5 ! video/x-raw,format=BGRA ! textoverlay text=vivi shaded-background=true ! fakesink
# Vivi patch 0001: playsink was built to use imxipuvideotransform (a string, not a symbol, so grep)
check playsink-imx [ "$(grep -ac imxipuvideotransform $plugins/libgstplayback.so)" -ge 1 ]
# souphttpsrc over HTTPS: Debian's libsoup 3, glib-networking and CA store work
check https timeout 60 gst-launch-1.0 -q souphttpsrc location=https://gstreamer.freedesktop.org/ ! fakesink
exit $fail
