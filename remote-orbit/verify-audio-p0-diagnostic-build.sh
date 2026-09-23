#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
APP_PATH="${1:-/Applications/RemoteOrbit.app}"
APP_BINARY="$APP_PATH/Contents/MacOS/RemoteOrbit"
APP_INFO="$APP_PATH/Contents/Info.plist"

if [[ ! -x "$APP_BINARY" || ! -f "$APP_INFO" ]]; then
    print -u2 "Diagnostic app is missing: $APP_PATH"
    exit 1
fi

SOURCE_HEAD="$(git -C "$SCRIPT_DIR" rev-parse HEAD)"
if [[ -n "$(git -C "$SCRIPT_DIR" status --porcelain)" ]]; then
    print -u2 "Source worktree is not clean; refusing exact-build verification."
    exit 1
fi

INSTALLED_HEAD="$(/usr/libexec/PlistBuddy \
    -c 'Print :RemoteOrbitDiagnosticSourceHead' "$APP_INFO" 2>/dev/null || true)"
if [[ "$INSTALLED_HEAD" != "$SOURCE_HEAD" ]]; then
    print -u2 "Installed app source head mismatch: expected=$SOURCE_HEAD actual=${INSTALLED_HEAD:-UNSTAMPED}"
    exit 1
fi

BUNDLE_ID="$(/usr/libexec/PlistBuddy \
    -c 'Print :CFBundleIdentifier' "$APP_INFO")"
if [[ "$BUNDLE_ID" != "com.lost0rz.RemoteOrbit" ]]; then
    print -u2 "Unexpected bundle identity: $BUNDLE_ID"
    exit 1
fi

codesign --verify --deep --strict "$APP_PATH"
for marker in BLE_DECODE_SUMMARY AUDIOPIPE_SUMMARY DIAGNOSTIC_BUILD; do
    if ! /usr/bin/strings "$APP_BINARY" | /usr/bin/grep -F "$marker" >/dev/null; then
        print -u2 "Installed executable lacks diagnostics marker: $marker"
        exit 1
    fi
done

print "SOURCE_HEAD=$SOURCE_HEAD"
print "INSTALLED_DIAGNOSTIC_BUILD=VERIFIED"
print "APP=$APP_PATH"
