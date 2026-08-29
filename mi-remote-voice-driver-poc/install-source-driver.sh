#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
SOURCE="$SCRIPT_DIR/build/MiRemoteVoice.driver"
DESTINATION="/Library/Audio/Plug-Ins/HAL/MiRemoteVoice.driver"
BACKUP="$SCRIPT_DIR/build/MiRemoteVoice.driver.previous"

if [[ ! -d "$SOURCE" ]]; then
    print -u2 "Missing source-built driver: $SOURCE"
    exit 1
fi

if [[ -e "$BACKUP" ]]; then
    print -u2 "Refusing to replace existing backup: $BACKUP"
    exit 2
fi

killall -TERM MiRemoteBridge 2>/dev/null || true
sleep 1

if [[ -e "$DESTINATION" ]]; then
    mv "$DESTINATION" "$BACKUP"
fi

ditto "$SOURCE" "$DESTINATION"
chown -R root:wheel "$DESTINATION"
find "$DESTINATION" -type d -exec chmod 755 {} \;
find "$DESTINATION" -type f -exec chmod 644 {} \;
chmod 755 "$DESTINATION/Contents/MacOS/BlackHole"

killall -9 coreaudiod 2>/dev/null || true

print "Installed source-built USB transport driver: $DESTINATION"
print "Previous driver backup: $BACKUP"
print "Restart macOS before testing Doubao again."
