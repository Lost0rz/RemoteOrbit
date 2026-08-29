#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
OUTPUT="$SCRIPT_DIR/.build/voice-remote-self-test"

mkdir -p "${OUTPUT:h}"
swiftc \
  "$SCRIPT_DIR/Sources/VoiceRemoteBridge/ATVV/BridgeError.swift" \
  "$SCRIPT_DIR/Sources/VoiceRemoteBridge/ATVV/ADPCMDecoder.swift" \
  "$SCRIPT_DIR/Sources/VoiceRemoteBridge/ATVV/ATVVProtocol.swift" \
  "$SCRIPT_DIR/SelfTests/main.swift" \
  -o "$OUTPUT"
"$OUTPUT"
