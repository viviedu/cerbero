#!/bin/bash
# Gates for the i.MX tarballs made by build.sh. Runs inside the build container: imx-debian/run.sh imx-debian/check.sh
set -uo pipefail

out="${GST_OUT_DIR:-/workspace/build/imx}"
repo=$(cd "$(dirname "$0")/.." && pwd)
triplet=arm-linux-gnueabihf
dome_os=/sysroot/var/lib/vivi-sysroot/dome-os-packages.txt

runtime=$(find "${out}" -maxdepth 1 -name 'gstreamer-1.0-linux-armv7-imx6-*.tar.xz' ! -name '*-devel.tar.xz')
if [[ $(wc -l <<<"${runtime}") -ne 1 || -z "${runtime}" ]]; then
  echo "expected exactly one runtime tarball in ${out}, found: ${runtime:-none}" >&2
  exit 1
fi
devel="${runtime%.tar.xz}-devel.tar.xz"
missing="${runtime%.tar.xz}-dome-os-missing-packages.txt"

# /tmp belongs to the throwaway container, so the unpacked copies need no clean up
tree=$(mktemp -d)
tar -xJf "${runtime}" -C "${tree}"
tar -xJf "${devel}" -C "${tree}"
plugins="${tree}/lib/${triplet}/gstreamer-1.0"
deps="${tree}/share/vivi-gstreamer/debian-runtime-deps.txt"

fail=0
check() { local name=$1; shift; if "$@"; then echo "PASS ${name}"; else echo "FAIL ${name}"; fail=1; fi; }

# Every library is ARMv7 hard-float NEON and needs no glibc newer than the box's 2.36
check target-abi "${repo}/imx-debian/check-target-abi.sh" "${tree}/lib"

# The tarball ships GStreamer only; every other library must come from dome-os
gstreamer_only() {
  local other
  other=$(tar -tJf "${runtime}" | grep -E '\.so(\.|$)' | sed 's|.*/||' | grep -v -E '^lib(gst|ges)' || true)
  [[ -z "${other}" ]] || { echo "  not GStreamer: ${other}"; return 1; }
}
check gstreamer-only gstreamer_only

# No library carries a search path from the build machine
no_runpath() {
  local hits
  hits=$(find "${tree}" -type f -name '*.so*' -exec "${triplet}-readelf" -d {} + 2>/dev/null | grep -E 'RPATH|RUNPATH' || true)
  [[ -z "${hits}" ]] || { echo "${hits}" | head -5; return 1; }
}
check no-runpath no_runpath

# Parity: a Debian package GStreamer needs and dome-os already has must be the version dome-os has
parity() {
  local bad=0 package version have
  : > "${missing}"
  while IFS='=' read -r package version; do
    have=$(awk -v p="${package}" '$1 == p { print $2 }' "${dome_os}")
    if [[ -z "${have}" ]]; then
      echo "${package}=${version}" >> "${missing}"
    elif [[ "${have}" != "${version}" ]]; then
      echo "  ${package}: built against ${version}, dome-os has ${have}"; bad=1
    fi
  done < "${deps}"
  echo "  $(wc -l < "${deps}") packages needed, $(wc -l < "${missing}") not yet in dome-os (listed in $(basename "${missing}"))"
  return "${bad}"
}
check dome-os-parity parity

# The plugins vivi-box uses are in the tarball (nice and the gstreamer-imx plugins come from dome-os)
required_plugins() {
  local bad=0 p
  for p in coreelements playback typefindfunctions app soup hls adaptivedemux2 rtsp rtp rtpmanager mpegtsdemux isomp4 \
           libav opus pango cairo png imagefreeze videoconvertscale videoparsersbad pulseaudio webrtc srtp dtls x264; do
    [[ -f "${plugins}/libgst${p}.so" ]] || { echo "  missing plugin: ${p}"; bad=1; }
  done
  return "${bad}"
}
check required-plugins required_plugins

# The -devel tarball is usable for building the vivi-box addon against /usr/local
devel_usable() {
  [[ -f "${tree}/include/gstreamer-1.0/gst/gst.h" ]] &&
    grep -q '^prefix=/usr/local$' "${tree}/lib/${triplet}/pkgconfig/gstreamer-1.0.pc" &&
    [[ -L "${tree}/lib/${triplet}/libgstreamer-1.0.so" ]]
}
check devel-usable devel_usable

echo "plugins: $(find "${plugins}" -maxdepth 1 -name 'libgst*.so' | wc -l)"
exit "${fail}"
