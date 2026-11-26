#!/usr/bin/env python3
# Print package=version for every Debian package in the sysroot that owns a library the staged GStreamer links to.
# Usage: runtime-deps.py <staged prefix> [sysroot]
import os
import re
import subprocess
import sys

READELF = 'arm-linux-gnueabihf-readelf'
# libsoup is loaded with dlopen and TLS comes from a GIO module, so neither appears in NEEDED
ALWAYS = {'libsoup-3.0-0', 'glib-networking'}

stage = sys.argv[1]
sysroot = sys.argv[2] if len(sys.argv) > 2 else '/sysroot'


def is_elf(path):
    with open(path, 'rb') as f:
        return f.read(4) == b'\x7fELF'


elfs = [os.path.join(d, name) for d, _, names in os.walk(stage) for name in names
        if not os.path.islink(os.path.join(d, name)) and is_elf(os.path.join(d, name))]
dynamic = subprocess.run([READELF, '-d', *elfs], check=True, capture_output=True, text=True).stdout
needed = set(re.findall(r'\(NEEDED\).*\[(.*)\]', dynamic))

packages = set(ALWAYS)
for so in sorted(needed):
    if so.startswith(('libgst', 'libges')):
        continue
    owners = subprocess.run(['dpkg', '--admindir=%s/var/lib/dpkg' % sysroot, '-S', '*/' + so],
                            capture_output=True, text=True).stdout.splitlines()
    if not owners:
        sys.exit('%s is not owned by a Debian package in the sysroot' % so)
    packages.add(owners[0].split(':')[0])

versions = dict(line.split() for line in open('%s/var/lib/vivi-sysroot/sysroot-packages.txt' % sysroot))
for package in sorted(packages):
    if package not in versions:
        sys.exit('%s is not in the sysroot package list' % package)
    print('%s=%s' % (package, versions[package]))
