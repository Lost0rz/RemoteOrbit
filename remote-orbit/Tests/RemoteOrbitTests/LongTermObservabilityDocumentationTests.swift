import Foundation
import XCTest

final class LongTermObservabilityDocumentationTests: XCTestCase {
    func testOperationalDocumentationContainsLongTermObservabilityContract() throws {
        let packageRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let repositoryRoot = packageRoot.deletingLastPathComponent()
        let readme = try String(contentsOf: repositoryRoot.appendingPathComponent("README.md"), encoding: .utf8)
        let setup = try String(contentsOf: repositoryRoot.appendingPathComponent("SETUP_NOTES.md"), encoding: .utf8)
        let adrURL = repositoryRoot.appendingPathComponent("docs/diagnostics/ADR-0003-long-term-observability.md")
        let adr = try String(contentsOf: adrURL, encoding: .utf8)
        let contract = [readme, setup, adr].joined(separator: "\n")

        XCTAssertTrue(contract.contains("RemoteOrbit diagnostics export --output"))
        XCTAssertTrue(contract.contains("2 MiB"))
        XCTAssertTrue(contract.contains("5 segments"))
        XCTAssertTrue(contract.contains("L1"))
        XCTAssertTrue(contract.contains("L2"))
        XCTAssertTrue(contract.contains("evidence-unavailable.json"))
        XCTAssertTrue(contract.contains("session_id"))
        XCTAssertTrue(contract.contains("capture_id"))
        XCTAssertTrue(contract.contains("does not establish root cause"))
    }
}
