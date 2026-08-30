#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/remote-orbit/Packaging/Info.plist")"
DIST="$ROOT/dist"
PACKAGE_ROOT="$DIST/RemoteOrbit-$VERSION-pkg-root"
PACKAGE_SCRIPTS="$DIST/RemoteOrbit-$VERSION-pkg-scripts"
PACKAGE_EXPANDED="$DIST/RemoteOrbit-$VERSION-pkg-expanded"
PACKAGE_CLEAN="$DIST/RemoteOrbit-$VERSION-clean.pkg"
COMPONENT_PACKAGE="$DIST/RemoteOrbit-$VERSION-component.pkg"
DISTRIBUTION="$DIST/RemoteOrbit-$VERSION-Distribution.xml"
PACKAGE="$DIST/RemoteOrbit-$VERSION.pkg"
STAGING="$DIST/RemoteOrbit-$VERSION-dmg-root"
OUTPUT="$DIST/RemoteOrbit-$VERSION.dmg"
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
    "$ROOT/remote-orbit-audio-driver/build-driver.sh"
fi

"$ROOT/remote-orbit/package-app.sh"

APP_SOURCE="$ROOT/remote-orbit/dist/RemoteOrbit.app"
DRIVER_SOURCE="$ROOT/remote-orbit-audio-driver/build/RemoteOrbitAudio.driver"
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
    "$APP_SOURCE" "$PACKAGE_ROOT/Applications/RemoteOrbit.app"
ditto --norsrc --noextattr --noqtn \
    "$DRIVER_SOURCE" "$PACKAGE_ROOT/Library/Audio/Plug-Ins/HAL/RemoteOrbitAudio.driver"
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
    --identifier "com.lost0rz.RemoteOrbit.installer" \
    --version "$VERSION" \
    --install-location / \
    --ownership recommended \
    "$COMPONENT_PACKAGE"

# pkgbuild may add AppleDouble provenance entries to package scripts. Remove
# those packaging-only entries while preserving the actual scripts and payload.
pkgutil --expand "$COMPONENT_PACKAGE" "$PACKAGE_EXPANDED"
find "$PACKAGE_EXPANDED/Scripts" -name '._*' -delete
# pkgbuild infers application bundles as relocatable when the package is
# assembled from a local staging root. That would move RemoteOrbit.app back
# into the repository instead of /Applications during installation. The
# installer payload has an explicit destination, so remove only that inferred
# relocation rule before flattening the component package again.
perl -0pi -e 's/\s*<relocate>.*?<\/relocate>//s' "$PACKAGE_EXPANDED/PackageInfo"
pkgutil --flatten "$PACKAGE_EXPANDED" "$PACKAGE_CLEAN"
mv "$PACKAGE_CLEAN" "$COMPONENT_PACKAGE"
rm -rf "$PACKAGE_EXPANDED"

# The HAL driver is reloaded by the postinstall script through coreaudiod. Do
# not force a full macOS restart: the app and driver can be installed without
# rebooting, with a reboot remaining only as a fallback if macOS does not
# publish the device after coreaudiod reload.
productbuild --synthesize --package "$COMPONENT_PACKAGE" "$DISTRIBUTION"
productbuild \
    --distribution "$DISTRIBUTION" \
    --package-path "$DIST" \
    "$PACKAGE"

mkdir -p "$STAGING"
cp "$ROOT/installer/DMG-README.txt" "$STAGING/Read Me First.txt"
# The DMG exposes one installation path: drag the app to Applications. The
# embedded driver is installed on demand from the app's Settings page when
# first-run diagnostics find it missing.
ditto --norsrc --noextattr --noqtn \
    "$APP_SOURCE" "$STAGING/RemoteOrbit.app"
ln -s /Applications "$STAGING/Applications"
# hdiutil on current macOS no longer exposes the historical -volicon flag.
# A hidden volume icon plus the custom-icon bit produces the same Finder
# result while keeping the DMG portable across supported macOS versions.
cp "$ROOT/remote-orbit/dist/RemoteOrbit.icns" "$STAGING/.VolumeIcon.icns"
SetFile -a C "$STAGING"

mkdir -p "$STAGING/Documentation"
cp "$ROOT/LICENSE" "$ROOT/README.md" "$ROOT/THIRD_PARTY_NOTICES.md" \
    "$STAGING/Documentation/"

mkdir -p "$DIST"
hdiutil create \
    -volname "RemoteOrbit" \
    -srcfolder "$STAGING" \
    -ov \
    -format UDZO \
    "$OUTPUT"

codesign --verify --deep --strict "$PACKAGE_ROOT/Applications/RemoteOrbit.app"
print "Built: $OUTPUT"
