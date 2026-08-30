#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
APP="$SCRIPT_DIR/dist/RemoteOrbit.app"
CONTENTS="$APP/Contents"

cd "$SCRIPT_DIR"
swift build -c release

# Generate the native macOS icon as part of every reproducible app build.
"$SCRIPT_DIR/Packaging/generate-icon.sh" "$SCRIPT_DIR/dist"

rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$SCRIPT_DIR/.build/release/RemoteOrbit" "$CONTENTS/MacOS/RemoteOrbit"
cp "$SCRIPT_DIR/Packaging/Info.plist" "$CONTENTS/Info.plist"
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
