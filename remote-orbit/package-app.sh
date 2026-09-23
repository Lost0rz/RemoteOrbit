#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
APP="$SCRIPT_DIR/dist/RemoteOrbit.app"
CONTENTS="$APP/Contents"

cd "$SCRIPT_DIR"
swift build -c release
ARM64_BINARY="$(swift build -c release --show-bin-path)/RemoteOrbit"

# Keep the distributable app compatible with both Apple Silicon and Intel Macs.
# SwiftPM builds for the host architecture by default, so compile the second
# slice in an isolated temporary scratch directory and combine the two slices
# after the application bundle has been assembled.
X86_SCRATCH="$(mktemp -d /private/tmp/remoteorbit-x86.XXXXXX)"
trap 'rm -rf "$X86_SCRATCH"' EXIT
swift build \
  -c release \
  --scratch-path "$X86_SCRATCH" \
  -Xswiftc -target \
  -Xswiftc x86_64-apple-macos13.0
X86_BINARY="$(swift build \
  -c release \
  --scratch-path "$X86_SCRATCH" \
  --show-bin-path)/RemoteOrbit"

# Generate the native macOS icon as part of every reproducible app build.
"$SCRIPT_DIR/Packaging/generate-icon.sh" "$SCRIPT_DIR/dist"

rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
lipo -create "$ARM64_BINARY" "$X86_BINARY" -output "$CONTENTS/MacOS/RemoteOrbit"
cp "$SCRIPT_DIR/Packaging/Info.plist" "$CONTENTS/Info.plist"
SOURCE_HEAD="$(git -C "$SCRIPT_DIR" rev-parse HEAD)"
/usr/libexec/PlistBuddy \
  -c "Set :RemoteOrbitDiagnosticSourceHead $SOURCE_HEAD" \
  "$CONTENTS/Info.plist"
cp "$SCRIPT_DIR/dist/RemoteOrbit.icns" "$CONTENTS/Resources/RemoteOrbit.icns"
chmod 755 "$CONTENTS/MacOS/RemoteOrbit"

# Bundle the currently built HAL driver so a failed first installation can be
# repaired from the app's Settings page without requiring the repository
# checkout to remain in place.
AUDIO_DRIVER="$SCRIPT_DIR/../remote-orbit-audio-driver/build/RemoteOrbitAudio.driver"
if [[ -d "$AUDIO_DRIVER" ]]; then
  ditto "$AUDIO_DRIVER" "$CONTENTS/Resources/RemoteOrbitAudio.driver"
else
  print -u2 "Warning: RemoteOrbitAudio.driver is not built; repair button will be unavailable."
fi

# Give the ad-hoc build a stable designated requirement. Without this,
# codesign falls back to a CDHash-only requirement, so every rebuild looks
# like a different application to Accessibility/Input Monitoring (TCC).
codesign \
  --force \
  --deep \
  --sign - \
  --timestamp=none \
  --requirements '=designated => identifier "com.lost0rz.RemoteOrbit"' \
  "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
print "Built: $APP"
