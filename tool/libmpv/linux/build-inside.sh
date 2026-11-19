#!/bin/bash
# Build the bundled libmpv stack for Linux (plan section 62.5) inside a
# Debian 12 container: libaribb24 -> FFmpeg -> mpv, all into /opt/tmhb-libmpv,
# then assemble the shippable bundle directory at /work/bundle.
#
# Pins follow the project's other platforms (tool/libmpv/README.md):
#   libaribb24  master snapshot 5e9be272f96e00f15a2f3c5f8ba7e124862aec38,
#               version label 1.0.4 (same as Android/iOS/macOS builds)
#   FFmpeg      n6.1.2
#   mpv         v0.38.0
# The FFmpeg/mpv pairing mirrors the system stack proven in plan
# section 62.2 (Ubuntu's mpv 0.37 + FFmpeg 6.1 decode ARIB captions
# through libaribb24). mpv >= 0.38 requires libplacebo at build time,
# so libplacebo v6.338.2 (the release contemporary with mpv 0.38) is
# built from source with Vulkan/shaderc/lcms disabled: the
# distribution's libplacebo would drag libvulkan into the bundle,
# while the app only ever uses libplacebo's OpenGL backend through
# the mpv render API.
#
# Stage markers live in /work/.stamps so a failed run can resume.
# PREFIX is under /work for the same reason (the container is --rm).
set -euo pipefail

PREFIX=/work/prefix
WORK=/work
SRC="$WORK/src"
STAMPS="$WORK/.stamps"
NPROC="$(nproc)"
# Debian's meson installs into the multiarch libdir, autotools into
# lib/; both pkgconfig directories must be searchable.
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:$PREFIX/lib/x86_64-linux-gnu/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"

mkdir -p "$SRC" "$STAMPS" "$PREFIX"
cd "$SRC"

# ---------------------------------------------------------------- aribb24
if [ ! -f "$STAMPS/aribb24" ]; then
  if [ ! -d aribb24 ]; then
    git clone https://github.com/nkoriyama/aribb24.git aribb24
  fi
  cd aribb24
  git checkout 5e9be272f96e00f15a2f3c5f8ba7e124862aec38
  # Same two seds as the project's Android/Darwin builds: version label
  # 1.0.4 (FFmpeg's non-GPL pkg-config check wants "aribb24 > 1.0.3")
  # and a genuinely optional libpng check (libpng IS present here, so
  # DRCS support stays enabled).
  sed -i 's/AC_INIT(\[aribb24\], \[1.0.3\]/AC_INIT([aribb24], [1.0.4]/' configure.ac
  sed -i 's/^], \[\])$/], [PNG_CFLAGS=""; PNG_LIBS=""])/' configure.ac
  if [ -x ./bootstrap ]; then ./bootstrap; else autoreconf -fi; fi
  ./configure --prefix="$PREFIX" --enable-shared --disable-static
  make -j"$NPROC"
  make install
  cd ..
  touch "$STAMPS/aribb24"
fi

# ---------------------------------------------------------------- FFmpeg
if [ ! -f "$STAMPS/ffmpeg" ]; then
  if [ ! -d FFmpeg ]; then
    git clone --depth 1 --branch n6.1.2 https://github.com/FFmpeg/FFmpeg.git FFmpeg
  fi
  cd FFmpeg
  ./configure --prefix="$PREFIX" \
    --enable-shared --disable-static \
    --enable-version3 \
    --enable-libaribb24 --enable-decoder=libaribb24 \
    --disable-doc --disable-debug \
    --extra-ldflags="-Wl,-rpath,$PREFIX/lib"
  make -j"$NPROC"
  make install
  cd ..
  touch "$STAMPS/ffmpeg"
fi

# The section 68 lesson: never trust the configure summary, check the
# generated component table for the whole broadcast set.
echo "=== FFmpeg component check (must all be 1) ==="
for c in CONFIG_LIBARIBB24_DECODER CONFIG_MPEGTS_DEMUXER \
         CONFIG_MPEG2VIDEO_DECODER CONFIG_H264_DECODER CONFIG_AAC_DECODER \
         CONFIG_HTTP_PROTOCOL CONFIG_TCP_PROTOCOL CONFIG_FILE_PROTOCOL; do
  grep -E "^#define $c " FFmpeg/config_components.h || echo "MISSING: $c"
done

# ---------------------------------------------------------------- libplacebo
if [ ! -f "$STAMPS/libplacebo" ]; then
  if [ ! -d libplacebo ]; then
    git clone --depth 1 --branch v6.338.2 \
      https://github.com/haasn/libplacebo.git libplacebo
  fi
  cd libplacebo
  git submodule update --init
  rm -rf build
  meson setup build --prefix="$PREFIX" --buildtype=release \
    -Dvulkan=disabled -Dshaderc=disabled -Dglslang=disabled \
    -Dlcms=disabled -Dd3d11=disabled -Dxxhash=disabled \
    -Dunwind=disabled -Ddemos=false -Dtests=false -Dbench=false \
    -Dopengl=enabled
  ninja -C build
  ninja -C build install
  cd ..
  touch "$STAMPS/libplacebo"
fi

# ---------------------------------------------------------------- mpv
if [ ! -f "$STAMPS/mpv" ]; then
  if [ ! -d mpv ]; then
    git clone --depth 1 --branch v0.38.0 https://github.com/mpv-player/mpv.git mpv
  fi
  cd mpv
  rm -rf build
  meson setup build --prefix="$PREFIX" --buildtype=release \
    -Dlibmpv=true \
    -Dgl=enabled -Degl=enabled \
    -Dx11=disabled -Dwayland=disabled -Ddrm=disabled \
    -Dvulkan=disabled \
    -Dlua=disabled -Djavascript=disabled \
    -Dalsa=enabled -Dpulse=enabled -Dpipewire=disabled -Djack=disabled -Dsdl2=disabled \
    -Dvaapi=disabled -Dvdpau=disabled \
    -Dcdda=disabled -Ddvdnav=disabled -Dlibarchive=disabled -Dlibbluray=disabled \
    -Duchardet=disabled -Dzimg=disabled -Drubberband=disabled -Dlcms2=disabled
  ninja -C build
  ninja -C build install
  cd ..
  touch "$STAMPS/mpv"
fi

# ---------------------------------------------------------------- bundle
BUNDLE="$WORK/bundle"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE"
for lib in libmpv.so.2 libavcodec.so.60 libavformat.so.60 libavutil.so.58 \
           libswscale.so.7 libswresample.so.4 libavfilter.so.9 libavdevice.so.60 \
           libaribb24.so.0 libplacebo.so.338; do
  found=0
  for dir in "$PREFIX/lib" "$PREFIX/lib/x86_64-linux-gnu"; do
    if compgen -G "$dir/$lib*" > /dev/null; then
      cp -a $dir/$lib* "$BUNDLE/"
      found=1
    fi
  done
  if [ "$found" = 0 ]; then
    echo "note: $lib not present in prefix, skipped"
  fi
done
# Media-stack libraries built from distribution packages inside the
# container (Debian 12 versions). Their own dependencies (fontconfig,
# freetype, harfbuzz, fribidi for libass; zlib for libpng) belong to the
# GTK runtime stack that any host able to run the app already has.
for lib in libass.so.9 libpng16.so.16; do
  cp -a /usr/lib/x86_64-linux-gnu/$lib* "$BUNDLE/"
done

# Every bundled library finds its siblings next to itself, independent
# of how the loader was invoked.
for f in "$BUNDLE"/*.so.*; do
  if [ -f "$f" ] && [ ! -L "$f" ]; then
    patchelf --set-rpath '$ORIGIN' "$f"
    strip --strip-unneeded "$f"
  fi
done

echo "=== bundle contents ==="
ls -la "$BUNDLE"
echo "=== ldd of bundled libmpv (LD_LIBRARY_PATH=bundle) ==="
LD_LIBRARY_PATH="$BUNDLE" ldd "$BUNDLE/libmpv.so.2" || true
echo "=== max GLIBC_ symbol versions per library (must be <= 2.36) ==="
for f in "$BUNDLE"/*.so.*; do
  if [ -f "$f" ] && [ ! -L "$f" ]; then
    echo "$f: $(objdump -T "$f" | grep -oE 'GLIBC_[0-9.]+' | sort -Vu | tail -1)"
  fi
done
echo "=== libavcodec configuration string ==="
strings "$BUNDLE/libavcodec.so.60" > /tmp/avcodec-strings.txt
grep -m1 -- '--enable-libaribb24' /tmp/avcodec-strings.txt || echo "CONFIG STRING NOT FOUND"
echo "BUILD-INSIDE DONE"
