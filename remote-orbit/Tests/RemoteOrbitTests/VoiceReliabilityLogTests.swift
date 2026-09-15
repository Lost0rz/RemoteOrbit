import Foundation
import XCTest
@testable import RemoteOrbit

final class VoiceReliabilityLogTests: XCTestCase {
    func testRotationKeepsCurrentOneAndTwoWithinBoundedRetention() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let log = VoiceReliabilityLog(directory: directory, maximumBytes: 32)

        log.write(String(repeating: "a", count: 24))
        log.flushForTesting()
        log.write(String(repeating: "b", count: 24))
        log.flushForTesting()
        log.write(String(repeating: "c", count: 24))
        log.flushForTesting()

        XCTAssertEqual(try contents(of: directory, named: "VoiceReliability.log.2"), String(repeating: "a", count: 24) + "\n")
        XCTAssertEqual(try contents(of: directory, named: "VoiceReliability.log.1"), String(repeating: "b", count: 24) + "\n")
        XCTAssertEqual(try contents(of: directory, named: "VoiceReliability.log"), String(repeating: "c", count: 24) + "\n")

        let total = AppStorage.byteSize(of: directory)
        XCTAssertLessThanOrEqual(total, 96)
    }

    func testClearRemovesAllReliabilityLayers() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let log = VoiceReliabilityLog(directory: directory, maximumBytes: 32)
        for value in ["one", "two", "three"] {
            log.write(String(repeating: value, count: 12))
            log.flushForTesting()
        }

        log.clear()

        let names = try FileManager.default.contentsOfDirectory(
            atPath: directory.path
        )
        XCTAssertFalse(names.contains("VoiceReliability.log"))
        XCTAssertFalse(names.contains("VoiceReliability.log.1"))
        XCTAssertFalse(names.contains("VoiceReliability.log.2"))
    }

    func testWriteFailureIsContainedAndCounted() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let log = VoiceReliabilityLog(
            directory: directory,
            writer: { _, _ in throw TestError.writeFailed }
        )

        log.write("metadata-only")
        log.flushForTesting()

        XCTAssertEqual(log.failureCount, 1)
    }

    func testWriteIsQueuedUntilExplicitTestFlush() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let log = VoiceReliabilityLog(directory: directory)

        log.write("session=abc event=SESSION_BEGIN")
        log.flushForTesting()

        XCTAssertEqual(
            try contents(of: directory, named: "VoiceReliability.log"),
            "session=abc event=SESSION_BEGIN\n"
        )
    }

    private enum TestError: Error {
        case writeFailed
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RemoteOrbit-VoiceReliability-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    private func contents(of directory: URL, named name: String) throws -> String {
        let url = directory.appendingPathComponent(name)
        return try String(contentsOf: url, encoding: .utf8)
    }
}
