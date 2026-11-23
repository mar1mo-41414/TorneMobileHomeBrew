#!/bin/bash
# Build the Android TV (Fire TV) APK.
#
# Run this on the build host, from anywhere:
#   tool/build_tv_apk.sh
# Output: build/TorneMobileHomeBrew-dev-tv.apk (plus size/SHA-256)
#
# Why this script exists (plan 133 — a trap that was actually
# hit, twice): the app variant is chosen ONLY by the Dart entry
# point — lib/main.dart runs the standard edition,
# lib/main_tv.dart the TV edition — and nothing ties the entry
# point to the Android product flavor. `flutter build apk
# --flavor tv` sets the TV package (applicationId, minSdk) but
# still compiles lib/main.dart, so the result is a
# standard-edition app in the TV package: every variant-gated
# behaviour is silently inert (the AppTextField focus shells,
# the focus anchors, the title-detail banner cap, the TV
# default playback quality), while package-level checks
# (applicationId / version / minSdk) all look correct. The
# plan 130 and plan 132 local TV builds were made that way;
# only on-device behaviour checks told them apart from the
# correct plan 131 build. Always build the TV APK through
# this script, and verify behaviour on the device, not the
# package metadata.
set -euo pipefail
cd "$(dirname "$0")/.."

flutter build apk --release --flavor tv -t lib/main_tv.dart

OUT="build/TorneMobileHomeBrew-dev-tv.apk"
cp build/app/outputs/flutter-apk/app-tv-release.apk "$OUT"
ls -la "$OUT"
sha256sum "$OUT"
echo "built: $OUT"
