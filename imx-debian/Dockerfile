# Native build container for the i.MX GStreamer build. It supplies tools only: every target header and
# library comes from /sysroot, copied from the image built by Dockerfile.sysroot (dome-os plus -dev packages).
ARG SYSROOT_IMAGE
FROM --platform=linux/arm/v7 ${SYSROOT_IMAGE} AS sysroot

FROM --platform=$BUILDPLATFORM debian:bookworm

WORKDIR /workspace

ENV DEBIAN_FRONTEND=noninteractive

# Host tools and the Debian armhf cross toolchain
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        binutils-arm-linux-gnueabihf \
        bison \
        build-essential \
        ca-certificates \
        file \
        flex \
        g++-arm-linux-gnueabihf \
        gcc-arm-linux-gnueabihf \
        gettext \
        git \
        libglib2.0-dev-bin \
        liborc-0.4-dev-bin \
        ninja-build \
        patch \
        pkg-config \
        python3 \
        python3-pip \
        xz-utils \
        && \
    apt-get clean

# GStreamer 1.26 needs meson >= 1.4 and bookworm ships 1.0.1; 1.9.0 matches recipes/build-tools/meson.recipe
RUN pip3 install --no-cache-dir --break-system-packages meson==1.9.0

# /usr/local is left behind on purpose: dome-os keeps hand-built pango, cairo and ffmpeg there
COPY --from=sysroot /usr/include /sysroot/usr/include
COPY --from=sysroot /usr/lib/arm-linux-gnueabihf /sysroot/usr/lib/arm-linux-gnueabihf
COPY --from=sysroot /usr/share/pkgconfig /sysroot/usr/share/pkgconfig
COPY --from=sysroot /var/lib/dpkg /sysroot/var/lib/dpkg
COPY --from=sysroot /var/lib/vivi-sysroot /sysroot/var/lib/vivi-sysroot

# Debian -dev symlinks into /lib are absolute; make them resolve inside the sysroot
RUN ln -s usr/lib /sysroot/lib && \
    find /sysroot -type l -lname '/*' | while read -r link; do \
        ln -snf "$(realpath -m --relative-to="$(dirname "$link")" "/sysroot$(readlink "$link")")" "$link"; \
    done

CMD ["bash"]
