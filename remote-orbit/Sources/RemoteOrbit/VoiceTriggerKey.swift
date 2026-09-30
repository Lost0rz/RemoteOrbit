import CoreGraphics
import IOKit.hidsystem

enum VoiceTriggerKey: String, CaseIterable, Codable, Equatable, Identifiable {
    case leftOption = "left_option"
    case rightOption = "right_option"
    case leftControl = "left_control"
    case rightControl = "right_control"
    case leftCommand = "left_command"
    case rightCommand = "right_command"

    static let defaultValue: VoiceTriggerKey = .leftOption

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .leftOption: return "左 Option"
        case .rightOption: return "右 Option"
        case .leftControl: return "左 Control"
        case .rightControl: return "右 Control"
        case .leftCommand: return "左 Command"
        case .rightCommand: return "右 Command"
        }
    }

    /// Stable English label for machine-readable diagnostic logs. Keep this
    /// separate from the localized settings label above.
    var diagnosticDisplayName: String {
        switch self {
        case .leftOption: return "Left Option"
        case .rightOption: return "Right Option"
        case .leftControl: return "Left Control"
        case .rightControl: return "Right Control"
        case .leftCommand: return "Left Command"
        case .rightCommand: return "Right Command"
        }
    }

    var hidUsage: UInt16 {
        switch self {
        case .leftOption: return 0xE2
        case .rightOption: return 0xE6
        case .leftControl: return 0xE0
        case .rightControl: return 0xE4
        case .leftCommand: return 0xE3
        case .rightCommand: return 0xE7
        }
    }

    var hidutilDestination: UInt64 {
        switch self {
        case .leftOption: return 0x7000000E2
        case .rightOption: return 0x7000000E6
        case .leftControl: return 0x7000000E0
        case .rightControl: return 0x7000000E4
        case .leftCommand: return 0x7000000E3
        case .rightCommand: return 0x7000000E7
        }
    }

    var cgKeyCode: CGKeyCode {
        switch self {
        case .leftOption: return 58
        case .rightOption: return 61
        case .leftControl: return 59
        case .rightControl: return 62
        case .leftCommand: return 55
        case .rightCommand: return 54
        }
    }

    var cgEventFlag: CGEventFlags {
        switch self {
        case .leftOption, .rightOption: return .maskAlternate
        case .leftControl, .rightControl: return .maskControl
        case .leftCommand, .rightCommand: return .maskCommand
        }
    }

    var deviceSideCGEventFlag: CGEventFlags {
        let mask: UInt64
        switch self {
        case .leftOption:
            mask = UInt64(NX_DEVICELALTKEYMASK)
        case .rightOption:
            mask = UInt64(NX_DEVICERALTKEYMASK)
        case .leftControl:
            mask = UInt64(NX_DEVICELCTLKEYMASK)
        case .rightControl:
            mask = UInt64(NX_DEVICERCTLKEYMASK)
        case .leftCommand:
            mask = UInt64(NX_DEVICELCMDKEYMASK)
        case .rightCommand:
            mask = UInt64(NX_DEVICERCMDKEYMASK)
        }
        return CGEventFlags(rawValue: mask)
    }

    var syntheticModifierFlags: CGEventFlags {
        cgEventFlag.union(deviceSideCGEventFlag)
    }
}
