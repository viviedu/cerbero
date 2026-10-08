#!/bin/bash
# Check every *.so* under $1 is ARMv7 hard-float NEON and needs no glibc newer than 2.36.
set -uo pipefail
dir="${1:?usage: check-elf.sh <dir>}"
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
