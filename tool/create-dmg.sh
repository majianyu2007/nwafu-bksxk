#!/usr/bin/env bash
set -euo pipefail

# Packages the Flutter macOS release app into a drag-to-Applications DMG.
# Usage:
#   tool/create-dmg.sh [path/to/app] [path/to/output.dmg]
# Defaults assume `flutter build macos --release` has just completed.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="西农本科选课"
DEFAULT_APP="$ROOT_DIR/build/macos/Build/Products/Release/$APP_NAME.app"
DEFAULT_DMG="$ROOT_DIR/build/macos/$APP_NAME.dmg"
APP_PATH="${1:-$DEFAULT_APP}"
DMG_PATH="${2:-$DEFAULT_DMG}"

if [[ ! -d "$APP_PATH" ]]; then
  printf 'App bundle not found: %s\n' "$APP_PATH" >&2
  printf 'Run `flutter build macos --release` first, or pass the .app path.\n' >&2
  exit 1
fi

STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nwafu-bksxk-dmg.XXXXXX")"
cleanup() { rm -rf "$STAGE_DIR"; }
trap cleanup EXIT INT TERM

mkdir -p "$(dirname "$DMG_PATH")"
rm -f "$DMG_PATH"

# `ditto` preserves bundle metadata, resource forks, permissions, and symlinks.
ditto "$APP_PATH" "$STAGE_DIR/$APP_NAME.app"

# Finder presents this beside the app, giving users the standard drag target.
ln -s /Applications "$STAGE_DIR/Applications"

hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGE_DIR" \
  -format UDZO \
  -ov \
  "$DMG_PATH"

printf 'Created DMG: %s\n' "$DMG_PATH"
