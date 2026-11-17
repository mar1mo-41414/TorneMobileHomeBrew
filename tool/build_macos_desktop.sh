#!/bin/bash
# Build the macOS desktop app and package it as a zip.
#
# Run this ON the Mac, from anywhere:
#   tool/build_macos_desktop.sh
# Output: ~/Desktop/TorneMobileHomeBrew-macos-<version>.zip
# (plus the built .app under build/macos/Build/Products/Release/)
#
# Why it looks like this (plan 47 — every step is a trap that was
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
#    by dyld, so it is signed below. The signature must NOT carry
#    keychain-access-groups: an app whose signature contains it is
#    refused by launchd at spawn time (RBSRequestErrorDomain 5 /
#    NSPOSIXErrorDomain 163), even though `codesign --verify`
#    passes. Credential storage does not need the entitlement —
#    the app uses the legacy login keychain on macOS (plan 47).
#    The signing step therefore applies the dedicated minimal set
#    in macos/Runner/Signing.entitlements, not the Runner
#    entitlements files. That set carries exactly one entitlement,
#    com.apple.security.files.user-selected.read-only, which
#    file_picker's macOS plugin requires before it will open a
#    file panel at all (plan 69).
#
# 3. The version in the zip name is read from pubspec.yaml.
#
# 4. Signing identity (plan 66): the build prefers the fixed
#    self-signed code-signing identity "torne-mobile-hb-signing"
#    from the login keychain. An ad-hoc signature changes the
#    app's cdhash on every build, so the keychain's "Always
#    Allow" for the stored DTCP credentials never carries over
#    and the user is asked for the keychain password on every
#    rebuild. With a fixed certificate the designated
#    requirement is stable, and the permission sticks. When the
#    identity is not installed, the script falls back to ad-hoc
#    signing (with a warning) so the build still works.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(grep '^version:' pubspec.yaml | sed 's/version: *//; s/+.*//')
APP="build/macos/Build/Products/Release/torne mobile HB.app"
ZIP="$HOME/Desktop/TorneMobileHomeBrew-macos-${VERSION}.zip"
SIGN_IDENTITY="torne-mobile-hb-signing"
SIGN_ENTITLEMENTS="macos/Runner/Signing.entitlements"

flutter build macos --config-only --release
xcodebuild -workspace macos/Runner.xcworkspace -scheme Runner \
  -configuration Release -derivedDataPath build/macos \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build

if security find-identity -v -p codesigning 2>/dev/null | grep -q "\"$SIGN_IDENTITY\""; then
  echo "signing with identity: $SIGN_IDENTITY"
  codesign --force --deep --timestamp=none \
    --entitlements "$SIGN_ENTITLEMENTS" --sign "$SIGN_IDENTITY" "$APP"
else
  echo "WARNING: code-signing identity '$SIGN_IDENTITY' not found;" >&2
  echo "falling back to ad-hoc signing. The login keychain will" >&2
  echo "ask for its password again after every rebuild (plan 66)." >&2
  codesign --force --deep \
    --entitlements "$SIGN_ENTITLEMENTS" --sign - "$APP"
fi
codesign --verify --deep --strict "$APP"

# Guard against the plan-47 trap: if keychain-access-groups ever
# sneaks back into the signature, the app will not launch.
if codesign -d --entitlements - "$APP" 2>/dev/null | grep -q keychain-access-groups; then
  echo "ERROR: keychain-access-groups present in signature;" >&2
  echo "launchd will refuse to spawn this app (plan 47)." >&2
  exit 1
fi

rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "built: $ZIP"
