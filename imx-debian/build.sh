#!/bin/bash
# Build GStreamer for the i.MX6 box against /sysroot and pack the runtime and -devel tarballs.
# Runs inside the build container: SYSROOT_IMAGE=... imx-debian/run.sh imx-debian/build.sh
set -euo pipefail

# the commit the upstream tag for that version must be; change it when recipes/custom.py moves to another version
commit=e6ee9e63e033b9c8e343ba0bdfa7590ef81449ee
source_url="${GST_SOURCE_URL:-https://gitlab.freedesktop.org/gstreamer/gstreamer.git}"
build_number="${BUILDKITE_BUILD_NUMBER:-local}"
work="${GST_WORK_DIR:-/build/gst}"
out="${GST_OUT_DIR:-/workspace/build/imx}"

repo=$(cd "$(dirname "$0")/.." && pwd)
# the same GStreamer version the Android build uses
version=$(python3 "${repo}/imx-debian/gst-version.py" "${repo}/recipes/custom.py")
triplet=arm-linux-gnueabihf
name="gstreamer-1.0-linux-armv7-imx6-${version}-vivi-${build_number}"
src="${work}/src"
stage="${work}/dest/usr/local"

# Vivi patches in apply order, read from the recipes so the Android and i.MX builds cannot drift apart
patch_list=$(python3 "${repo}/imx-debian/patch-list.py" "${repo}/recipes")
mapfile -t patches <<< "${patch_list}"

meson_options=(
  --cross-file "${repo}/imx-debian/armhf-cross.ini"
  --prefix=/usr/local --libdir="lib/${triplet}" --buildtype=release
  # nofallback alone still clones and builds ORC; the two *-source options stop that
  --wrap-mode=nofallback -Dorc-source=system -Dbuild-tools-source=system
  -Dpython=disabled -Ddevtools=disabled -Dgst-examples=disabled -Dtests=disabled
  -Dexamples=disabled -Dintrospection=disabled -Dnls=disabled -Ddoc=disabled
  -Dqt5=disabled -Dqt6=disabled -Dbenchmarks=disabled -Dlibnice=disabled -Dtls=disabled
  -Dgpl=enabled -Dlibav=enabled -Drtsp_server=enabled -Dges=enabled -Dorc=enabled
  # no GL, X11, ALSA or V4L2 on the box: it renders and captures through gstreamer-imx
  -Dgst-plugins-base:gl=disabled -Dgst-plugins-base:x11=disabled
  -Dgst-plugins-base:xvideo=disabled -Dgst-plugins-base:alsa=disabled
  -Dgst-plugins-good:v4l2=disabled -Dgst-plugins-good:ximagesrc=disabled
  # plugins the cerbero i.MX build (388, box tested) did not ship
  -Dgst-plugins-base:dsd=disabled
  -Dgst-plugins-good:monoscope=disabled -Dgst-plugins-good:oss=disabled -Dgst-plugins-good:oss4=disabled
  -Dgst-plugins-bad:analyticsoverlay=disabled -Dgst-plugins-bad:aom=disabled
  -Dgst-plugins-bad:codec2json=disabled -Dgst-plugins-bad:colormanagement=disabled
  -Dgst-plugins-bad:faad=disabled -Dgst-plugins-bad:faceoverlay=disabled
  -Dgst-plugins-bad:fbdev=disabled -Dgst-plugins-bad:festival=disabled
  -Dgst-plugins-bad:jp2kdecimator=disabled -Dgst-plugins-bad:libde265=disabled
  -Dgst-plugins-bad:openexr=disabled -Dgst-plugins-bad:rsvg=disabled
  -Dgst-plugins-bad:tensordecoders=disabled -Dgst-plugins-bad:ttml=disabled
  -Dgst-plugins-bad:unixfd=disabled -Dgst-plugins-bad:uvcgadget=disabled
  -Dgst-plugins-bad:v4l2codecs=disabled -Dgst-plugins-bad:vmnc=disabled
  -Dgst-plugins-bad:webp=disabled
)

echo "--- fetch GStreamer ${version}"
# the work directory is wiped on every run, so only accept one inside the container's build volume
case "${work}" in /build/?*) ;; *) echo "GST_WORK_DIR must be under /build, got '${work}'" >&2; exit 1 ;; esac
rm -rf -- "${work}"
mkdir -p "${src}" "${out}"
git -C "${src}" init -q
git -C "${src}" fetch -q --depth 1 "${source_url}" "refs/tags/${version}"
fetched=$(git -C "${src}" rev-parse 'FETCH_HEAD^{commit}')
if [[ "${fetched}" != "${commit}" ]]; then
  echo "tag ${version} is ${fetched}, expected ${commit}" >&2
  exit 1
fi
git -C "${src}" checkout -q FETCH_HEAD

echo "--- apply ${#patches[@]} Vivi patches"
for p in "${patches[@]}"; do
  echo "${p}"
  patch -d "${src}" -p1 --no-backup-if-mismatch --fuzz=0 -s < "${repo}/recipes/${p}"
done

echo "--- configure"
meson setup "${work}/build" "${src}" "${meson_options[@]}"

echo "--- compile"
ninja -C "${work}/build"

echo "--- install"
DESTDIR="${work}/dest" meson install -C "${work}/build" --no-rebuild --strip > "${work}/install.log"

echo "--- list the Debian packages the libraries need"
cd "${stage}"
elfs=$(find . -type f -exec sh -c 'head -c4 "$1" | grep -q ELF' _ {} \; -print)
# libsoup is loaded with dlopen and TLS comes from a GIO module, so neither appears in NEEDED
packages="libsoup-3.0-0 glib-networking"
for so in $(echo "${elfs}" | xargs "${triplet}-readelf" -d | sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p' | sort -u); do
  case "${so}" in libgst*|libges*) continue ;; esac
  owner=$(dpkg --admindir=/sysroot/var/lib/dpkg -S "*/${so}" 2>/dev/null | head -1 | cut -d: -f1)
  if [[ -z "${owner}" ]]; then
    echo "${so} is not owned by a Debian package in the sysroot" >&2
    exit 1
  fi
  packages+=" ${owner}"
done
mkdir -p share/vivi-gstreamer
for package in $(echo "${packages}" | tr ' ' '\n' | sort -u); do
  awk -v p="${package}" '$1 == p { print $1 "=" $2; found = 1 } END { exit !found }' \
    /sysroot/var/lib/vivi-sysroot/sysroot-packages.txt
done > share/vivi-gstreamer/debian-runtime-deps.txt
cp share/vivi-gstreamer/debian-runtime-deps.txt "${out}/${name}-debian-runtime-deps.txt"

echo "--- pack"
find . \( -type f -o -type l \) | sort > "${work}/all.list"
# -devel: headers, pkg-config files and the unversioned lib*.so link names
grep -E "^\./include/|/pkgconfig/|^\./share/aclocal/|/gstreamer-1.0/include/|^\./lib/${triplet}/[^/]+\.so$" \
  "${work}/all.list" > "${work}/devel.list"
grep -v -x -F -f "${work}/devel.list" "${work}/all.list" > "${work}/runtime.list"
for kind in runtime devel; do
  suffix=""; [[ "${kind}" == "devel" ]] && suffix="-devel"
  tar -cJf "${out}/${name}${suffix}.tar.xz" --owner=0 --group=0 --numeric-owner -T "${work}/${kind}.list"
done

ls -lh "${out}/${name}"*
echo "$(grep -c "/gstreamer-1.0/libgst.*\.so$" "${work}/runtime.list") plugins, $(wc -l < share/vivi-gstreamer/debian-runtime-deps.txt) Debian runtime packages"
