#!/bin/sh
# Builds a host copy of the native AES code so the dart:ffi binding
# and the C implementation can be verified on a development machine
# (test/native_aes_test.dart loads the result).
#
# The Android build compiles the same source file into
# libtmhb_fcntl.so via android/app/src/main/cpp/CMakeLists.txt;
# this script exists only for host-side verification and its output
# (build/native_test/) is not shipped.
set -eu
cd "$(dirname "$0")/.."
mkdir -p build/native_test
cc -O2 -Wall -Wextra -shared -fPIC \
  -o build/native_test/libtmhb_aes.so \
  android/app/src/main/cpp/tmhb_aes.c
echo "built build/native_test/libtmhb_aes.so"
