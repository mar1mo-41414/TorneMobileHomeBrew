FROM debian:12

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential git curl ca-certificates pkg-config meson ninja-build \
      nasm autoconf automake libtool patchelf python3 xz-utils file \
      libass-dev libpng-dev libgl-dev libegl-dev libopengl-dev \
      libasound2-dev libpulse-dev zlib1g-dev python3-jinja2 \
    && rm -rf /var/lib/apt/lists/*
