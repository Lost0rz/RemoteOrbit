// InstallationSupport.swift — first-install checks and repair actions

import AppKit
import Carbon.HIToolbox
import CoreAudio
import CryptoKit
import Foundation
import IOKit

enum SecureEventInputDiagnostics {
    static var isSecureEventInputEnabled: Bool {
        IsSecureEventInputEnabled()
    }

    static var secureInputOwnerPID: pid_t? {
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        guard root != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(root) }
        guard let rawUsers = IORegistryEntryCreateCFProperty(
            root,
            "IOConsoleUsers" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? [[String: Any]] else {
            return nil
        }
        for entry in rawUsers {
            if let number = entry["kCGSSessionSecureInputPID"] as? NSNumber {
                let pid = pid_t(number.int32Value)
                if pid > 0 {
                    return pid
                }
            }
        }
        return nil
    }

    static var secureInputOwnerSummary: String? {
        guard isSecureEventInputEnabled else { return nil }
        guard let pid = secureInputOwnerPID else {
            return "已开启（未知进程）"
        }
        let appName: String? = {
            guard let app = NSRunningApplication(processIdentifier: pid) else { return nil }
            if let localized = app.localizedName?.trimmingCharacters(in: .whitespacesAndNewlines),
               !localized.isEmpty {
                return localized
            }
            return app.bundleIdentifier
        }()
        if let appName {
            return "\(appName) (PID \(pid))"
        }
        return "PID \(pid)"
    }
}

enum InstallationDiagnostics {
    static let audioDriverURL = URL(
        fileURLWithPath: "/Library/Audio/Plug-Ins/HAL/RemoteOrbitAudio.driver",
        isDirectory: true
    )

    static var appInstalled: Bool {
        Bundle.main.bundlePath.hasSuffix(".app") &&
            Bundle.main.bundleIdentifier == ProductIdentity.bundleIdentifier
    }

    static var audioDriverInstalled: Bool {
        FileManager.default.fileExists(atPath: audioDriverURL.path)
    }

    static var audioDeviceName: String? {
        AudioPipe.installedOutputDeviceName
    }

    static var bundledAudioDriverAvailable: Bool {
        Bundle.main.url(
            forResource: "RemoteOrbitAudio",
            withExtension: "driver"
        ) != nil
    }

    static let karabinerManagerURL = URL(
        fileURLWithPath: "/Applications/.Karabiner-VirtualHIDDevice-Manager.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Manager"
    )

    static let hidHelperDaemonURL = URL(
        fileURLWithPath: "/Library/Application Support/RemoteOrbit/RemoteOrbitHIDHelperDaemon"
    )

    enum VirtualHIDStatus: Equatable {
        case ready
        case helperUpdateRequired
        case awaitingDriverApproval
        case daemonDisconnected
        case notInstalled
    }

    private struct CachedFileDigest {
        let fileSize: UInt64
        let modificationDate: Date?
        let hexDigest: String
    }

    private static let digestCacheLock = NSLock()
    private static var digestCache: [String: CachedFileDigest] = [:]

    static var isInstalledHIDHelperUpToDate: Bool {
        guard let bundledURL = bundledHIDHelperDaemonURL else {
            return true
        }
        guard FileManager.default.isExecutableFile(atPath: hidHelperDaemonURL.path),
              let bundledDigest = cachedSHA256Hex(at: bundledURL),
              let installedDigest = cachedSHA256Hex(at: hidHelperDaemonURL) else {
            return false
        }
        return bundledDigest == installedDigest
    }

    private static func cachedSHA256Hex(at url: URL) -> String? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
              let size = values.fileSize.map(UInt64.init) else {
            return nil
        }
        let modDate = values.contentModificationDate
        let key = url.path
        digestCacheLock.lock()
        if let cached = digestCache[key],
           cached.fileSize == size,
           cached.modificationDate == modDate {
            digestCacheLock.unlock()
            return cached.hexDigest
        }
        digestCacheLock.unlock()

        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            return nil
        }
        let hex = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        digestCacheLock.lock()
        digestCache[key] = CachedFileDigest(
            fileSize: size,
            modificationDate: modDate,
            hexDigest: hex
        )
        digestCacheLock.unlock()
        return hex
    }

    static var karabinerManagerInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: karabinerManagerURL.path)
    }

    static var bundledVirtualHIDPackageURL: URL? {
        Bundle.main.url(
            forResource: "Karabiner-DriverKit-VirtualHIDDevice-8.6.0",
            withExtension: "pkg"
        )
    }

    static var bundledHIDHelperDaemonURL: URL? {
        guard let execURL = Bundle.main.executableURL else { return nil }
        let helperURL = execURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Helpers/RemoteOrbitHIDHelperDaemon")
        return FileManager.default.isExecutableFile(atPath: helperURL.path) ? helperURL : nil
    }

    static var bundledVirtualHIDAvailable: Bool {
        bundledVirtualHIDPackageURL != nil && bundledHIDHelperDaemonURL != nil
    }

    static var virtualHIDStatus: VirtualHIDStatus {
        let provider = VoiceShortcutHIDUnixSocketProvider.shared
        if case let .ready(_, _, _, keyboardReady) = provider.state, keyboardReady {
            return isInstalledHIDHelperUpToDate ? .ready : .helperUpdateRequired
        }
        if provider.isDaemonConnected {
            return .awaitingDriverApproval
        }
        if karabinerManagerInstalled || FileManager.default.fileExists(atPath: hidHelperDaemonURL.path) {
            return .daemonDisconnected
        }
        return .notInstalled
    }
}

enum InstallationRepair {
    enum RepairError: LocalizedError {
        case bundledDriverMissing
        case bundledVirtualHIDMissing
        case failedToLaunch(String)
        case failed(Int32, String)

        var errorDescription: String? {
            switch self {
            case .bundledDriverMissing:
                return "当前应用没有附带 RemoteOrbitAudio 驱动，无法执行补装。"
            case .bundledVirtualHIDMissing:
                return "当前应用没有附带完整的虚拟键盘驱动组件（Karabiner VirtualHID v8.6.0 与守护服务）。"
            case let .failedToLaunch(message):
                return "无法启动安装授权：\(message)"
            case let .failed(code, output):
                let detail = output.isEmpty ? "无额外信息" : output
                return "补装失败（错误 \(code)）：\(detail)"
            }
        }
    }

    /// Reinstall the bundled HAL driver through macOS's administrator dialog.
    /// The existing driver is moved to a timestamped backup before replacement.
    static func reinstallBundledAudioDriver(completion: @escaping (Result<Void, Error>) -> Void) {
        guard let sourceURL = Bundle.main.url(
            forResource: "RemoteOrbitAudio",
            withExtension: "driver"
        ) else {
            completion(.failure(RepairError.bundledDriverMissing))
            return
        }

        let destination = "/Library/Audio/Plug-Ins/HAL/RemoteOrbitAudio.driver"
        let command = """
        set -e
        source=\(shellQuote(sourceURL.path))
        destination=\(shellQuote(destination))
        timestamp=$(date +%Y%m%d%H%M%S)
        legacy='/Library/Audio/Plug-Ins/HAL/VoiceRemoteAudio.driver'
        if [ -e "$legacy" ]; then
          mv "$legacy" "${legacy}.previous.$timestamp"
        fi
        legacy='/Library/Audio/Plug-Ins/HAL/MiRemoteVoice.driver'
        if [ -e "$legacy" ]; then
          mv "$legacy" "${legacy}.previous.$timestamp"
        fi
        legacy='/Library/Audio/Plug-Ins/HAL/BlackHole2ch.driver'
        if [ -e "$legacy" ]; then
          mv "$legacy" "${legacy}.previous.$timestamp"
        fi
        if [ -e \"$destination\" ]; then
          backup=\"${destination}.previous.$timestamp\"
          mv \"$destination\" \"$backup\"
        fi
        ditto \"$source\" \"$destination\"
        chown -R root:wheel \"$destination\"
        chmod -R u+rwX,go+rX \"$destination\"
        chmod 755 \"$destination/Contents/MacOS/BlackHole\"
        killall -9 coreaudiod 2>/dev/null || true
        """
        // Keep the command in an AppleScript string so the password dialog is
        // owned by macOS rather than asking the app to handle credentials.
        let authorizedScript = "do shell script \(appleScriptQuote(command)) with administrator privileges"

        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", authorizedScript]
            process.standardOutput = output
            process.standardError = output

            do {
                try process.run()
                process.waitUntilExit()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                let message = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                DispatchQueue.main.async {
                    if process.terminationStatus == 0 {
                        completion(.success(()))
                    } else {
                        completion(.failure(RepairError.failed(process.terminationStatus, message)))
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(RepairError.failedToLaunch(error.localizedDescription)))
                }
            }
        }
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\\"'\\\"'") + "'"
    }

    private static func appleScriptQuote(_ value: String) -> String {
        "\"" + value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private static func hidHelperDaemonInstallScript(helperURL: URL) -> String {
        """
        helper_src=\(shellQuote(helperURL.path))
        /usr/bin/install -d -o root -g wheel -m 0755 '/Library/Application Support/RemoteOrbit' '/Library/Application Support/RemoteOrbit/run' '/Library/Logs/RemoteOrbit'
        /usr/bin/install -o root -g wheel -m 0755 "$helper_src" '/Library/Application Support/RemoteOrbit/RemoteOrbitHIDHelperDaemon'
        cat > '/Library/LaunchDaemons/com.lost0rz.RemoteOrbitHIDHelper.plist' <<'PLIST'
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>com.lost0rz.RemoteOrbitHIDHelper</string>
            <key>ProgramArguments</key>
            <array>
                <string>/Library/Application Support/RemoteOrbit/RemoteOrbitHIDHelperDaemon</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <true/>
            <key>StandardOutPath</key>
            <string>/Library/Logs/RemoteOrbit/hid-helper.log</string>
            <key>StandardErrorPath</key>
            <string>/Library/Logs/RemoteOrbit/hid-helper.log</string>
        </dict>
        </plist>
        PLIST
        /usr/sbin/chown root:wheel '/Library/LaunchDaemons/com.lost0rz.RemoteOrbitHIDHelper.plist'
        /bin/chmod 0644 '/Library/LaunchDaemons/com.lost0rz.RemoteOrbitHIDHelper.plist'
        /usr/bin/plutil -lint '/Library/LaunchDaemons/com.lost0rz.RemoteOrbitHIDHelper.plist' >/dev/null
        /bin/launchctl bootout system/com.lost0rz.RemoteOrbitHIDHelper 2>/dev/null || true
        : > '/Library/Logs/RemoteOrbit/hid-helper.log'
        /bin/launchctl bootstrap system '/Library/LaunchDaemons/com.lost0rz.RemoteOrbitHIDHelper.plist'
        /bin/launchctl kickstart -k system/com.lost0rz.RemoteOrbitHIDHelper
        """
    }

    static func updateBundledHIDHelperDaemon(completion: @escaping (Result<String, Error>) -> Void) {
        guard let helperURL = InstallationDiagnostics.bundledHIDHelperDaemonURL else {
            completion(.failure(RepairError.bundledVirtualHIDMissing))
            return
        }

        let command = """
        set -e
        \(hidHelperDaemonInstallScript(helperURL: helperURL))
        """
        let authorizedScript = "do shell script \(appleScriptQuote(command)) with administrator privileges"

        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", authorizedScript]
            process.standardOutput = output
            process.standardError = output

            do {
                try process.run()
                process.waitUntilExit()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                let message = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard process.terminationStatus == 0 else {
                    DispatchQueue.main.async {
                        completion(.failure(RepairError.failed(process.terminationStatus, message)))
                    }
                    return
                }

                VoiceShortcutHIDUnixSocketProvider.shared.refreshStatusNow()
                DispatchQueue.main.async {
                    completion(.success("虚拟键盘守护服务已更新并重新启动。"))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(RepairError.failedToLaunch(error.localizedDescription)))
                }
            }
        }
    }

    static func reinstallBundledVirtualHIDStack(completion: @escaping (Result<String, Error>) -> Void) {
        guard let pkgURL = InstallationDiagnostics.bundledVirtualHIDPackageURL,
              let helperURL = InstallationDiagnostics.bundledHIDHelperDaemonURL else {
            completion(.failure(RepairError.bundledVirtualHIDMissing))
            return
        }

        let command = """
        set -e
        pkg=\(shellQuote(pkgURL.path))
        /usr/sbin/pkgutil --check-signature "$pkg" >/dev/null
        tmp_expand="$(mktemp -d /private/tmp/rohid-expand.XXXXXX)"
        trap 'rm -rf "$tmp_expand"' EXIT
        rm -rf "$tmp_expand/pkg"
        /usr/sbin/pkgutil --expand-full "$pkg" "$tmp_expand/pkg"
        manager_src="$tmp_expand/pkg/Payload/Applications/.Karabiner-VirtualHIDDevice-Manager.app"
        pqrs_src="$tmp_expand/pkg/Payload/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice"
        /usr/bin/codesign --verify --deep --strict "$manager_src"
        /usr/bin/codesign --verify --deep --strict "$pqrs_src/Applications/Karabiner-VirtualHIDDevice-Daemon.app"
        rm -rf '/Applications/.Karabiner-VirtualHIDDevice-Manager.app'
        /usr/bin/ditto "$manager_src" '/Applications/.Karabiner-VirtualHIDDevice-Manager.app'
        /usr/sbin/chown -R root:wheel '/Applications/.Karabiner-VirtualHIDDevice-Manager.app'
        /usr/bin/install -d -o root -g wheel -m 0755 '/Library/Application Support/org.pqrs'
        rm -rf '/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice'
        /usr/bin/ditto "$pqrs_src" '/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice'
        /usr/sbin/chown -R root:wheel '/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice'
        upstream_plist='/Library/LaunchDaemons/org.pqrs.service.daemon.Karabiner-VirtualHIDDevice-Daemon.plist'
        karabiner_plist='/Library/LaunchDaemons/com.lost0rz.RemoteOrbitKarabinerVHDDaemon.plist'
        if [ -f "$upstream_plist" ]; then
          /usr/bin/killall Karabiner-VirtualHIDDevice-Daemon 2>/dev/null || true
        else
          cat > "$karabiner_plist" <<'PLIST'
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>com.lost0rz.RemoteOrbitKarabinerVHDDaemon</string>
            <key>ProgramArguments</key>
            <array>
                <string>/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/Applications/Karabiner-VirtualHIDDevice-Daemon.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Daemon</string>
            </array>
            <key>ProcessType</key>
            <string>Interactive</string>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <true/>
        </dict>
        </plist>
        PLIST
          /usr/sbin/chown root:wheel "$karabiner_plist"
          /bin/chmod 0644 "$karabiner_plist"
          /usr/bin/plutil -lint "$karabiner_plist" >/dev/null
          /bin/launchctl bootout system/com.lost0rz.RemoteOrbitKarabinerVHDDaemon 2>/dev/null || true
          /bin/launchctl bootstrap system "$karabiner_plist"
          /bin/launchctl kickstart -k system/com.lost0rz.RemoteOrbitKarabinerVHDDaemon
        fi
        \(hidHelperDaemonInstallScript(helperURL: helperURL))
        """
        let authorizedScript = "do shell script \(appleScriptQuote(command)) with administrator privileges"

        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", authorizedScript]
            process.standardOutput = output
            process.standardError = output

            do {
                try process.run()
                process.waitUntilExit()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                let message = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard process.terminationStatus == 0 else {
                    DispatchQueue.main.async {
                        completion(.failure(RepairError.failed(process.terminationStatus, message)))
                    }
                    return
                }

                // Activate the DriverKit system extension from the console user session
                // without blocking on user approval in System Settings.
                try? launchVirtualHIDActivationRequest()
                VoiceShortcutHIDUnixSocketProvider.shared.refreshStatusNow()

                DispatchQueue.main.async {
                    if let loginItemsURL = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
                        NSWorkspace.shared.open(loginItemsURL)
                    }
                    completion(.success(
                        "虚拟键盘驱动与守护服务已安装完成！若首次安装系统提示拦截系统扩展，请在刚打开的「系统设置 -> 通用 -> 登录项与扩展 -> 驱动程序扩展」中开启 Karabiner-DriverKit-VirtualHIDDevice，随后点「重新检测」即可变为已就绪。"
                    ))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(RepairError.failedToLaunch(error.localizedDescription)))
                }
            }
        }
    }

    static func activateVirtualHIDDriverExtension(completion: @escaping (Result<String, Error>) -> Void) {
        let managerURL = InstallationDiagnostics.karabinerManagerURL
        guard FileManager.default.isExecutableFile(atPath: managerURL.path) else {
            completion(.failure(RepairError.failedToLaunch("未找到 Karabiner-VirtualHIDDevice-Manager，请先完成驱动包安装。")))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try launchVirtualHIDActivationRequest()
                VoiceShortcutHIDUnixSocketProvider.shared.refreshStatusNow()
                DispatchQueue.main.async {
                    if let loginItemsURL = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
                        NSWorkspace.shared.open(loginItemsURL)
                    }
                    completion(.success(
                        "已请求激活虚拟键盘扩展；请在刚打开的「系统设置 -> 通用 -> 登录项与扩展 -> 驱动程序扩展」中允许 Karabiner-DriverKit-VirtualHIDDevice，开启后状态会自动变为已就绪。"
                    ))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(RepairError.failedToLaunch(error.localizedDescription)))
                }
            }
        }
    }

    /// Launches `Karabiner-VirtualHIDDevice-Manager activate`, which keeps its
    /// `OSSystemExtensionRequest` process alive until the user approves the
    /// DriverKit extension in System Settings, so it must not block the caller.
    private static func launchVirtualHIDActivationRequest() throws {
        let managerURL = InstallationDiagnostics.karabinerManagerURL
        guard FileManager.default.isExecutableFile(atPath: managerURL.path) else { return }

        let process = Process()
        process.executableURL = managerURL
        process.arguments = ["activate"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()

        DispatchQueue.global(qos: .utility).async {
            process.waitUntilExit()
            VoiceShortcutHIDUnixSocketProvider.shared.refreshStatusNow()
        }
        Thread.sleep(forTimeInterval: 0.8)
    }
}
