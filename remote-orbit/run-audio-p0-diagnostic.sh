#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
APP_PATH="${1:-/Applications/RemoteOrbit.app}"
APP_BINARY="$APP_PATH/Contents/MacOS/RemoteOrbit"
SOURCE_HEAD="$(git -C "$SCRIPT_DIR" rev-parse HEAD)"

"$SCRIPT_DIR/verify-audio-p0-diagnostic-build.sh" "$APP_PATH"

LOG_DIR="$HOME/Library/Logs/RemoteOrbit"
umask 077
/bin/mkdir -p "$LOG_DIR"
LOG_PATH="$(/usr/bin/mktemp "$LOG_DIR/audio-p0-$(/bin/date '+%Y%m%d-%H%M%S').XXXXXX")"
print "Diagnostic log: $LOG_PATH"
print "Wait for [AUDIO-PATH] DIAGNOSTIC_BUILD head=$SOURCE_HEAD instrumentation=p0 before sampling."
REMOTE_ORBIT_DIAGNOSTICS=1 "$APP_BINARY" >"$LOG_PATH" 2>&1 &
APP_PID=$!
/usr/bin/tail -f "$LOG_PATH" &
TAIL_PID=$!
trap 'kill "$TAIL_PID" 2>/dev/null || true' EXIT

BUILD_MARKER="[AUDIO-PATH] DIAGNOSTIC_BUILD head=$SOURCE_HEAD instrumentation=p0"
for attempt in {1..100}; do
    if /usr/bin/grep -F "$BUILD_MARKER" "$LOG_PATH" >/dev/null; then
        print "EXACT_DIAGNOSTIC_BUILD_GATE=PASS"
        wait "$APP_PID"
        exit $?
    fi
    if ! kill -0 "$APP_PID" 2>/dev/null; then
        if wait "$APP_PID"; then
            APP_STATUS=0
        else
            APP_STATUS=$?
        fi
        print -u2 "Launch exited before the exact diagnostic build marker appeared (status=$APP_STATUS)."
        exit 1
    fi
    /bin/sleep 0.1
done

kill "$APP_PID" 2>/dev/null || true
wait "$APP_PID" 2>/dev/null || true
print -u2 "Launch did not emit the exact diagnostic build marker within 10 seconds."
exit 1
