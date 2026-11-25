#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
APP_BUNDLE_NAME="${REMOTE_ORBIT_APP_NAME:-RemoteOrbit}"
DISPLAY_NAME="${REMOTE_ORBIT_DISPLAY_NAME:-$APP_BUNDLE_NAME}"
BUNDLE_IDENTIFIER="${REMOTE_ORBIT_BUNDLE_ID:-com.lost0rz.RemoteOrbit}"
APP="$SCRIPT_DIR/dist/${APP_BUNDLE_NAME}.app"
CONTENTS="$APP/Contents"

cd "$SCRIPT_DIR"
ARM64_TRIPLE="arm64-apple-macosx13.0"
X86_64_TRIPLE="x86_64-apple-macosx13.0"
ARM64_SCRATCH="$(mktemp -d /private/tmp/remoteorbit-arm64.XXXXXX)"
X86_64_SCRATCH="$(mktemp -d /private/tmp/remoteorbit-x86_64.XXXXXX)"
trap 'rm -rf "$ARM64_SCRATCH" "$X86_64_SCRATCH"' EXIT

# Keep the distributable app compatible with both Apple Silicon and Intel Macs.
# Each slice has its own SwiftPM graph and explicit target triple so no host
# architecture or shared .build output can contaminate the other link.
swift build \
  -c release \
  --scratch-path "$ARM64_SCRATCH" \
  --triple "$ARM64_TRIPLE"
ARM64_BIN_DIR="$(swift build \
  -c release \
  --scratch-path "$ARM64_SCRATCH" \
  --triple "$ARM64_TRIPLE" \
  --show-bin-path)"
ARM64_BINARY="$ARM64_BIN_DIR/RemoteOrbit"
ARM64_DAEMON_BINARY="$ARM64_BIN_DIR/RemoteOrbitHIDHelperDaemon"
ARM64_ARCHS="$(lipo -archs "$ARM64_BINARY")"
if [[ "$ARM64_ARCHS" != "arm64" ]]; then
  print -u2 "Expected arm64-only source binary, got: $ARM64_ARCHS"
  exit 1
fi
print "ARM64 source binary: $ARM64_BINARY ($ARM64_ARCHS)"

swift build \
  -c release \
  --scratch-path "$X86_64_SCRATCH" \
  --triple "$X86_64_TRIPLE"
X86_BIN_DIR="$(swift build \
  -c release \
  --scratch-path "$X86_64_SCRATCH" \
  --triple "$X86_64_TRIPLE" \
  --show-bin-path)"
X86_BINARY="$X86_BIN_DIR/RemoteOrbit"
X86_DAEMON_BINARY="$X86_BIN_DIR/RemoteOrbitHIDHelperDaemon"
X86_64_ARCHS="$(lipo -archs "$X86_BINARY")"
if [[ "$X86_64_ARCHS" != "x86_64" ]]; then
  print -u2 "Expected x86_64-only source binary, got: $X86_64_ARCHS"
  exit 1
fi
print "X86_64 source binary: $X86_BINARY ($X86_64_ARCHS)"

# Generate the native macOS icon as part of every reproducible app build.
"$SCRIPT_DIR/Packaging/generate-icon.sh" "$SCRIPT_DIR/dist"

rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources" "$CONTENTS/Helpers"
lipo -create "$ARM64_BINARY" "$X86_BINARY" -output "$CONTENTS/MacOS/RemoteOrbit"
lipo -create "$ARM64_DAEMON_BINARY" "$X86_DAEMON_BINARY" -output "$CONTENTS/Helpers/RemoteOrbitHIDHelperDaemon"
COMBINED_ARCHS="$(lipo -archs "$CONTENTS/MacOS/RemoteOrbit")"
if [[ "$COMBINED_ARCHS" != "arm64 x86_64" && "$COMBINED_ARCHS" != "x86_64 arm64" ]]; then
  print -u2 "Expected Universal2 executable, got: $COMBINED_ARCHS"
  exit 1
fi
print "Universal2 executable: $COMBINED_ARCHS"
cp "$SCRIPT_DIR/Packaging/Info.plist" "$CONTENTS/Info.plist"
SOURCE_HEAD="$(git -C "$SCRIPT_DIR" rev-parse HEAD)"
if [[ -n "$(git -C "$SCRIPT_DIR/.." status --porcelain --untracked-files=no)" ]]; then
  SOURCE_HEAD="${SOURCE_HEAD}-dirty"
fi
/usr/libexec/PlistBuddy \
  -c "Set :RemoteOrbitDiagnosticSourceHead \"$SOURCE_HEAD\"" \
  -c "Set :CFBundleIdentifier \"$BUNDLE_IDENTIFIER\"" \
  -c "Set :CFBundleDisplayName \"$DISPLAY_NAME\"" \
  -c "Set :CFBundleName \"$DISPLAY_NAME\"" \
  "$CONTENTS/Info.plist"
cp "$SCRIPT_DIR/dist/RemoteOrbit.icns" "$CONTENTS/Resources/RemoteOrbit.icns"
chmod 755 "$CONTENTS/MacOS/RemoteOrbit" "$CONTENTS/Helpers/RemoteOrbitHIDHelperDaemon"

VIRTUAL_HID_PKG="$SCRIPT_DIR/Packaging/Karabiner-DriverKit-VirtualHIDDevice-8.6.0.pkg"
if [[ -f "$VIRTUAL_HID_PKG" ]]; then
  cp -f "$VIRTUAL_HID_PKG" "$CONTENTS/Resources/Karabiner-DriverKit-VirtualHIDDevice-8.6.0.pkg"
fi

# Bundle the currently built HAL driver so a failed first installation can be
# repaired from the app's Settings page without requiring the repository
# checkout to remain in place.
AUDIO_DRIVER="$SCRIPT_DIR/../remote-orbit-audio-driver/build/RemoteOrbitAudio.driver"
if [[ -d "$AUDIO_DRIVER" ]]; then
  ditto "$AUDIO_DRIVER" "$CONTENTS/Resources/RemoteOrbitAudio.driver"
  codesign \
    --force \
    --deep \
    --sign - \
    --timestamp=none \
    "$CONTENTS/Resources/RemoteOrbitAudio.driver"
else
  print -u2 "Warning: RemoteOrbitAudio.driver is not built; repair button will be unavailable."
fi

codesign \
  --force \
  --sign - \
  --timestamp=none \
  --identifier "com.lost0rz.RemoteOrbitHIDHelper" \
  --requirements "=designated => identifier \"com.lost0rz.RemoteOrbitHIDHelper\"" \
  "$CONTENTS/Helpers/RemoteOrbitHIDHelperDaemon"

# Give the ad-hoc build a stable designated requirement. Without this,
# codesign falls back to a CDHash-only requirement, so every rebuild looks
# like a different application to Accessibility/Input Monitoring (TCC).
codesign \
  --force \
  --sign - \
  --timestamp=none \
  --requirements "=designated => identifier \"$BUNDLE_IDENTIFIER\"" \
  "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
print "Built: $APP"
