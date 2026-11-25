import Darwin
import Dispatch
import Foundation
import RemoteOrbitHIDHelper

setvbuf(stdout, nil, _IONBF, 0)
setvbuf(stderr, nil, _IONBF, 0)

let socketPath = ProcessInfo.processInfo.environment["REMOTE_ORBIT_HID_SOCKET_PATH"]
    ?? RemoteOrbitHIDIPCContract.defaultSocketPath

let transport = KarabinerVirtualHIDTransport()
// The root LaunchDaemon runs outside the GUI WindowServer session; physical
// modifier conflict checks are enforced by VoiceShortcutHIDSessionOwner inside
// the GUI app process before every begin request.
let manager = RemoteOrbitHIDHelperSessionManager(
    transport: transport,
    physicalModifierKeyCodesProvider: { [] }
)
let server = RemoteOrbitHIDUnixSocketServer(
    socketPath: socketPath,
    socketMode: 0o666,
    manager: manager,
    peerAuthPolicy: .production
)

transport.setStateObserver { state in
    print(
        "[HID-DAEMON] state generation=\(state.connectionGeneration) "
            + "connected=\(state.serviceConnected) keyboardReady=\(state.keyboardReady)"
    )
    server.broadcastStatus(state)
}

guard server.start() else {
    fputs("[HID-DAEMON] failed to bind socket at \(socketPath)\n", stderr)
    exit(1)
}

transport.start()
print("[HID-DAEMON] listening at \(socketPath)")

signal(SIGTERM, SIG_IGN)
signal(SIGINT, SIG_IGN)
let termSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
let intSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
let shutdown = {
    print("[HID-DAEMON] shutting down")
    server.stop()
    transport.stop()
    exit(0)
}
termSource.setEventHandler(handler: shutdown)
intSource.setEventHandler(handler: shutdown)
termSource.resume()
intSource.resume()

dispatchMain()
