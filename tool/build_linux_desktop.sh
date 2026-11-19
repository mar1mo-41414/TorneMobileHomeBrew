#!/bin/bash
# Build the Linux desktop app and package it as a tar.gz.
#
# Run this ON a Linux machine (the build host), from anywhere:
#   tool/build_linux_desktop.sh
# Output: build/TorneMobileHomeBrew-linux-<version>.tar.gz
#
# Why the sysroot dance (plan 47.3 — a trap that was actually hit):
# media_kit's CMake locates libmpv via pkg_check_modules, which
# needs libmpv-dev. The build host has only the runtime library
# and packages are not installed with sudo here, so the .deb is
# downloaded and extracted into a local sysroot and its mpv.pc is
# rewritten:
#
#   - prefix must point at the sysroot, or the -L/-I flags resolve
#     against /usr where the dev symlink does not exist.
#   - Requires.private must be deleted: `pkg-config --exists`
#     otherwise fails on the missing private .pc files, CMake's
#     pkg_check_modules then fails SILENTLY, and the build only
#     dies at generate time with PkgConfig::mpv not found.
#   - the system runtime libmpv.so.2 must be copied into the
#     sysroot because the dev package's libmpv.so is a symlink
#     to it.
#
# The sysroot is cached under build/linux-sysroot (override with
# TMHB_LINUX_SYSROOT). The version in the tar name is read from
# pubspec.yaml.
#
# The package also bundles the custom ARIB-capable libmpv (plan
# 62.5 / 82), so subtitles also work on Debian, whose ffmpeg has
# no libaribb24 decoder: the archive's libraries are staged into
# lib/, and libmedia_kit_video_plugin.so — which links libmpv.so.2
# itself — gets its build-tree RUNPATH rewritten to $ORIGIN so the
# loader resolves libmpv.so.2 to the bundled copy instead of a
# system one. The archive comes from this repo's GitHub release
# and is verified by SHA-256, like the other platforms' libmpv
# archives. The sysroot above is only about build-time
# headers/linking and is unaffected by the bundling.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(grep '^version:' pubspec.yaml | sed 's/version: *//; s/+.*//')
SYSROOT="${TMHB_LINUX_SYSROOT:-$PWD/build/linux-sysroot}"
PKGDIR="$SYSROOT/usr/lib/x86_64-linux-gnu/pkgconfig"

if [ ! -f "$PKGDIR/mpv.pc" ]; then
  mkdir -p "$SYSROOT"
  (cd "$SYSROOT" && apt-get download libmpv-dev && dpkg-deb -x libmpv-dev_*.deb .)
  sed -i "s|^prefix=.*|prefix=$SYSROOT/usr|" "$PKGDIR/mpv.pc"
  sed -i '/^Requires\.private:/d' "$PKGDIR/mpv.pc"
  cp /usr/lib/x86_64-linux-gnu/libmpv.so.2 "$SYSROOT/usr/lib/x86_64-linux-gnu/"
fi

export PKG_CONFIG_PATH="$PKGDIR"
flutter build linux --release

STAGE="build/TorneMobileHomeBrew-linux"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -r build/linux/x64/release/bundle/. "$STAGE/"
cp linux/torne-mobile-hb.desktop "$STAGE/"

LIBMPV_TAG="libmpv-linux-v0.38.0-arib1"
LIBMPV_SHA256="2a27855f292ebcfce7266e474af790e02606e47f3fb578aefe4e7ff5c19c08f1"
LIBMPV_CACHE="build/libmpv-linux/$LIBMPV_TAG"
if [ ! -f "$LIBMPV_CACHE/.done" ]; then
  mkdir -p "$LIBMPV_CACHE"
  curl -fsSL -o "$LIBMPV_CACHE/$LIBMPV_TAG.tar.gz" \
    "https://github.com/mar1mo-41414/TorneMobileHomeBrew/releases/download/$LIBMPV_TAG/$LIBMPV_TAG.tar.gz"
  echo "$LIBMPV_SHA256  $LIBMPV_CACHE/$LIBMPV_TAG.tar.gz" | sha256sum -c -
  tar xzf "$LIBMPV_CACHE/$LIBMPV_TAG.tar.gz" -C "$LIBMPV_CACHE"
  touch "$LIBMPV_CACHE/.done"
fi
cp -a "$LIBMPV_CACHE"/lib*.so* "$STAGE/lib/"

# libmedia_kit_video_plugin.so links libmpv.so.2 itself, with a
# RUNPATH baked at build time that points into the build tree (the
# flutter ephemeral dir and the sysroot above). On a user's machine
# those paths do not exist and the loader falls back to a system
# libmpv — or cannot load the plugin at all where none is installed
# (the Debian case this bundling exists for). Point the plugin at
# the bundle's own lib/ so it resolves to the copy staged above.
PATCHELF="$(command -v patchelf || true)"
if [ -z "$PATCHELF" ]; then
  # Same no-sudo pattern as the sysroot: fetch the .deb, extract it.
  PATCHELF_DIR="$SYSROOT/patchelf"
  if [ ! -x "$PATCHELF_DIR/usr/bin/patchelf" ]; then
    mkdir -p "$PATCHELF_DIR"
    (cd "$PATCHELF_DIR" && apt-get download patchelf && dpkg-deb -x patchelf_*.deb .)
  fi
  PATCHELF="$PATCHELF_DIR/usr/bin/patchelf"
fi
"$PATCHELF" --set-rpath '$ORIGIN' "$STAGE/lib/libmedia_kit_video_plugin.so"

tar czf "build/TorneMobileHomeBrew-linux-${VERSION}.tar.gz" \
  -C build "TorneMobileHomeBrew-linux"
echo "built: build/TorneMobileHomeBrew-linux-${VERSION}.tar.gz"
