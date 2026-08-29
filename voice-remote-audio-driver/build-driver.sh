#!/bin/zsh
set -euo pipefail

# Build the independent VoiceRemoteAudio driver from pinned BlackHole source.
# BlackHole's binary layout changes between releases, so byte patching an
# installed binary is intentionally avoided here.
BLACKHOLE_VERSION="0.7.1"
SCRIPT_DIR="${0:A:h}"
BUILD_DIR="$SCRIPT_DIR/build"
OUTPUT_DRIVER="$BUILD_DIR/VoiceRemoteAudio.driver"
BUNDLE_ID="audio.local.VoiceRemoteAudio2chXX"

if ! command -v xcodebuild >/dev/null 2>&1; then
  print -u2 "Missing xcodebuild. Install Xcode Command Line Tools first."
  exit 1
fi

TASK_TMPDIR="$(mktemp -d /private/tmp/voiceremotebridge-blackhole.XXXXXX)"
trap 'rm -rf "$TASK_TMPDIR"' EXIT

ARCHIVE="$TASK_TMPDIR/BlackHole-$BLACKHOLE_VERSION.tar.gz"
SOURCE_ROOT="$TASK_TMPDIR/BlackHole-$BLACKHOLE_VERSION"
SOURCE_URL="https://github.com/ExistentialAudio/BlackHole/archive/refs/tags/v$BLACKHOLE_VERSION.tar.gz"

curl -fsSL "$SOURCE_URL" -o "$ARCHIVE"
tar -xzf "$ARCHIVE" -C "$TASK_TMPDIR"

# Doubao ignores devices reported as virtual. Keep the outer Audio Box virtual
# (required by the HAL plug-in) but expose the actual Audio Device as USB.
perl -0777 -pi -e \
  's/(case kAudioDevicePropertyTransportType:.*?\*\(\(UInt32\*\)outData\) = )kAudioDeviceTransportTypeVirtual;/$1kAudioDeviceTransportTypeUSB;/s' \
  "$SOURCE_ROOT/BlackHole/BlackHole.c"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

DEFINITIONS='kNumber_Of_Channels=2 kPlugIn_BundleID=\"audio.local.VoiceRemoteAudio2chXX\" kDriver_Name=\"VoiceRemote Mic\"'
xcodebuild \
  -project "$SOURCE_ROOT/BlackHole.xcodeproj" \
  -configuration Release \
  -target BlackHole \
  CONFIGURATION_BUILD_DIR="$TASK_TMPDIR/xcode-build" \
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
  CODE_SIGNING_ALLOWED=NO \
  "GCC_PREPROCESSOR_DEFINITIONS=$DEFINITIONS"

ditto "$TASK_TMPDIR/xcode-build/BlackHole.driver" "$OUTPUT_DRIVER"
PLIST="$OUTPUT_DRIVER/Contents/Info.plist"

/usr/libexec/PlistBuddy -c "Set :CFBundleName VoiceRemoteAudio" "$PLIST"
/usr/libexec/PlistBuddy -c "Delete :CFPlugInFactories" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFPlugInFactories:1A0861D7-CB3C-4DD2-A529-9AB081AF912C string BlackHole_Create" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFPlugInTypes:443ABAB8-E7B3-491A-B985-BEB9187030DB:0 1A0861D7-CB3C-4DD2-A529-9AB081AF912C" "$PLIST"

codesign --force --deep --sign - --timestamp=none "$OUTPUT_DRIVER"
codesign --verify --deep --strict --verbose=2 "$OUTPUT_DRIVER"

print "Built: $OUTPUT_DRIVER"
print "Bundle ID: $(defaults read "$PLIST" CFBundleIdentifier)"
print "Architectures: $(lipo -archs "$OUTPUT_DRIVER/Contents/MacOS/BlackHole")"
