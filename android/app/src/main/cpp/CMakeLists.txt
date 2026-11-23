cmake_minimum_required(VERSION 3.22.1)

project(tmhb_fcntl C)

# tmhb_aes.c is the AES-128-CBC decryption used through dart:ffi by
# the DTCP streaming path (lib/core/dtcp/native_aes.dart); it shares
# this library with the JNI fcntl bridge so the app ships one .so.
add_library(tmhb_fcntl SHARED tmhb_fcntl.c tmhb_aes.c)
target_compile_options(tmhb_fcntl PRIVATE -O3)
