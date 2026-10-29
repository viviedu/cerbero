#!/bin/bash
# Check every *.so* under a directory carries the i.MX6 box's ABI. See --help.
# Hard-float is the box's Debian armhf ABI: its glibc and libpulse pass floats in VFP registers, and the loader
# refuses to mix hard- and soft-float objects. v7 and NEON are the Cortex-A9 features the .cbc selects with
# -mfpu=neon (matching the box's existing GStreamer libs); asserting them catches a build where those flags were lost.
set -uo pipefail
usage() {
  cat <<EOT
usage: check-target-abi.sh <dir>

Gate for the i.MX6 cross build: checks every *.so* under <dir> will load on the box.
Each library must
  - be ARMv7 with NEON (Tag_CPU_arch: v7, Tag_Advanced_SIMD_arch: NEONv1)
  - use the hard-float ABI (Tag_ABI_VFP_args: VFP registers), as Debian armhf does
  - need no glibc symbol version newer than \$MAX_GLIBC (default 2.36, the box's bookworm glibc)
Prints one FAIL line per violation and exits 1, or "OK <n> files" and exits 0.
Run inside the cross-build container, e.g. after a package step:
  docker/imx-cross/check-target-abi.sh build/dist/linux_armv7/lib/arm-linux-gnueabihf
Environment: READELF, OBJDUMP (default arm-linux-gnueabihf-*), MAX_GLIBC.
EOT
}
case "${1:-}" in -h|--help) usage; exit 0;; '') usage >&2; exit 2;; esac
dir="$1"
readelf="${READELF:-arm-linux-gnueabihf-readelf}"
objdump="${OBJDUMP:-arm-linux-gnueabihf-objdump}"
max_glibc="${MAX_GLIBC:-2.36}"
bad=0; n=0
while IFS= read -r -d '' f; do
  n=$((n + 1))
  attrs=$("$readelf" -A "$f" 2>/dev/null)
  for tag in 'Tag_ABI_VFP_args: VFP registers' 'Tag_Advanced_SIMD_arch: NEONv1' 'Tag_CPU_arch: v7'; do
    grep -qF "$tag" <<<"$attrs" || { echo "FAIL $f: missing '$tag'"; bad=1; }
  done
  top=$("$objdump" -T "$f" 2>/dev/null | grep -o 'GLIBC_2\.[0-9]*' | sort -uV | tail -1)
  if [ -n "$top" ]; then
    newest=$(printf '%s\n%s\n' "GLIBC_$max_glibc" "$top" | sort -V | tail -1)
    [ "$newest" = "GLIBC_$max_glibc" ] || [ "$top" = "GLIBC_$max_glibc" ] || { echo "FAIL $f: needs $top (> GLIBC_$max_glibc)"; bad=1; }
  fi
done < <(find "$dir" -type f -name '*.so*' -print0)
[ "$n" -gt 0 ] || { echo "FAIL: no .so files under $dir"; exit 1; }
[ "$bad" -eq 0 ] && echo "OK $n files"
exit "$bad"
