import Foundation
import Combine

/// A voice shortcut keeps the physical side of each modifier. Ordinary
/// KeyChord remains the separate, backwards-compatible mapping format.
enum VoiceShortcutBinding: Equatable, Hashable, Codable {
    case pureModifier(VoiceTriggerKey)
    case chord(primaryKeyCode: UInt16, preview: String, modifierKeyCodes: [UInt16])
    case modifierChord(modifierKeyCodes: [UInt16])

    private enum CodingKeys: String, CodingKey {
        case kind
        case triggerKey
        case primaryKeyCode
        case preview
        case modifierKeyCodes
    }

    private enum Kind: String, Codable {
        case pureModifier
        case chord
        case modifierChord
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .pureModifier:
            self = .pureModifier(try container.decode(VoiceTriggerKey.self, forKey: .triggerKey))
        case .chord:
            self = .chord(
                primaryKeyCode: try container.decode(UInt16.self, forKey: .primaryKeyCode),
                preview: try container.decode(String.self, forKey: .preview),
                modifierKeyCodes: try container.decode([UInt16].self, forKey: .modifierKeyCodes)
            )
        case .modifierChord:
            self = .modifierChord(
                modifierKeyCodes: try container.decode([UInt16].self, forKey: .modifierKeyCodes)
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .pureModifier(key):
            try container.encode(Kind.pureModifier, forKey: .kind)
            try container.encode(key, forKey: .triggerKey)
        case let .chord(primaryKeyCode, preview, modifierKeyCodes):
            try container.encode(Kind.chord, forKey: .kind)
            try container.encode(primaryKeyCode, forKey: .primaryKeyCode)
            try container.encode(preview, forKey: .preview)
            try container.encode(modifierKeyCodes, forKey: .modifierKeyCodes)
        case let .modifierChord(modifierKeyCodes):
            try container.encode(Kind.modifierChord, forKey: .kind)
            try container.encode(modifierKeyCodes.sorted(), forKey: .modifierKeyCodes)
        }
    }

    var pureModifierKey: VoiceTriggerKey? {
        guard case let .pureModifier(key) = self else { return nil }
        return key
    }

    var displayName: String {
        switch self {
        case let .pureModifier(key): return key.displayName
        case let .chord(_, preview, _): return preview
        case .modifierChord: return sideDescription
        }
    }

    var sideDescription: String {
        switch self {
        case let .pureModifier(key): return key.displayName
        case let .chord(primaryKeyCode, preview, modifierKeyCodes):
            let labels: [UInt16: String] = [
                55: "左 Command", 54: "右 Command",
                59: "左 Control", 62: "右 Control",
                58: "左 Option", 61: "右 Option",
                56: "左 Shift", 60: "右 Shift",
            ]
            let orderedCodes: [UInt16] = [59, 62, 58, 61, 56, 60, 55, 54]
            let modifiers = orderedCodes.compactMap { code in
                modifierKeyCodes.contains(code) ? labels[code] : nil
            }
            let primaryLabel = String(preview.drop(while: { "⌃⌥⇧⌘".contains($0) }))
            let keyLabel = primaryLabel.isEmpty ? "键码 \(primaryKeyCode)" : primaryLabel
            return (modifiers + [keyLabel]).joined(separator: " + ")
        case let .modifierChord(modifierKeyCodes):
            let labels = Self.modifierDisplayLabels
            return Self.modifierDisplayOrder.compactMap { code in
                modifierKeyCodes.contains(code) ? labels[code] : nil
            }.joined(separator: " + ")
        }
    }

    private static let modifierDisplayLabels: [UInt16: String] = [
        55: "左 Command", 54: "右 Command",
        59: "左 Control", 62: "右 Control",
        58: "左 Option", 61: "右 Option",
        56: "左 Shift", 60: "右 Shift",
    ]

    private static let modifierDisplayOrder: [UInt16] = [59, 62, 58, 61, 56, 60, 55, 54]

    var physicalIdentity: String {
        switch self {
        case let .pureModifier(key): return "modifier:\(key.rawValue)"
        case let .chord(primary, _, modifiers):
            return "chord:\(primary):\(modifiers.sorted().map(String.init).joined(separator: ","))"
        case let .modifierChord(modifiers):
            return "modifier-chord:\(modifiers.sorted().map(String.init).joined(separator: ","))"
        }
    }

    var usesVoiceShortcutEmitter: Bool {
        switch self {
        case .chord, .modifierChord: return true
        case .pureModifier: return false
        }
    }

    var diagnosticFields: [String: Any] {
        switch self {
        case let .pureModifier(key):
            return [
                "binding_kind": "pure_modifier",
                "primary_key_code": Int(key.cgKeyCode),
                "modifier_key_codes": [Int(key.cgKeyCode)],
            ]
        case let .chord(primaryKeyCode, _, modifierKeyCodes):
            return [
                "binding_kind": "chord",
                "primary_key_code": Int(primaryKeyCode),
                "modifier_key_codes": modifierKeyCodes.map(Int.init),
            ]
        case let .modifierChord(modifierKeyCodes):
            return [
                "binding_kind": "modifier_chord",
                "modifier_key_codes": modifierKeyCodes.sorted().map(Int.init),
            ]
        }
    }

    var diagnosticPrimaryKeyCode: UInt16? {
        switch self {
        case let .chord(primaryKeyCode, _, _): return primaryKeyCode
        case .pureModifier, .modifierChord: return nil
        }
    }

    var diagnosticModifierKeyCodes: [UInt16] {
        switch self {
        case let .pureModifier(key): [key.cgKeyCode]
        case let .chord(_, _, modifierKeyCodes): modifierKeyCodes
        case let .modifierChord(modifierKeyCodes): modifierKeyCodes.sorted()
        }
    }
}

struct VoiceShortcutEntry: Codable, Equatable, Identifiable {
    let id: String
    var displayName: String
    var binding: VoiceShortcutBinding

    init(id: String = UUID().uuidString.lowercased(), displayName: String, binding: VoiceShortcutBinding) {
        self.id = id
        self.displayName = displayName
        self.binding = binding
    }

    var profile: VoiceInputProfile {
        VoiceInputProfile(id: id, displayName: displayName, binding: binding)
    }

    var diagnosticFields: [String: Any] {
        var fields = binding.diagnosticFields
        fields["entry_id"] = id
        return fields
    }
}

struct VoiceShortcutSnapshot: Codable, Equatable {
    let schemaVersion: Int
    var entries: [VoiceShortcutEntry]
    var activeEntryID: String

    static func seeded(activeEntryID: String = VoiceInputProfile.defaultProfile.id) -> Self {
        Self(
            schemaVersion: VoiceShortcutStore.schemaVersion,
            entries: VoiceInputProfile.legacySeeds.map {
                VoiceShortcutEntry(id: $0.id, displayName: $0.displayName, binding: $0.binding)
            },
            activeEntryID: activeEntryID
        )
    }

    var activeEntry: VoiceShortcutEntry? {
        entries.first { $0.id == activeEntryID }
    }
}

enum VoiceShortcutValidationError: Error, Equatable, LocalizedError {
    case invalidName
    case duplicateName
    case invalidBinding
    case duplicateBinding
    case cannotDeleteLast
    case invalidSnapshot
    case unsupportedSchema(Int)
    case readbackMismatch
    case notMainThread

    var errorDescription: String? {
        switch self {
        case .invalidName: return "名称需为 1–64 个字符，且不能只包含空白。"
        case .duplicateName: return "已有同名语音快捷键，请更改名称。"
        case .invalidBinding: return "此按键组合不能用作语音快捷键。"
        case .duplicateBinding: return "此物理按键组合已被另一个语音快捷键使用。"
        case .cannotDeleteLast: return "至少需要保留一个语音快捷键。"
        case .invalidSnapshot: return "语音快捷键数据无效，已进入只读兼容模式。"
        case let .unsupportedSchema(version): return "语音快捷键数据版本 \(version) 暂不支持，已保留原数据并进入只读模式。"
        case .readbackMismatch: return "语音快捷键保存后回读不一致，运行时已回滚。"
        case .notMainThread: return "语音快捷键配置只能由主线程提交。"
        }
    }
}

enum VoiceShortcutLoadResult {
    case writable(VoiceShortcutSnapshot)
    case readOnly(snapshot: VoiceShortcutSnapshot, reason: VoiceShortcutValidationError)

    var snapshot: VoiceShortcutSnapshot {
        switch self {
        case let .writable(snapshot), let .readOnly(snapshot, _): return snapshot
        }
    }

    var isWritable: Bool {
        if case .writable = self { return true }
        return false
    }

    var reason: VoiceShortcutValidationError? {
        if case let .readOnly(_, reason) = self { return reason }
        return nil
    }
}

/// UI-facing projection only. AppController and the persisted snapshot remain
/// the sole runtime/configuration owners.
final class VoiceShortcutPresentation: ObservableObject {
    static let shared = VoiceShortcutPresentation()

    @Published private(set) var snapshot = VoiceShortcutSnapshot.seeded()
    @Published private(set) var readOnlyReason: VoiceShortcutValidationError?
    var updateSnapshot: (
        VoiceShortcutSnapshot,
        @escaping (VoiceTriggerApplyResult) -> Void
    ) -> Void = { _, completion in completion(.locked) }

    func replace(snapshot: VoiceShortcutSnapshot, readOnlyReason: VoiceShortcutValidationError?) {
        self.snapshot = snapshot
        self.readOnlyReason = readOnlyReason
    }
}

enum VoiceShortcutStore {
    static let snapshotKey = "RemoteOrbit.voiceShortcuts.snapshot.v1"
    static let schemaVersion = 1
    static let maximumNameLength = 64
    private static let modifierKeyCodes: Set<UInt16> = [54, 55, 56, 58, 59, 60, 61, 62]
    // macOS virtual key codes from HIToolbox/Events.h that represent usable
    // keyboard keys. Media, modifier-only, input-method, reserved and unknown
    // codes are deliberately omitted so a restored snapshot is checked too.
    // F14/F15 are omitted because Apple keyboards use them for display brightness.
    private static let supportedPrimaryKeyCodes: Set<UInt16> = Set(0...51).union([
        64, 65, 67, 69, 71, 75, 76, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89,
        90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 103, 105, 106, 109,
        111, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126,
    ])

    /// AppController is the sole runtime owner and calls mutation APIs from its
    /// main-thread state transitions. Invalid bytes are never replaced by a seed.
    static func load(from defaults: UserDefaults) -> VoiceShortcutLoadResult {
        guard let data = defaults.data(forKey: snapshotKey) else {
            let activeID = initialActiveEntryID(from: defaults)
            let snapshot = VoiceShortcutSnapshot.seeded(activeEntryID: activeID)
            do {
                try persist(snapshot, to: defaults)
                return .writable(snapshot)
            } catch let error as VoiceShortcutValidationError {
                return .readOnly(snapshot: snapshot, reason: error)
            } catch {
                return .readOnly(snapshot: snapshot, reason: .readbackMismatch)
            }
        }

        guard let snapshot = try? JSONDecoder().decode(VoiceShortcutSnapshot.self, from: data) else {
            return .readOnly(snapshot: fallbackSnapshot(from: defaults), reason: .invalidSnapshot)
        }
        guard snapshot.schemaVersion == schemaVersion else {
            return .readOnly(
                snapshot: fallbackSnapshot(from: defaults),
                reason: .unsupportedSchema(snapshot.schemaVersion)
            )
        }
        do {
            try validate(snapshot)
        } catch {
            return .readOnly(snapshot: fallbackSnapshot(from: defaults), reason: .invalidSnapshot)
        }

        // A stale active ID is repaired in memory only. The next explicit,
        // successful user edit is the first operation permitted to persist it.
        if !snapshot.entries.contains(where: { $0.id == snapshot.activeEntryID }),
           let first = snapshot.entries.first {
            var repaired = snapshot
            repaired.activeEntryID = first.id
            return .writable(repaired)
        }
        return .writable(snapshot)
    }

    static func migrate(from defaults: UserDefaults) {
        _ = load(from: defaults)
    }

    static func persist(_ snapshot: VoiceShortcutSnapshot, to defaults: UserDefaults) throws {
        guard Thread.isMainThread else { throw VoiceShortcutValidationError.notMainThread }
        try validate(snapshot)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(snapshot)
        let oldData = defaults.data(forKey: snapshotKey)
        defaults.set(data, forKey: snapshotKey)
        guard defaults.data(forKey: snapshotKey) == data else {
            if let oldData {
                defaults.set(oldData, forKey: snapshotKey)
            } else {
                defaults.removeObject(forKey: snapshotKey)
            }
            throw VoiceShortcutValidationError.readbackMismatch
        }
    }

    static func validate(_ snapshot: VoiceShortcutSnapshot) throws {
        guard snapshot.schemaVersion == schemaVersion,
              !snapshot.entries.isEmpty,
              snapshot.entries.allSatisfy({ !$0.id.isEmpty && $0.id.count <= 128 }),
              Set(snapshot.entries.map(\.id)).count == snapshot.entries.count
        else { throw VoiceShortcutValidationError.invalidSnapshot }

        var names = Set<String>()
        var bindings = Set<String>()
        for entry in snapshot.entries {
            let normalizedName = normalizedNameKey(entry.displayName)
            guard !normalizedName.isEmpty,
                  entry.displayName.trimmingCharacters(in: .whitespacesAndNewlines).count <= maximumNameLength
            else { throw VoiceShortcutValidationError.invalidName }
            guard names.insert(normalizedName).inserted else {
                throw VoiceShortcutValidationError.duplicateName
            }
            try validate(binding: entry.binding)
            guard bindings.insert(entry.binding.physicalIdentity).inserted else {
                throw VoiceShortcutValidationError.duplicateBinding
            }
        }
    }

    static func validate(binding: VoiceShortcutBinding) throws {
        switch binding {
        case .pureModifier:
            return
        case let .chord(primary, preview, modifiers):
            guard supportedPrimaryKeyCodes.contains(primary),
                  !modifierKeyCodes.contains(primary),
                  preview.count <= 24,
                  !preview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !modifiers.isEmpty,
                  isValidModifierCombination(modifiers)
            else { throw VoiceShortcutValidationError.invalidBinding }
        case let .modifierChord(modifiers):
            guard modifiers.count >= 2,
                  isValidModifierCombination(modifiers)
            else { throw VoiceShortcutValidationError.invalidBinding }
        }
    }

    private static func isValidModifierCombination(_ modifiers: [UInt16]) -> Bool {
        guard Set(modifiers).count == modifiers.count,
              modifiers.allSatisfy({ modifierKeyCodes.contains($0) })
        else { return false }
        let families = modifiers.map(modifierFamily(for:))
        return Set(families).count == families.count
    }

    private static func modifierFamily(for keyCode: UInt16) -> UInt16 {
        switch keyCode {
        case 54, 55: return 1 // Command
        case 59, 62: return 2 // Control
        case 58, 61: return 3 // Option
        case 56, 60: return 4 // Shift
        default: return keyCode
        }
    }

    static func replacingEntry(
        _ entry: VoiceShortcutEntry,
        in snapshot: VoiceShortcutSnapshot
    ) throws -> VoiceShortcutSnapshot {
        var normalizedEntry = entry
        normalizedEntry.displayName = entry.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        var updated = snapshot
        if let index = updated.entries.firstIndex(where: { $0.id == normalizedEntry.id }) {
            updated.entries[index] = normalizedEntry
        } else {
            updated.entries.append(normalizedEntry)
        }
        try validate(updated)
        return updated
    }

    static func deletingEntry(
        id: String,
        from snapshot: VoiceShortcutSnapshot,
        replacementActiveID: String? = nil
    ) throws -> VoiceShortcutSnapshot {
        guard snapshot.entries.count > 1 else { throw VoiceShortcutValidationError.cannotDeleteLast }
        var updated = snapshot
        updated.entries.removeAll { $0.id == id }
        if updated.activeEntryID == id {
            guard let replacementActiveID,
                  updated.entries.contains(where: { $0.id == replacementActiveID })
            else { throw VoiceShortcutValidationError.invalidSnapshot }
            updated.activeEntryID = replacementActiveID
        }
        try validate(updated)
        return updated
    }

    private static func normalizedNameKey(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func initialActiveEntryID(from defaults: UserDefaults) -> String {
        if let id = defaults.string(forKey: VoiceInputProfileStore.selectedProfileIDKey),
           VoiceInputProfile.legacySeeds.contains(where: { $0.id == id }) {
            return id
        }
        let legacyKey = AppStorage.readMomentaryVoiceTriggerKey(from: defaults)
        return VoiceInputProfile.legacySeeds.first {
            $0.binding.pureModifierKey == legacyKey
        }?.id ?? VoiceInputProfile.defaultProfile.id
    }

    private static func fallbackSnapshot(from defaults: UserDefaults) -> VoiceShortcutSnapshot {
        VoiceShortcutSnapshot.seeded(activeEntryID: initialActiveEntryID(from: defaults))
    }
}
