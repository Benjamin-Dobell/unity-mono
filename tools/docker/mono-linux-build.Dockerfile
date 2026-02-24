FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    autoconf \
    automake \
    bison \
    build-essential \
    ca-certificates \
    clang \
    cmake \
    flex \
    gawk \
    gettext \
    git \
    libglib2.0-dev \
    libssl-dev \
    libtool \
    m4 \
    make \
    perl \
    pkg-config \
    python3 \
    wget \
    xz-utils \
    zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace
