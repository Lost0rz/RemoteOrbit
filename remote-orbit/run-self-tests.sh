#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
OUTPUT="$SCRIPT_DIR/.build/remote-orbit-self-test"

mkdir -p "${OUTPUT:h}"
swiftc \
  "$SCRIPT_DIR/Sources/RemoteOrbit/ATVV/BridgeError.swift" \
  "$SCRIPT_DIR/Sources/RemoteOrbit/AudioPipePlayoutReserve.swift" \
  "$SCRIPT_DIR/Sources/RemoteOrbit/AudioDataPlaneDiagnostics.swift" \
  "$SCRIPT_DIR/Sources/RemoteOrbit/ATVV/ADPCMDecoder.swift" \
  "$SCRIPT_DIR/Sources/RemoteOrbit/ATVV/ATVVProtocol.swift" \
  "$SCRIPT_DIR/SelfTests/main.swift" \
  -o "$OUTPUT"
"$OUTPUT"
