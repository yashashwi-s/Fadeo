import Foundation
import FadeoCore

/// Time/weekday sensor — deliberately NOT a polling tick loop. Computes the single
/// soonest upcoming boundary (a `timeBetween` start/end, or the next midnight for
/// `weekdays` rules) across all enabled workspaces, arms exactly one
/// `DispatchSourceTimer` for it with a generous coalescing leeway, and re-arms for the
/// next boundary only when it fires. If no workspace uses time/weekday matching, the
/// timer stays disarmed entirely — zero cost (PLAN.md §11).
@MainActor
final class ScheduleSensor: Sensor {
    static let providedFields: Set<ContextField> = [.time, .weekday]

    private var timer: DispatchSourceTimer?
    private var emit: ((ContextPatch) -> Void)?
    private var workspaces: [Workspace] = []

    func start(emit: @escaping (ContextPatch) -> Void) {
        self.emit = emit
        armNextBoundary()
    }

    func stop() {
        timer?.cancel()
        timer = nil
        emit = nil
    }

    deinit { timer?.cancel() }

    /// The app calls this whenever config changes so boundaries stay current, whether or
    /// not the sensor is currently running (it may be about to start).
    func reschedule(workspaces: [Workspace]) {
        self.workspaces = workspaces
        guard emit != nil else { return }
        armNextBoundary()
    }

    private func armNextBoundary() {
        timer?.cancel()
        guard let interval = nextBoundaryInterval() else { timer = nil; return }
        let t = DispatchSource.makeTimerSource(queue: .main)
        // One-shot to the next boundary, not a repeating tick — and a generous leeway
        // since this is a single infrequent wakeup, not a latency-sensitive one.
        t.schedule(deadline: .now() + interval, leeway: .seconds(5))
        t.setEventHandler { [weak self] in
            guard let self else { return }
            self.emit?(ContextPatch(apply: { $0.localTime = Date() }, label: "schedule boundary"))
            self.armNextBoundary()   // roll forward to whatever's next
        }
        timer = t
        t.resume()
    }

    private func nextBoundaryInterval() -> TimeInterval? {
        let now = Date()
        let calendar = Calendar.current
        var candidates: [Date] = []

        for ws in workspaces where ws.enabled {
            if let window = ws.match.timeBetween {
                candidates.append(contentsOf: [
                    nextOccurrence(of: window.start, after: now, calendar: calendar),
                    nextOccurrence(of: window.end, after: now, calendar: calendar),
                ].compactMap { $0 })
            }
            if !ws.match.weekdays.isEmpty,
               let midnight = calendar.nextDate(
                   after: now, matching: DateComponents(hour: 0, minute: 0, second: 0),
                   matchingPolicy: .nextTime) {
                candidates.append(midnight)
            }
        }
        guard let soonest = candidates.min() else { return nil }
        return max(1, soonest.timeIntervalSince(now))
    }

    private func nextOccurrence(of hhmm: String, after date: Date, calendar: Calendar) -> Date? {
        let parts = hhmm.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        return calendar.nextDate(
            after: date, matching: DateComponents(hour: h, minute: m),
            matchingPolicy: .nextTimePreservingSmallerComponents)
    }
}
