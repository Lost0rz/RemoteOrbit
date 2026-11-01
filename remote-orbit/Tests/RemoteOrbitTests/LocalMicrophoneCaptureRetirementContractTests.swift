import XCTest
@testable import RemoteOrbit

/// Domain 6 retirement contract: production no longer owns an AVCapture
/// physical/external microphone path or microphone-TCC requirement, while
/// the menu-bar system input selector, persisted preferred input, and the
/// temporary RemoteOrbit input lease remain supported surfaces.
final class LocalMicrophoneCaptureRetirementContractTests: XCTestCase {
    func testProductionSourcesRetireAVCaptureMicrophoneOwnership() throws {
        let sourcesRoot = packageRoot()
            .appendingPathComponent("Sources/RemoteOrbit")
        let sourceFiles = try FileManager.default
            .enumerator(at: sourcesRoot, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
        XCTAssertNotNil(sourceFiles)
        try sourceFiles?.forEach { file in
            let contents = try String(contentsOf: file, encoding: .utf8)
            for retiredSymbol in [
                "AVCaptureSession",
                "AVCaptureDevice",
                "AVCaptureAudioDataOutput",
                "AVCaptureAudioDataOutputSampleBufferDelegate",
                "setLocalMicrophoneCaptureEnabled",
                "requestAccess(for: .audio)",
                "import AVFoundation",
                "import CoreMedia",
            ] {
                XCTAssertFalse(
                    contents.contains(retiredSymbol),
                    "\(file.lastPathComponent) still owns retired local-capture surface: \(retiredSymbol)"
                )
            }
        }
    }

    func testPackagedInfoPlistDeclaresNoMicrophonePermission() throws {
        let plist = try String(
            contentsOf: packageRoot()
                .appendingPathComponent("Packaging/Info.plist"),
            encoding: .utf8
        )
        XCTAssertFalse(
            plist.contains("NSMicrophoneUsageDescription"),
            "packaged Info.plist must not declare the obsolete microphone TCC permission"
        )
    }

    func testSystemInputSelectorAndLeaseAuthorityRemain() throws {
        let deviceManager = try source("Sources/RemoteOrbit/AudioDeviceManager.swift")
        for retainedSurface in [
            "static func selectInput(identifier: String)",
            "static func applyPreferredInputSelection()",
            "static func selectRemoteOrbitInputForVoice()",
            "preferredInputKey",
        ] {
            XCTAssertTrue(
                deviceManager.contains(retainedSurface),
                "AudioDeviceManager lost retained input-selector surface: \(retainedSurface)"
            )
        }

        let audioPipe = try source("Sources/RemoteOrbit/AudioPipe.swift")
        XCTAssertTrue(
            audioPipe.contains("selectRemoteOrbitInputForVoice()"),
            "remote route activation must keep temporarily selecting RemoteOrbit Mic 2ch"
        )
        XCTAssertTrue(
            audioPipe.contains("applyPreferredInputSelection()"),
            "startup/driver-reload preferred-input restore must remain in AudioPipe"
        )
        XCTAssertFalse(
            audioPipe.contains("isLocalMicrophoneCaptureRequested"),
            "preferred-input restoration must not be gated on the retired local-capture flag"
        )

        let main = try source("Sources/RemoteOrbit/main.swift")
        XCTAssertTrue(
            main.contains("onRemoteInputLeaseRelease"),
            "the direct voice lifecycle must own the temporary input lease release"
        )
        XCTAssertTrue(
            main.contains("settleRemoteInputLeaseAtDirectCompletion"),
            "lease release must be bound to post-drain session completion"
        )
    }

    private func source(_ relativePath: String) throws -> String {
        try String(
            contentsOf: packageRoot().appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private func packageRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
