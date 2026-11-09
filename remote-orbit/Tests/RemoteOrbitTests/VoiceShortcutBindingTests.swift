import Foundation
import XCTest
@testable import RemoteOrbit

final class VoiceShortcutBindingTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "RemoteOrbitTests.VoiceShortcutBinding.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testFirstRunSeedsSixStableEntriesUsingSelectedProfileBeforeMomentaryKey() throws {
        defaults.set("system-right-command", forKey: VoiceInputProfileStore.selectedProfileIDKey)
        defaults.set(VoiceTriggerKey.leftOption.rawValue, forKey: AppStorage.momentaryVoiceTriggerKeyKey)

        let loaded = onMain { VoiceShortcutStore.load(from: defaults) }

        XCTAssertTrue(loaded.isWritable)
        XCTAssertEqual(loaded.snapshot.entries.count, 6)
        XCTAssertEqual(loaded.snapshot.activeEntryID, "system-right-command")
        XCTAssertEqual(defaults.data(forKey: VoiceShortcutStore.snapshotKey), try encoded(loaded.snapshot))
    }

    func testFirstRunFallsBackFromSelectedProfileToLegacyMomentaryKey() throws {
        defaults.set("stale-profile-id", forKey: VoiceInputProfileStore.selectedProfileIDKey)
        defaults.set(VoiceTriggerKey.rightControl.rawValue, forKey: AppStorage.momentaryVoiceTriggerKeyKey)

        let loaded = onMain { VoiceShortcutStore.load(from: defaults) }

        XCTAssertEqual(loaded.snapshot.activeEntryID, "system-right-control")
    }

    func testCorruptAndUnsupportedSnapshotsRemainByteForByteAndReadOnly() throws {
        let corrupt = Data([0x00, 0x01, 0xFE, 0xFF])
        defaults.set(corrupt, forKey: VoiceShortcutStore.snapshotKey)
        let corruptResult = VoiceShortcutStore.load(from: defaults)
        XCTAssertFalse(corruptResult.isWritable)
        XCTAssertEqual(defaults.data(forKey: VoiceShortcutStore.snapshotKey), corrupt)

        var newer = VoiceShortcutSnapshot.seeded()
        newer = VoiceShortcutSnapshot(schemaVersion: 99, entries: newer.entries, activeEntryID: newer.activeEntryID)
        let newerBytes = try encoded(newer)
        defaults.set(newerBytes, forKey: VoiceShortcutStore.snapshotKey)
        let newerResult = VoiceShortcutStore.load(from: defaults)
        XCTAssertFalse(newerResult.isWritable)
        XCTAssertEqual(defaults.data(forKey: VoiceShortcutStore.snapshotKey), newerBytes)
    }

    func testOrphanActiveIDIsRepairedOnlyInMemoryUntilExplicitCommit() throws {
        var snapshot = VoiceShortcutSnapshot.seeded()
        snapshot.activeEntryID = "deleted-entry"
        let bytes = try encoded(snapshot)
        defaults.set(bytes, forKey: VoiceShortcutStore.snapshotKey)

        let loaded = VoiceShortcutStore.load(from: defaults)

        XCTAssertTrue(loaded.isWritable)
        XCTAssertEqual(loaded.snapshot.activeEntryID, snapshot.entries[0].id)
        XCTAssertEqual(defaults.data(forKey: VoiceShortcutStore.snapshotKey), bytes)
    }

    func testNameAndPhysicalDuplicateValidationPreservesModifierSide() throws {
        let left = VoiceShortcutEntry(
            id: "left-f",
            displayName: "F 快捷键",
            binding: .chord(primaryKeyCode: 3, preview: "⌘F", modifierKeyCodes: [55])
        )
        let right = VoiceShortcutEntry(
            id: "right-f",
            displayName: "右侧组合",
            binding: .chord(primaryKeyCode: 3, preview: "⌘F", modifierKeyCodes: [54])
        )
        var snapshot = VoiceShortcutSnapshot.seeded()
        snapshot.entries.append(contentsOf: [left, right])
        XCTAssertNoThrow(try VoiceShortcutStore.validate(snapshot))

        var duplicateSide = snapshot
        duplicateSide.entries[duplicateSide.entries.count - 1].binding =
            .chord(primaryKeyCode: 3, preview: "⌘F (different label)", modifierKeyCodes: [55])
        XCTAssertThrowsError(try VoiceShortcutStore.validate(duplicateSide)) {
            XCTAssertEqual($0 as? VoiceShortcutValidationError, .duplicateBinding)
        }

        var duplicateName = snapshot
        duplicateName.entries[duplicateName.entries.count - 1].displayName = "  f 快捷键  "
        XCTAssertThrowsError(try VoiceShortcutStore.validate(duplicateName)) {
            XCTAssertEqual($0 as? VoiceShortcutValidationError, .duplicateName)
        }

        var duplicateModifierFamily = VoiceShortcutSnapshot.seeded()
        duplicateModifierFamily.entries[0].binding = .chord(
            primaryKeyCode: 3,
            preview: "⌘F",
            modifierKeyCodes: [55, 54]
        )
        XCTAssertThrowsError(try VoiceShortcutStore.validate(duplicateModifierFamily)) {
            XCTAssertEqual($0 as? VoiceShortcutValidationError, .invalidBinding)
        }

        XCTAssertNoThrow(try VoiceShortcutStore.validate(binding: .chord(
            primaryKeyCode: 3,
            preview: "⇧F",
            modifierKeyCodes: [56]
        )))
        XCTAssertThrowsError(try VoiceShortcutStore.validate(binding: .chord(
            primaryKeyCode: 127,
            preview: "⌘Power",
            modifierKeyCodes: [55]
        )))
    }

    func testNamesAllow64UnicodeCharactersAndReject65() throws {
        var snapshot = VoiceShortcutSnapshot.seeded()
        snapshot.entries[0].displayName = String(repeating: "界", count: 64)
        XCTAssertNoThrow(try VoiceShortcutStore.validate(snapshot))

        snapshot.entries[0].displayName = String(repeating: "界", count: 65)
        XCTAssertThrowsError(try VoiceShortcutStore.validate(snapshot)) {
            XCTAssertEqual($0 as? VoiceShortcutValidationError, .invalidName)
        }
    }

    func testDeletionCannotRemoveLastEntry() throws {
        let only = VoiceShortcutSnapshot(
            schemaVersion: VoiceShortcutStore.schemaVersion,
            entries: [VoiceShortcutEntry(id: "only", displayName: "Only", binding: .pureModifier(.leftOption))],
            activeEntryID: "only"
        )
        XCTAssertThrowsError(try VoiceShortcutStore.deletingEntry(id: "only", from: only)) {
            XCTAssertEqual($0 as? VoiceShortcutValidationError, .cannotDeleteLast)
        }
    }

    private func encoded(_ snapshot: VoiceShortcutSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(snapshot)
    }

    private func onMain<T>(_ work: () throws -> T) rethrows -> T {
        if Thread.isMainThread { return try work() }
        return try DispatchQueue.main.sync(execute: work)
    }
}
