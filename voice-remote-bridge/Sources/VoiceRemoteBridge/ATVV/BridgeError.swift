// Copyright (c) 2026 FanXeon@Poemcoder with Codex
// Minimal local error type for protocol failures.
import Foundation

enum BridgeError: LocalizedError {
    case protocolFailure(String)

    var errorDescription: String? {
        switch self {
        case .protocolFailure(let message):
            return message
        }
    }
}
