import Darwin
import Dispatch
import Foundation
import Security

@_silgen_name("proc_pidpath")
private func rohid_proc_pidpath(_ pid: Int32, _ buffer: UnsafeMutableRawPointer, _ buffersize: UInt32) -> Int32

public enum RemoteOrbitHIDIPCContract {
    public static let defaultSocketDirectory = "/Library/Application Support/RemoteOrbit/run"
    public static let defaultSocketPath = "/Library/Application Support/RemoteOrbit/run/hid-helper.sock"
    public static let maxFrameBytes = 16_384
}

public struct RemoteOrbitHIDWireRequest: Codable, Equatable {
    public enum Kind: String, Codable, Equatable {
        case status
        case begin
        case release
        case recover
    }

    public let kind: Kind
    public let requestID: UUID
    public let sessionID: UUID?
    public let protocolVersion: Int?
    public let connectionGeneration: UInt64?
    public let requestSequence: UInt64?
    public let modifierKeyCodes: [UInt16]?
    public let primaryKeyUsage: UInt16?

    public init(
        kind: Kind,
        requestID: UUID = UUID(),
        sessionID: UUID? = nil,
        protocolVersion: Int? = nil,
        connectionGeneration: UInt64? = nil,
        requestSequence: UInt64? = nil,
        modifierKeyCodes: [UInt16]? = nil,
        primaryKeyUsage: UInt16? = nil
    ) {
        self.kind = kind
        self.requestID = requestID
        self.sessionID = sessionID
        self.protocolVersion = protocolVersion
        self.connectionGeneration = connectionGeneration
        self.requestSequence = requestSequence
        self.modifierKeyCodes = modifierKeyCodes
        self.primaryKeyUsage = primaryKeyUsage
    }
}

public struct RemoteOrbitHIDWireServerMessage: Codable, Equatable {
    public enum Kind: String, Codable, Equatable {
        case status
        case reply
    }

    public let kind: Kind
    public let requestID: UUID?
    public let packageVersion: String?
    public let clientProtocolVersion: Int?
    public let connectionGeneration: UInt64
    public let keyboardReady: Bool?
    public let serviceConnected: Bool?
    public let requestSequence: UInt64?
    public let outcome: Int?

    public static func status(_ state: RemoteOrbitHIDHelperTransportState, requestID: UUID? = nil) -> Self {
        Self(
            kind: .status,
            requestID: requestID,
            packageVersion: state.packageVersion,
            clientProtocolVersion: state.clientProtocolVersion,
            connectionGeneration: state.connectionGeneration,
            keyboardReady: state.keyboardReady,
            serviceConnected: state.serviceConnected,
            requestSequence: nil,
            outcome: nil
        )
    }

    public static func reply(
        requestID: UUID,
        connectionGeneration: UInt64,
        requestSequence: UInt64,
        outcome: RemoteOrbitHIDHelperOutcome
    ) -> Self {
        Self(
            kind: .reply,
            requestID: requestID,
            packageVersion: nil,
            clientProtocolVersion: nil,
            connectionGeneration: connectionGeneration,
            keyboardReady: nil,
            serviceConnected: nil,
            requestSequence: requestSequence,
            outcome: outcome.rawValue
        )
    }
}

public enum RemoteOrbitHIDWireFraming {
    public static func encode<T: Encodable>(_ value: T) -> Data? {
        guard let payload = try? JSONEncoder().encode(value),
              !payload.isEmpty,
              payload.count <= RemoteOrbitHIDIPCContract.maxFrameBytes else {
            return nil
        }
        var length = UInt32(payload.count).bigEndian
        var frame = Data(bytes: &length, count: MemoryLayout<UInt32>.size)
        frame.append(payload)
        return frame
    }

    public static func writeAll(fd: Int32, data: Data) -> Bool {
        data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return false }
            var offset = 0
            while offset < rawBuffer.count {
                let written = Darwin.write(fd, base.advanced(by: offset), rawBuffer.count - offset)
                if written > 0 {
                    offset += written
                } else if written < 0 && errno == EINTR {
                    continue
                } else if written < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) {
                    var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
                    let ready = Darwin.poll(&pfd, 1, 100)
                    if ready > 0 && (pfd.revents & Int16(POLLERR | POLLHUP | POLLNVAL)) == 0 {
                        continue
                    }
                    return false
                } else {
                    return false
                }
            }
            return true
        }
    }

    public static func configureNoSigPipe(fd: Int32) {
        var one: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
    }
}

public final class RemoteOrbitHIDFrameStreamDecoder {
    private var buffer = Data()

    public init() {}

    public enum Step {
        case frame(Data)
        case needMoreData
        case invalidFrame
    }

    public func append(_ chunk: Data) {
        buffer.append(chunk)
    }

    public func nextFrame() -> Step {
        guard buffer.count >= 4 else { return .needMoreData }
        let start = buffer.startIndex
        let b0 = UInt32(buffer[start]) << 24
        let b1 = UInt32(buffer[start + 1]) << 16
        let b2 = UInt32(buffer[start + 2]) << 8
        let b3 = UInt32(buffer[start + 3])
        let length = Int(b0 | b1 | b2 | b3)
        guard length > 0, length <= RemoteOrbitHIDIPCContract.maxFrameBytes else {
            buffer.removeAll()
            return .invalidFrame
        }
        guard buffer.count >= 4 + length else { return .needMoreData }
        let payload = Data(buffer[(start + 4)..<(start + 4 + length)])
        buffer.removeSubrange(start..<(start + 4 + length))
        return .frame(payload)
    }
}

public struct RemoteOrbitHIDPeerAuthPolicy {
    private let verifySocket: (Int32) -> Bool

    public init(verifySocket: @escaping (Int32) -> Bool) {
        self.verifySocket = verifySocket
    }

    public func isAuthorized(clientFD: Int32) -> Bool {
        verifySocket(clientFD)
    }

    /// Production fail-closed verification:
    /// 1. Kernel `LOCAL_PEERCRED` UID must equal the active non-root GUI `/dev/console` owner.
    /// 2. Kernel `LOCAL_PEERPID` executable path must resolve to `/Applications/RemoteOrbit.app`
    ///    or `/Applications/Remote Orbit Test.app`.
    /// 3. `SecStaticCodeCheckValidity` must validate the bundle's designated identifier.
    public static let production = RemoteOrbitHIDPeerAuthPolicy { clientFD in
        let solLocal: Int32 = 0
        let localPeerCred: Int32 = 0x001
        let localPeerPID: Int32 = 0x002

        var cred = xucred()
        var credLen = socklen_t(MemoryLayout<xucred>.size)
        guard getsockopt(clientFD, solLocal, localPeerCred, &cred, &credLen) == 0,
              credLen == socklen_t(MemoryLayout<xucred>.size),
              cred.cr_version == XUCRED_VERSION,
              cred.cr_uid != 0 else {
            return false
        }

        var consoleStat = stat()
        guard stat("/dev/console", &consoleStat) == 0,
              consoleStat.st_uid != 0,
              cred.cr_uid == consoleStat.st_uid else {
            return false
        }

        var peerPID: pid_t = 0
        var pidLen = socklen_t(MemoryLayout<pid_t>.size)
        guard getsockopt(clientFD, solLocal, localPeerPID, &peerPID, &pidLen) == 0,
              pidLen == socklen_t(MemoryLayout<pid_t>.size),
              peerPID > 0 else {
            return false
        }

        var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let pathLen = rohid_proc_pidpath(peerPID, &pathBuffer, UInt32(pathBuffer.count))
        guard pathLen > 0 else { return false }
        let rawPath = String(cString: pathBuffer)
        let resolvedExecURL = URL(fileURLWithPath: rawPath).resolvingSymlinksInPath()
        let allowedExecPaths: Set<String> = [
            URL(fileURLWithPath: "/Applications/RemoteOrbit.app/Contents/MacOS/RemoteOrbit")
                .resolvingSymlinksInPath().path,
            URL(fileURLWithPath: "/Applications/Remote Orbit Test.app/Contents/MacOS/RemoteOrbit")
                .resolvingSymlinksInPath().path,
        ]
        guard allowedExecPaths.contains(resolvedExecURL.path) else {
            return false
        }

        let appBundleURL = resolvedExecURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(appBundleURL as CFURL, SecCSFlags(), &staticCode) == errSecSuccess,
              let staticCode else {
            return false
        }
        var requirement: SecRequirement?
        let requirementText = "identifier \"com.lost0rz.RemoteOrbit\" or identifier \"com.lost0rz.RemoteOrbit.test\"" as CFString
        guard SecRequirementCreateWithString(requirementText, SecCSFlags(), &requirement) == errSecSuccess,
              let requirement else {
            return false
        }
        return SecStaticCodeCheckValidity(staticCode, SecCSFlags(), requirement) == errSecSuccess
    }

    public static func sameProcessForTesting() -> RemoteOrbitHIDPeerAuthPolicy {
        RemoteOrbitHIDPeerAuthPolicy { clientFD in
            let solLocal: Int32 = 0
            let localPeerCred: Int32 = 0x001
            let localPeerPID: Int32 = 0x002

            var cred = xucred()
            var credLen = socklen_t(MemoryLayout<xucred>.size)
            guard getsockopt(clientFD, solLocal, localPeerCred, &cred, &credLen) == 0,
                  cred.cr_uid == getuid() else {
                return false
            }
            var peerPID: pid_t = 0
            var pidLen = socklen_t(MemoryLayout<pid_t>.size)
            guard getsockopt(clientFD, solLocal, localPeerPID, &peerPID, &pidLen) == 0,
                  peerPID == getpid() else {
                return false
            }
            return true
        }
    }
}

public final class RemoteOrbitHIDUnixSocketServer {
    private final class ClientContext {
        let id: UUID
        let fd: Int32
        let decoder = RemoteOrbitHIDFrameStreamDecoder()
        let writeLock = NSLock()
        var readSource: DispatchSourceRead?
        var closed = false

        init(id: UUID, fd: Int32) {
            self.id = id
            self.fd = fd
        }

        func send(_ message: RemoteOrbitHIDWireServerMessage) -> Bool {
            guard let frame = RemoteOrbitHIDWireFraming.encode(message) else { return false }
            writeLock.lock()
            defer { writeLock.unlock() }
            guard !closed else { return false }
            return RemoteOrbitHIDWireFraming.writeAll(fd: fd, data: frame)
        }

        func markClosed() -> Bool {
            writeLock.lock()
            defer { writeLock.unlock() }
            guard !closed else { return false }
            closed = true
            return true
        }
    }

    private let socketPath: String
    private let socketMode: mode_t
    private let manager: RemoteOrbitHIDHelperSessionManager
    private let peerAuthPolicy: RemoteOrbitHIDPeerAuthPolicy
    private let queue = DispatchQueue(label: "com.lost0rz.RemoteOrbitHIDHelper.socket-server")
    private var listenFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var clients: [UUID: ClientContext] = [:]

    public init(
        socketPath: String = RemoteOrbitHIDIPCContract.defaultSocketPath,
        socketMode: mode_t = 0o666,
        manager: RemoteOrbitHIDHelperSessionManager,
        peerAuthPolicy: RemoteOrbitHIDPeerAuthPolicy = .production
    ) {
        self.socketPath = socketPath
        self.socketMode = socketMode
        self.manager = manager
        self.peerAuthPolicy = peerAuthPolicy
    }

    deinit {
        stop()
    }

    @discardableResult
    public func start() -> Bool {
        queue.sync {
            guard listenFD < 0 else { return true }
            let directory = URL(fileURLWithPath: socketPath).deletingLastPathComponent().path
            do {
                try FileManager.default.createDirectory(
                    atPath: directory,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o755]
                )
            } catch {
                return false
            }

            unlink(socketPath)
            let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
            guard fd >= 0 else { return false }
            RemoteOrbitHIDWireFraming.configureNoSigPipe(fd: fd)
            let flags = fcntl(fd, F_GETFL, 0)
            _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)

            var addr = sockaddr_un()
            addr.sun_family = sa_family_t(AF_UNIX)
            let pathBytes = socketPath.utf8CString
            let maxSunPath = MemoryLayout.size(ofValue: addr.sun_path)
            guard pathBytes.count <= maxSunPath else {
                Darwin.close(fd)
                return false
            }
            withUnsafeMutablePointer(to: &addr.sun_path) { sunPathPtr in
                let rawPtr = UnsafeMutableRawPointer(sunPathPtr).assumingMemoryBound(to: CChar.self)
                for index in 0..<pathBytes.count {
                    rawPtr[index] = pathBytes[index]
                }
            }
            addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)

            let bindOK = withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    Darwin.bind(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size)) == 0
                }
            }
            guard bindOK, Darwin.listen(fd, 8) == 0 else {
                Darwin.close(fd)
                unlink(socketPath)
                return false
            }
            _ = chmod(socketPath, socketMode)
            listenFD = fd

            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
            source.setEventHandler { [weak self] in
                self?.acceptPendingClients()
            }
            source.setCancelHandler {
                Darwin.close(fd)
            }
            acceptSource = source
            source.resume()
            return true
        }
    }

    public func stop() {
        queue.sync {
            let activeClients = Array(clients.values)
            clients.removeAll()
            for client in activeClients {
                closeClientLocked(client)
            }
            if let source = acceptSource {
                acceptSource = nil
                listenFD = -1
                source.cancel()
            } else if listenFD >= 0 {
                Darwin.close(listenFD)
                listenFD = -1
            }
            unlink(socketPath)
        }
    }

    public func broadcastStatus(_ state: RemoteOrbitHIDHelperTransportState) {
        queue.async { [weak self] in
            guard let self else { return }
            let message = RemoteOrbitHIDWireServerMessage.status(state)
            for client in Array(self.clients.values) {
                if !client.send(message) {
                    self.closeClientLocked(client)
                }
            }
        }
    }

    private func acceptPendingClients() {
        guard listenFD >= 0 else { return }
        while true {
            var addr = sockaddr_un()
            var len = socklen_t(MemoryLayout<sockaddr_un>.size)
            let clientFD = withUnsafeMutablePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    Darwin.accept(listenFD, sockPtr, &len)
                }
            }
            if clientFD < 0 {
                if errno == EINTR { continue }
                break
            }
            RemoteOrbitHIDWireFraming.configureNoSigPipe(fd: clientFD)
            guard peerAuthPolicy.isAuthorized(clientFD: clientFD) else {
                Darwin.close(clientFD)
                continue
            }
            let flags = fcntl(clientFD, F_GETFL, 0)
            _ = fcntl(clientFD, F_SETFL, flags | O_NONBLOCK)

            let id = UUID()
            let context = ClientContext(id: id, fd: clientFD)
            clients[id] = context

            let readSource = DispatchSource.makeReadSource(fileDescriptor: clientFD, queue: queue)
            readSource.setEventHandler { [weak self, weak context] in
                guard let self, let context else { return }
                self.readFromClientLocked(context)
            }
            readSource.setCancelHandler {
                Darwin.close(clientFD)
            }
            context.readSource = readSource
            readSource.resume()

            manager.reportedStatus { [weak self, weak context] status in
                guard let self, let context else { return }
                self.queue.async {
                    guard self.clients[context.id] != nil else { return }
                    if !context.send(.status(status)) {
                        self.closeClientLocked(context)
                    }
                }
            }
        }
    }

    private func readFromClientLocked(_ client: ClientContext) {
        var temp = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = Darwin.read(client.fd, &temp, temp.count)
            if count > 0 {
                client.decoder.append(Data(temp[0..<count]))
                frameLoop: while true {
                    switch client.decoder.nextFrame() {
                    case let .frame(payload):
                        handlePayloadLocked(payload, from: client)
                        if clients[client.id] == nil { return }
                    case .needMoreData:
                        break frameLoop
                    case .invalidFrame:
                        closeClientLocked(client)
                        return
                    }
                }
            } else if count == 0 {
                closeClientLocked(client)
                return
            } else {
                if errno == EINTR { continue }
                if errno == EAGAIN || errno == EWOULDBLOCK { break }
                closeClientLocked(client)
                return
            }
        }
    }

    private func handlePayloadLocked(_ payload: Data, from client: ClientContext) {
        guard let wire = try? JSONDecoder().decode(RemoteOrbitHIDWireRequest.self, from: payload) else {
            closeClientLocked(client)
            return
        }
        switch wire.kind {
        case .status:
            manager.reportedStatus { [weak self, weak client] state in
                guard let self, let client else { return }
                self.queue.async {
                    guard self.clients[client.id] != nil else { return }
                    if !client.send(.status(state, requestID: wire.requestID)) {
                        self.closeClientLocked(client)
                    }
                }
            }
        case .begin, .release, .recover:
            guard let sessionID = wire.sessionID,
                  let protocolVersion = wire.protocolVersion,
                  let generation = wire.connectionGeneration,
                  let sequence = wire.requestSequence else {
                _ = client.send(.reply(
                    requestID: wire.requestID,
                    connectionGeneration: wire.connectionGeneration ?? 0,
                    requestSequence: wire.requestSequence ?? 0,
                    outcome: .rejected
                ))
                return
            }
            let operation: RemoteOrbitHIDHelperRequest.Operation
            switch wire.kind {
            case .begin:
                let modifiers = wire.modifierKeyCodes ?? []
                guard modifiers.count <= 8 else {
                    _ = client.send(.reply(
                        requestID: wire.requestID,
                        connectionGeneration: generation,
                        requestSequence: sequence,
                        outcome: .rejected
                    ))
                    return
                }
                operation = .beginCombo(
                    modifierKeyCodes: modifiers,
                    primaryKeyUsage: wire.primaryKeyUsage
                )
            case .release:
                operation = .release
            case .recover:
                operation = .recover
            case .status:
                return
            }

            let request = RemoteOrbitHIDHelperRequest(
                connectionID: client.id,
                sessionID: sessionID,
                protocolVersion: protocolVersion,
                connectionGeneration: generation,
                requestSequence: sequence,
                operation: operation
            )
            manager.submit(request) { [weak self, weak client] result in
                guard let self, let client else { return }
                self.queue.async {
                    guard self.clients[client.id] != nil else { return }
                    if !client.send(.reply(
                        requestID: wire.requestID,
                        connectionGeneration: result.connectionGeneration,
                        requestSequence: result.requestSequence,
                        outcome: result.outcome
                    )) {
                        self.closeClientLocked(client)
                    }
                }
            }
        }
    }

    private func closeClientLocked(_ client: ClientContext) {
        clients.removeValue(forKey: client.id)
        guard client.markClosed() else { return }
        manager.disconnect(connectionID: client.id)
        if let source = client.readSource {
            client.readSource = nil
            source.cancel()
        } else {
            Darwin.close(client.fd)
        }
    }
}
