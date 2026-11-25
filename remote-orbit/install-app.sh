#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
SOURCE="${REMOTE_ORBIT_SOURCE_APP:-$SCRIPT_DIR/dist/RemoteOrbit.app}"
# Keep one canonical installation path. Launch-at-login and release DMGs both
# resolve this location, so a developer build cannot silently coexist with an
# older copy under ~/Applications.
DESTINATION="${REMOTE_ORBIT_INSTALL_PATH:-/Applications/RemoteOrbit.app}"

if [[ ! -d "$SOURCE" ]]; then
  print -u2 "Run package-app.sh first."
  exit 1
fi

if [[ -w "${DESTINATION:h}" ]]; then
  rm -rf "$DESTINATION"
  ditto "$SOURCE" "$DESTINATION"
else
  sudo rm -rf "$DESTINATION"
  sudo ditto "$SOURCE" "$DESTINATION"
fi
codesign --verify --deep --strict --verbose=2 "$DESTINATION"
print "Installed: $DESTINATION"
