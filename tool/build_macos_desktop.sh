#!/bin/bash
# Build the macOS desktop app and package it as a zip.
#
# Run this ON the Mac, from anywhere:
#   tool/build_macos_desktop.sh
# Output: ~/Desktop/TorneMobileHomeBrew-macos-<version>.zip
# (plus the built .app under build/macos/Build/Products/Release/)
#
# Why it looks like this (plan 44 — every step is a trap that was
# actually hit):
#
# 1. `flutter build macos --release` FAILS in this project:
#    macos/Runner/Release.entitlements makes Xcode demand a
#    development signing identity, and there is none on the build
#    machine. Passing CODE_SIGNING_ALLOWED=NO as an environment
#    variable does not help — the flutter tool does not forward
#    it. So: let flutter generate the project (--config-only),
#    then drive xcodebuild directly with signing disabled.
#
# 2. The resulting .app is unsigned; its frameworks are rejected
#    by dyld, so it is ad-hoc signed below. The signature must
#    NOT carry entitlements: an ad-hoc app whose signature
#    contains keychain-access-groups is refused by launchd at
#    spawn time (RBSRequestErrorDomain 5 / NSPOSIXErrorDomain
#    163), even though `codesign --verify` passes. Credential
#    storage does not need the entitlement — the app uses the
#    legacy login keychain on macOS (plan 44).
#
# 3. The version in the zip name is read from pubspec.yaml.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(grep '^version:' pubspec.yaml | sed 's/version: *//; s/+.*//')
APP="build/macos/Build/Products/Release/torne mobile HB.app"
ZIP="$HOME/Desktop/TorneMobileHomeBrew-macos-${VERSION}.zip"

flutter build macos --config-only --release
xcodebuild -workspace macos/Runner.xcworkspace -scheme Runner \
  -configuration Release -derivedDataPath build/macos \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build

codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"

# Guard against the plan-39 trap: if entitlements ever sneak
# back into the ad-hoc signature, the app will not launch.
if codesign -d --entitlements - "$APP" 2>/dev/null | grep -q keychain-access-groups; then
  echo "ERROR: keychain-access-groups present in ad-hoc signature;" >&2
  echo "launchd will refuse to spawn this app (plan 44)." >&2
  exit 1
fi

rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "built: $ZIP"
