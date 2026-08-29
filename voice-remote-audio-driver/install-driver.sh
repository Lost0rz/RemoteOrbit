#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
SOURCE="$SCRIPT_DIR/build/VoiceRemoteAudio.driver"
DESTINATION="/Library/Audio/Plug-Ins/HAL/VoiceRemoteAudio.driver"
BACKUP="$SCRIPT_DIR/build/VoiceRemoteAudio.driver.previous"

if [[ ! -d "$SOURCE" ]]; then
    print -u2 "Missing source-built driver: $SOURCE"
    exit 1
fi

if [[ -e "$BACKUP" ]]; then
    print -u2 "Refusing to replace existing backup: $BACKUP"
    exit 2
fi

killall -TERM VoiceRemoteBridge 2>/dev/null || true
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

print "Installed VoiceRemoteAudio USB transport driver: $DESTINATION"
print "Previous driver backup: $BACKUP"
print "Restart macOS before testing Doubao again."
