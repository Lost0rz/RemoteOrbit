// InstallationSupport.swift — first-install checks and repair actions

import AppKit
import CoreAudio
import Foundation

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
}

enum InstallationRepair {
    enum RepairError: LocalizedError {
        case bundledDriverMissing
        case failedToLaunch(String)
        case failed(Int32, String)

        var errorDescription: String? {
            switch self {
            case .bundledDriverMissing:
                return "当前应用没有附带 RemoteOrbitAudio 驱动，无法执行补装。"
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
}
