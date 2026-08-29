#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/voice-remote-bridge/Packaging/Info.plist")"
DIST="$ROOT/dist"
PACKAGE_ROOT="$DIST/VoiceRemoteBridge-$VERSION-pkg-root"
PACKAGE_SCRIPTS="$DIST/VoiceRemoteBridge-$VERSION-pkg-scripts"
PACKAGE_EXPANDED="$DIST/VoiceRemoteBridge-$VERSION-pkg-expanded"
PACKAGE_CLEAN="$DIST/VoiceRemoteBridge-$VERSION-clean.pkg"
COMPONENT_PACKAGE="$DIST/VoiceRemoteBridge-$VERSION-component.pkg"
DISTRIBUTION="$DIST/VoiceRemoteBridge-$VERSION-Distribution.xml"
PACKAGE="$DIST/VoiceRemoteBridge-$VERSION.pkg"
STAGING="$DIST/VoiceRemoteBridge-$VERSION-dmg-root"
OUTPUT="$DIST/VoiceRemoteBridge-$VERSION.dmg"
REBUILD_DRIVER=1

while (($# > 0)); do
    case "$1" in
        --reuse-driver)
            REBUILD_DRIVER=0
            shift
            ;;
        *)
            print -u2 "Usage: $0 [--reuse-driver]"
            exit 64
            ;;
    esac
done

if ((REBUILD_DRIVER)); then
    "$ROOT/voice-remote-audio-driver/build-driver.sh"
fi

"$ROOT/voice-remote-bridge/package-app.sh"

APP_SOURCE="$ROOT/voice-remote-bridge/dist/VoiceRemoteBridge.app"
DRIVER_SOURCE="$ROOT/voice-remote-audio-driver/build/VoiceRemoteAudio.driver"
if [[ ! -d "$APP_SOURCE" || ! -d "$DRIVER_SOURCE" ]]; then
    print -u2 "Build outputs are missing. Build the app and driver first."
    exit 1
fi

rm -rf "$PACKAGE_ROOT" "$PACKAGE_SCRIPTS" "$PACKAGE_EXPANDED" \
    "$PACKAGE_CLEAN" "$COMPONENT_PACKAGE" "$DISTRIBUTION" \
    "$PACKAGE" "$STAGING" "$OUTPUT"
mkdir -p \
    "$PACKAGE_ROOT/Applications" \
    "$PACKAGE_ROOT/Library/Audio/Plug-Ins/HAL"
ditto --norsrc --noextattr --noqtn \
    "$APP_SOURCE" "$PACKAGE_ROOT/Applications/VoiceRemoteBridge.app"
ditto --norsrc --noextattr --noqtn \
    "$DRIVER_SOURCE" "$PACKAGE_ROOT/Library/Audio/Plug-Ins/HAL/VoiceRemoteAudio.driver"
find "$PACKAGE_ROOT" -name '._*' -delete

mkdir -p "$PACKAGE_SCRIPTS"
cp "$ROOT/installer/pkg-scripts/preinstall" "$PACKAGE_SCRIPTS/preinstall"
cp "$ROOT/installer/pkg-scripts/postinstall" "$PACKAGE_SCRIPTS/postinstall"
chmod 755 "$PACKAGE_SCRIPTS/preinstall" "$PACKAGE_SCRIPTS/postinstall"
/usr/bin/xattr -c "$PACKAGE_SCRIPTS/preinstall" "$PACKAGE_SCRIPTS/postinstall" 2>/dev/null || true
find "$PACKAGE_SCRIPTS" -name '._*' -delete

pkgbuild \
    --root "$PACKAGE_ROOT" \
    --scripts "$PACKAGE_SCRIPTS" \
    --identifier "com.lost0rz.VoiceRemoteBridge.installer" \
    --version "$VERSION" \
    --install-location / \
    --ownership recommended \
    "$COMPONENT_PACKAGE"

# pkgbuild may add AppleDouble provenance entries to package scripts. Remove
# those packaging-only entries while preserving the actual scripts and payload.
pkgutil --expand "$COMPONENT_PACKAGE" "$PACKAGE_EXPANDED"
find "$PACKAGE_EXPANDED/Scripts" -name '._*' -delete
pkgutil --flatten "$PACKAGE_EXPANDED" "$PACKAGE_CLEAN"
mv "$PACKAGE_CLEAN" "$COMPONENT_PACKAGE"
rm -rf "$PACKAGE_EXPANDED"

# Tell macOS Installer that this package changes CoreAudio/HAL state and must
# finish with a system restart. The component package keeps the install and
# recovery scripts; the product distribution adds the native restart action.
productbuild --synthesize --package "$COMPONENT_PACKAGE" "$DISTRIBUTION"
perl -pi -e 's/onConclusion="none"/onConclusion="RequireRestart"/' "$DISTRIBUTION"
productbuild \
    --distribution "$DISTRIBUTION" \
    --package-path "$DIST" \
    "$PACKAGE"

mkdir -p "$STAGING"
cp "$PACKAGE" "$STAGING/VoiceRemoteBridge.pkg"
cp "$ROOT/installer/DMG-README.txt" "$STAGING/Read Me First.txt"

mkdir -p "$STAGING/Documentation"
cp "$ROOT/LICENSE" "$ROOT/README.md" "$ROOT/THIRD_PARTY_NOTICES.md" \
    "$STAGING/Documentation/"

mkdir -p "$DIST"
hdiutil create \
    -volname "Voice Remote Bridge" \
    -srcfolder "$STAGING" \
    -ov \
    -format UDZO \
    "$OUTPUT"

codesign --verify --deep --strict "$PACKAGE_ROOT/Applications/VoiceRemoteBridge.app"
print "Built: $OUTPUT"
