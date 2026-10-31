#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
OUTPUT_DIR="${1:-$SCRIPT_DIR/../dist}"
PNG="$OUTPUT_DIR/RemoteOrbit-1024.png"
ICONSET="$OUTPUT_DIR/RemoteOrbit.iconset"
ICNS="$OUTPUT_DIR/RemoteOrbit.icns"
SOURCE_SVG="$SCRIPT_DIR/../Brand/RemoteOrbitMark.svg"

if [[ ! -f "$SOURCE_SVG" ]]; then
  print -u2 "Missing canonical icon source: $SOURCE_SVG"
  exit 1
fi

mkdir -p "$OUTPUT_DIR"
ICON_CACHE="$(mktemp -d /private/tmp/remoteorbit-icon-cache.XXXXXX)"
trap 'rm -rf "$ICON_CACHE"' EXIT
SWIFT_MODULECACHE_PATH="$ICON_CACHE" \
CLANG_MODULE_CACHE_PATH="$ICON_CACHE" \
  swift "$SCRIPT_DIR/generate-icon.swift" "$PNG" "$SOURCE_SVG"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"

sips -z 16 16 "$PNG" --out "$ICONSET/icon_16x16.png" >/dev/null
sips -z 32 32 "$PNG" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$PNG" --out "$ICONSET/icon_32x32.png" >/dev/null
sips -z 64 64 "$PNG" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$PNG" --out "$ICONSET/icon_128x128.png" >/dev/null
sips -z 256 256 "$PNG" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$PNG" --out "$ICONSET/icon_256x256.png" >/dev/null
sips -z 512 512 "$PNG" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$PNG" --out "$ICONSET/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$PNG" --out "$ICONSET/icon_512x512@2x.png" >/dev/null

SWIFT_MODULECACHE_PATH="$ICON_CACHE" \
CLANG_MODULE_CACHE_PATH="$ICON_CACHE" \
  swift "$SCRIPT_DIR/generate-icns.swift" "$ICONSET" "$ICNS"
rm -rf "$ICONSET" "$PNG"
print "Generated: $ICNS"
