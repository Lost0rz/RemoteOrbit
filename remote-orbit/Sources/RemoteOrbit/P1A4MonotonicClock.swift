import Darwin
import Foundation

/// Observation-only clock used by the P1-A4 correlation events.
///
/// It deliberately has no role in audio scheduling or voice state. The
/// value is process-local and monotonic; wall-clock strings are emitted only
/// as a human-readable companion to the monotonic value.
enum P1A4MonotonicClock {
    private static var timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    static func nowNanoseconds() -> UInt64 {
        let ticks = mach_continuous_time()
        return ticks
            .multipliedReportingOverflow(by: UInt64(timebase.numer)).partialValue
            / UInt64(timebase.denom)
    }

    /// Captures run-level evidence for correlating Quartz event timestamps with
    /// the process uptime clock. This is sampled once at application startup and
    /// is never used by the event-tap decision path.
    static func runStartCalibrationFields() -> [String: Any] {
        let calibrationTimebase = timebase
        guard calibrationTimebase.numer > 0,
              calibrationTimebase.denom > 0 else {
            return [:]
        }

        let machAbsoluteRaw = mach_absolute_time()
        let processUptime = ProcessInfo.processInfo.systemUptime
        return [
            "mach_timebase_numer": calibrationTimebase.numer,
            "mach_timebase_denom": calibrationTimebase.denom,
            "anchor_mach_absolute_raw": machAbsoluteRaw,
            "anchor_mach_clock": "mach_absolute_time",
            "anchor_process_uptime_seconds": processUptime,
        ]
    }

    static func wallClockISO8601() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}
