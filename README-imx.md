# How to patch i.MX GStreamer

Written 2026-11-27. Describes the state after VIVI-30863: cerbero `vivi-1.26.11-android` at `e4b9fd2a`, dome-os and vivi-box `release-3.13`, deployed build 457.

## Overview

The i.MX box runs GStreamer 1.26.11, built from upstream source plus 17 Vivi patches. Three repos are involved, and a change always flows in this order:

| Step | Repo | What it holds | What you change |
|---|---|---|---|
| 1 | cerbero (`vivi-1.26.11-android`) | Patches and the build (`imx-debian/`) | Patch files, version |
| 2 | dome-os (`release-3.13`) | The OS image; unpacks the tarball into `/usr/local` | Pin: S3 path + 2 checksums |
| 3 | vivi-box (`release-3.13`) | The box app; compiles its addon against the tarball | Same pin + `dome-os` submodule |

Things to know before starting:

- GStreamer is not in dome-os git. dome-os and vivi-box each name one published build by S3 path and SHA-256.
- A build is published only when someone presses **Deploy** on a cerbero Buildkite build. The build number is in the file name: `gstreamer-1.0-linux-armv7-imx6-<version>-vivi-<N>.tar.xz` and `…-vivi-<N>-devel.tar.xz`, under `s3://vivi-devops-packages/gstreamer/`.
- The tarball holds only GStreamer. GLib, OpenSSL, ffmpeg and the rest come from dome-os's Debian packages. The build links against dome-os itself, so library versions match.
- Android is built by the same pipeline from the same patches. One Deploy publishes Android and i.MX together.
- The gstreamer-imx plugins (`libgstimx*.so`) and `libgstnice.so` are not built here. They live in dome-os git.

Time: a cerbero build is about 30 minutes, a box build with the i.MX image about 50 minutes.

## a) Patch GStreamer

All work is in the cerbero repo.

1. Write the patch against the upstream monorepo at the tag in use. Paths must start with `subprojects/<module>/` (for example `subprojects/gst-plugins-good/gst/isomp4/qtdemux.c`). The build applies it with `patch -p1 --fuzz=0`, so it must apply exactly.
2. Put the file in the module's directory and register it:

   | Patch is for | File goes in | Register in |
   |---|---|---|
   | Android and i.MX | `recipes/gst-plugins-{base,good,bad}-1.0/` | the `patches = [...]` list in `recipes/gst-plugins-<module>-1.0.recipe` |
   | i.MX only | `recipes/gst-plugins-base-1.0/imx/` | nothing; every `*.patch` there is applied, in file-name order, after the base list |

   `imx-debian/patch-list.py recipes` prints the exact apply order. Only base, good and bad are read. A patch to another module (core, libav, ugly) needs `patch-list.py` extended first.
3. Build and test locally (optional; needs the dome-os rootfs image, see the cerbero README section "Building the i.MX tarball locally"):

   ```
   export SYSROOT_IMAGE=vivi/gst-imx-sysroot:<commit>
   imx-debian/run.sh imx-debian/build.sh
   imx-debian/run.sh imx-debian/check.sh
   imx-debian/smoke-test.sh build/imx/gstreamer-1.0-linux-armv7-imx6-1.26.11-vivi-local.tar.xz
   ```
4. Push the branch and run the cerbero Buildkite pipeline. It must pass the 6 gates in `check.sh` and the 18 smoke checks. Answer "No" to **Bootstrap Android** unless Android dependencies changed.
5. Test on a box before publishing: use the dome-os form field in section c, step 1.
6. Merge, build the merged branch, press **Deploy**. Note the build number `<N>`.
7. Continue with sections c and d.

If the patch makes GStreamer link a new library, the build writes it into `share/vivi-gstreamer/debian-runtime-deps.txt`. See section c, step 4.

## b) Upgrade to a more recent upstream

Also in the cerbero repo. The i.MX build reads its version from the same place as Android, so both move together.

1. Change `version` in `class GStreamer` in `recipes/custom.py`. The Android recipes build from release tarballs, so they need whatever else a cerbero version bump needs (not covered here).
2. Change `commit=` at the top of `imx-debian/build.sh` to the commit of the new upstream tag. The build refuses to continue if the tag does not match.
3. Update the version written by hand in three more places:
   - `.buildkite/pipeline-build.sh`: the three artifact file names (`VIVI_FILENAME`, `VIVI_IMX_FILENAME`, `VIVI_IMX_DEVEL_FILENAME`)
   - `imx-debian/smoke-checks.sh`: the `version` check (`GStreamer 1.26.11`)
   - `README.md` (the Outputs table and the local build example)
4. Rebase every patch onto the new tag. Drop the ones upstream has merged, and remove them from the recipe lists. Fuzz is 0, so even a shifted context line fails.
5. Check the `meson_options` list in `build.sh`. A new upstream release can add plugins that then build by default; `--wrap-mode=nofallback` stops them bundling private libraries, but they still enlarge the tarball. Compare the plugin list with the previous build.
6. Check the meson version: `imx-debian/Dockerfile` installs meson 1.9.0. Raise it if the new release needs newer.
7. If the new release needs a `-dev` package that is missing, add it to `imx-debian/Dockerfile.sysroot`. Packages come from the Debian snapshot `DEBIAN_SNAPSHOT=20250512T000000Z`, which matches dome-os. Do not move the date unless dome-os's packages move too.
8. Build, test, merge and Deploy as in section a, steps 4 to 6.
9. In dome-os, as well as the pin (section c), change the version of the two dummy packages in `var/lib/dpkg/status` (`1.26.11-custom`, two entries). They exist so apt does not install Debian's GStreamer.

A minor-series jump (1.26 → 1.28) can change the box addon's API use. The addon compiles against the `-devel` tarball, so section d will show any break at compile time.

## c) Integrate into dome-os

1. Test an unpublished build first (optional). Start a dome-os build and fill the form field **GStreamer i.MX Source** with the S3 path of the runtime tarball. Any path works, including a cerbero build's artifact that has not been deployed. With the field set, no checksum is checked.
2. After Deploy, get the two checksums:

   ```
   aws s3 cp s3://vivi-devops-packages/gstreamer/gstreamer-1.0-linux-armv7-imx6-<version>-vivi-<N>.tar.xz .
   aws s3 cp s3://vivi-devops-packages/gstreamer/gstreamer-1.0-linux-armv7-imx6-<version>-vivi-<N>-devel.tar.xz .
   sha256sum gstreamer-1.0-linux-armv7-imx6-*
   ```
3. Edit these three variables in `.buildkite/pipeline-build.sh`:
   - `gstreamer_imx_pin` (the S3 path)
   - `gstreamer_imx_pin_sha256` (runtime)
   - `gstreamer_imx_pin_devel_sha256` (devel)
4. Only if `debian-runtime-deps.txt` changed (a package added or a version changed):
   - install the package into the rootfs from the same Debian snapshot and commit it (the rootfs is in git, with LFS)
   - add it to the `gstreamer_packages` list in `.buildkite/scripts/image.sh`, so the image clean-up does not remove it

   The image build fails with `GStreamer needs <package>=<version>, image has …` if this step is missed.
5. Open the PR. The image build checks, in order: tarball checksum, no plugin fails to load (only `libgstgio.so` is allowed), and all runtime packages installed at the exact versions.

Nothing in dome-os's git rootfs changes for a plain patch release: steps 2, 3 and 5 only.

## d) Update the box

In vivi-box, after the dome-os PR is merged.

1. In `.buildkite/pipeline-build.sh`, set these to the same three values as dome-os: `gstreamer_imx_source`, `gstreamer_imx_sha256`, `gstreamer_imx_devel_sha256`. The comment above them says to keep them the same as dome-os. Nothing enforces it.
2. Move the `dome-os` submodule to the merged dome-os commit, so the triggered i.MX image uses the new pin.
3. Open the PR and run a box build with platform `imx`. Expect in the log:
   - `gstreamer-imx.tar.xz: OK` and `gstreamer-imx-devel.tar.xz: OK`
   - the addon compiles (`gyp info ok`)
   - the triggered dome-os build prints "all N GStreamer runtime packages are installed at the expected versions"
4. Flash the OTA to a box and check:

   ```
   gst-inspect-1.0 --version        # the new version
   gst-inspect-1.0 -b               # only libgstgio.so listed
   ```
   Then run signage (video, HLS, audio), a WebRTC share, a native share and AirPlay.

vivi-box has no form override: it always uses the committed pin, and both checksums are required.

## Pin constraints

Three pins tie the repos together. Two rules cover them.

| Pin | Lives in | Points at |
|---|---|---|
| `dome_os_commit` | cerbero | the dome-os commit GStreamer is compiled and linked against |
| `gstreamer_imx_pin*` | dome-os | the GStreamer build installed into the OS image |
| `gstreamer_imx_source` and two `*_sha256`, plus the `dome-os` submodule | vivi-box | the GStreamer build the addon is compiled against, and the dome-os commit the OTA is built from |

**Rule 1: the vivi-box GStreamer pin must be the same build as the dome-os pin.**

- Why: the addon (`gstreamer.node`) is compiled C++ that calls GStreamer directly. It must be built against the GStreamer it runs with, and the box runs whatever dome-os pinned.
- Strictly it needs the same GStreamer version and patch set. Using the identical build number is the way to guarantee that; Vivi's patches can change headers, so two builds with the same version number are not guaranteed interchangeable.
- If they differ: at best nothing; at worst the addon fails to load or calls something that behaves differently. The highest risk is an addon built against a newer GStreamer than the box has.
- Nothing checks this. The two pins are kept equal by hand.

**Rule 2: move the pins in this order.**

1. dome-os: change `gstreamer_imx_pin*` and merge.
2. vivi-box, in one PR: change the three GStreamer values and move the `dome-os` submodule to the merged dome-os commit.

One vivi-box commit then names one GStreamer build for both the addon and the image.

**`dome_os_commit` (cerbero) is independent of the other two.** It only needs to move when dome-os's Debian packages change, and then together with `DEBIAN_SNAPSHOT` in `imx-debian/Dockerfile.sysroot`. The cerbero parity gate fails the build if a library GStreamer needs is at a different version from dome-os. A published build stays valid when this pin moves.

## Quick reference

| What | Where |
|---|---|
| Patches | cerbero `recipes/gst-plugins-{base,good,bad}-1.0/`, i.MX-only in `…-base-1.0/imx/` |
| Version | cerbero `recipes/custom.py`, `class GStreamer` |
| Upstream tag commit | cerbero `imx-debian/build.sh`, `commit=` |
| Build options | cerbero `imx-debian/build.sh`, `meson_options` |
| dome-os commit the build links against | cerbero `.buildkite/pipeline-build.sh`, `dome_os_commit` |
| GStreamer build pinned in dome-os | dome-os `.buildkite/pipeline-build.sh`, `gstreamer_imx_pin*` |
| GStreamer build pinned in vivi-box | vivi-box `.buildkite/pipeline-build.sh`, `gstreamer_imx_source` and the two `*_sha256` |
