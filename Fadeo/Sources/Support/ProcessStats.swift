import Foundation

/// Self-reported resident memory, so the efficiency pillar's numbers (PLAN.md §11 ship
/// gate: RSS < ~15 MB headless / ~40 MB with window) are visible in the app itself, not
/// just something you have to open Activity Monitor to check.
enum ProcessStats {
    static func residentMemoryMB() -> Double? {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return Double(info.resident_size) / 1_048_576.0
    }
}
