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

    static func wallClockISO8601() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}
