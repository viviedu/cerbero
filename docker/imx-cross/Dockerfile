FROM --platform=linux/arm64 debian:bookworm

WORKDIR /workspace

ENV DEBIAN_FRONTEND noninteractive

# Cerbero host prerequisites (as .buildkite/Dockerfile.bootstrap) plus the Debian armhf cross toolchain
RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y \
        python3 \
        python3-distro \
        python3-venv \
        python3-pip \
        python3-setuptools \
        binutils \
        build-essential \
        curl \
        sudo \
        git \
        file \
        xz-utils \
        gcc-arm-linux-gnueabihf \
        g++-arm-linux-gnueabihf \
        binutils-arm-linux-gnueabihf \
        && \
    apt-get clean

# Host packages cerbero's DebianBootstrapper would install (containers are ephemeral, so bake them in)
RUN apt-get update && \
    apt-get install -y \
        autoconf \
        automake \
        autopoint \
        autotools-dev \
        bison \
        build-essential \
        ccache \
        cmake \
        flex \
        g++ \
        gettext \
        git \
        gperf \
        libasound2-dev \
        libegl1-mesa-dev \
        libgl1-mesa-dev \
        libglu1-mesa-dev \
        libpulse-dev \
        libssl-dev \
        libtool \
        libx11-dev \
        libx11-xcb-dev \
        libxcomposite-dev \
        libxdamage-dev \
        libxext-dev \
        libxfixes-dev \
        libxi-dev \
        libxrandr-dev \
        libxrender-dev \
        libxtst-dev \
        libxv-dev \
        make \
        nasm \
        ninja-build \
        pkg-config \
        python3-dev \
        python3-setuptools \
        wget \
        x11proto-record-dev \
        xutils-dev \
        && \
    apt-get clean

CMD ["bash"]
