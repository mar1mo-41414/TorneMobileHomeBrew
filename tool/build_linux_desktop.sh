#!/bin/bash
# Build the Linux desktop app and package it as a tar.gz.
#
# Run this ON a Linux machine (the build host), from anywhere:
#   tool/build_linux_desktop.sh
# Output: build/TorneMobileHomeBrew-linux-<version>.tar.gz
#
# Why the sysroot dance (plan 44.3 — a trap that was actually hit):
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
tar czf "build/TorneMobileHomeBrew-linux-${VERSION}.tar.gz" \
  -C build "TorneMobileHomeBrew-linux"
echo "built: build/TorneMobileHomeBrew-linux-${VERSION}.tar.gz"
