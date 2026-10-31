import Foundation

/// Process-local effective diagnostics state.
///
/// The persisted preference and environment override are sampled only when the
/// setting changes or the process starts. Producers use the in-memory value on
/// their hot path, so disabled diagnostics do not read UserDefaults, touch the
/// filesystem, serialize JSON, or synchronously dispatch.
final class DiagnosticsRuntimeGate: @unchecked Sendable {
    static let shared = DiagnosticsRuntimeGate()

    private let lock = NSLock()
    private var loggingEnabled = false
    private var environmentOverrideEnabled = false
    private var effectiveEnabled = false
    private var observers: [(@Sendable (Bool) -> Void)] = []

    @inline(__always)
    var isEnabled: Bool {
        lock.lock()
        let value = effectiveEnabled
        lock.unlock()
        return value
    }

    var isEnvironmentOverrideEnabled: Bool {
        lock.lock()
        let value = environmentOverrideEnabled
        lock.unlock()
        return value
    }

    func configureFromProcessEnvironment(loggingEnabled: Bool) {
        update(
            loggingEnabled: loggingEnabled,
            environmentOverrideEnabled:
                ProcessInfo.processInfo.environment["REMOTE_ORBIT_DIAGNOSTICS"] == "1"
        )
    }

    func setLoggingEnabled(_ enabled: Bool) {
        lock.lock()
        let environmentOverrideEnabled = self.environmentOverrideEnabled
        lock.unlock()
        update(
            loggingEnabled: enabled,
            environmentOverrideEnabled: environmentOverrideEnabled
        )
    }

    /// Test seam for deterministic gate tests without mutating the process
    /// environment. Production callers should use the two lifecycle methods
    /// above.
    func configureForTesting(
        loggingEnabled: Bool,
        environmentOverrideEnabled: Bool = false
    ) {
        update(
            loggingEnabled: loggingEnabled,
            environmentOverrideEnabled: environmentOverrideEnabled
        )
    }

    func observe(_ observer: @escaping @Sendable (Bool) -> Void) {
        lock.lock()
        observers.append(observer)
        let currentValue = effectiveEnabled
        lock.unlock()
        observer(currentValue)
    }

    private func update(
        loggingEnabled: Bool,
        environmentOverrideEnabled: Bool
    ) {
        lock.lock()
        self.loggingEnabled = loggingEnabled
        self.environmentOverrideEnabled = environmentOverrideEnabled
        let nextValue = loggingEnabled || environmentOverrideEnabled
        let changed = nextValue != effectiveEnabled
        effectiveEnabled = nextValue
        let observers = changed ? self.observers : []
        lock.unlock()

        guard changed else { return }
        for observer in observers {
            observer(nextValue)
        }
    }
}
