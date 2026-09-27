import CoreGraphics

enum VoiceTriggerKey: String, CaseIterable, Codable, Equatable, Identifiable {
    case leftOption = "left_option"
    case rightOption = "right_option"
    case leftControl = "left_control"
    case rightControl = "right_control"

    static let defaultValue: VoiceTriggerKey = .leftOption

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .leftOption: return "左 Option"
        case .rightOption: return "右 Option"
        case .leftControl: return "左 Control"
        case .rightControl: return "右 Control"
        }
    }

    var hidUsage: UInt16 {
        switch self {
        case .leftOption: return 0xE2
        case .rightOption: return 0xE6
        case .leftControl: return 0xE0
        case .rightControl: return 0xE4
        }
    }

    var hidutilDestination: UInt64 {
        switch self {
        case .leftOption: return 0x7000000E2
        case .rightOption: return 0x7000000E6
        case .leftControl: return 0x7000000E0
        case .rightControl: return 0x7000000E4
        }
    }

    var cgKeyCode: CGKeyCode {
        switch self {
        case .leftOption: return 58
        case .rightOption: return 61
        case .leftControl: return 59
        case .rightControl: return 62
        }
    }

    var cgEventFlag: CGEventFlags {
        switch self {
        case .leftOption, .rightOption: return .maskAlternate
        case .leftControl, .rightControl: return .maskControl
        }
    }
}
