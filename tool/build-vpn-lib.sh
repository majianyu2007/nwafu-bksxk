#!/usr/bin/env bash
# Builds nwafu-connect's embeddable library and copies it into
# packages/nwafu_connect_ffi/prebuilt/<platform>/ for the app to bundle.
# Usage: tool/build-vpn-lib.sh [macos|ios|android|linux|windows|all]
# NWAFU_CONNECT_DIR defaults to ../nwafu-connect (branch embed-lib).
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
src="${NWAFU_CONNECT_DIR:-$here/../nwafu-connect}"
out="$here/packages/nwafu_connect_ffi/prebuilt"
target="${1:-macos}"
build() { (cd "$src" && scripts/build-lib.sh "$1"); }
case "$target" in
  macos)
    build macos
    mkdir -p "$out/macos" && cp "$src/build/macos/libnwafuconnect.dylib" "$out/macos/" ;;
  ios)
    build ios
    mkdir -p "$out/ios" && rm -rf "$out/ios/NwafuConnect.xcframework" &&
      cp -R "$src/build/ios/NwafuConnect.xcframework" "$out/ios/" ;;
  android)
    build android
    for abi in arm64-v8a armeabi-v7a x86_64; do
      mkdir -p "$out/android/$abi" && cp "$src/build/android/$abi/libnwafuconnect.so" "$out/android/$abi/"
    done ;;
  linux)
    build linux
    mkdir -p "$out/linux" && cp "$src/build/linux/libnwafuconnect.so" "$out/linux/" ;;
  windows)
    build windows
    mkdir -p "$out/windows" && cp "$src/build/windows/nwafuconnect.dll" "$out/windows/" ;;
  all) for t in macos ios android; do "$0" "$t"; done ;;
  *) echo "unknown target $target" >&2; exit 2 ;;
esac
echo "prebuilt → $out"
