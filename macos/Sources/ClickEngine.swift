import Foundation
import ApplicationServices

struct RunStats: Codable {
    var active = false
    var postedPairs: UInt64 = 0
    var skippedSlots: UInt64 = 0
    var elapsedSeconds = 0.0
    var targetCPS = 5000
    var requestedSeconds = 10
    var x = 0.0
    var y = 0.0
    var stopReason = "준비"
    var postedCPS: Double { elapsedSeconds > 0 ? Double(postedPairs) / elapsedSeconds : 0 }
}

final class ClickEngine {
    private let queue = DispatchQueue(label: "dev.tapbench.clicks", qos: .userInteractive)
    private let lock = NSLock()
    private var timer: DispatchSourceTimer?
    private var schedule: RunSchedule?
    private var stats = RunStats()
    private var down: CGEvent?
    private var up: CGEvent?

    func start(point: CGPoint, cps: Int, seconds: Int) -> Bool {
        guard AXIsProcessTrusted(), (1...5000).contains(cps), (1...3600).contains(seconds),
              let source = CGEventSource(stateID: .privateState),
              let downEvent = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown,
                                      mouseCursorPosition: point, mouseButton: .left),
              let upEvent = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp,
                                    mouseCursorPosition: point, mouseButton: .left) else { return false }
        source.localEventsSuppressionInterval = 0
        for event in [downEvent, upEvent] {
            event.flags = []
            event.setIntegerValueField(.mouseEventClickState, value: 1)
        }
        downEvent.setDoubleValueField(.mouseEventPressure, value: 1)
        upEvent.setDoubleValueField(.mouseEventPressure, value: 0)
        lock.lock()
        defer { lock.unlock() }
        guard !stats.active else { return false }
        let now = DispatchTime.now().uptimeNanoseconds
        schedule = RunSchedule(cps: cps, seconds: seconds, start: now)
        stats = RunStats(active: true, targetCPS: cps, requestedSeconds: seconds,
                         x: point.x, y: point.y, stopReason: "실행 중")
        down = downEvent
        up = upEvent
        let sourceTimer = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
        sourceTimer.schedule(deadline: .now(), repeating: .nanoseconds(Int(schedule!.interval)),
                             leeway: .nanoseconds(0))
        sourceTimer.setEventHandler { [weak self] in self?.tick() }
        timer = sourceTimer
        sourceTimer.resume()
        return true
    }

    private func tick() {
        lock.lock()
        defer { lock.unlock() }
        guard stats.active, var current = schedule else { return }
        let now = DispatchTime.now().uptimeNanoseconds
        stats.elapsedSeconds = Double(min(now, current.end) - current.start) / 1e9
        if now >= current.end {
            finishLocked("시간 완료")
            return
        }
        let due = current.takeSlot(at: now)
        schedule = current
        stats.skippedSlots = current.skipped
        guard due, let down = down, let up = up else { return }
        // Exactly one complete pair per callback. Nothing is queued after stop.
        let number = Int64(stats.postedPairs + 1)
        down.timestamp = now
        down.setIntegerValueField(.mouseEventNumber, value: number)
        down.post(tap: .cghidEventTap)
        up.timestamp = DispatchTime.now().uptimeNanoseconds
        up.setIntegerValueField(.mouseEventNumber, value: number)
        up.post(tap: .cghidEventTap)
        stats.postedPairs += 1
    }

    private func finishLocked(_ reason: String) {
        stats.active = false
        stats.stopReason = reason
        timer?.cancel()
        timer = nil
        down = nil
        up = nil
    }

    func stop(_ reason: String = "사용자 중지") {
        lock.lock()
        defer { lock.unlock() }
        guard stats.active else { return }
        if let current = schedule {
            let now = min(DispatchTime.now().uptimeNanoseconds, current.end)
            stats.elapsedSeconds = Double(now - current.start) / 1e9
        }
        finishLocked(reason)
    }

    func snapshot() -> RunStats {
        lock.lock()
        defer { lock.unlock() }
        var result = stats
        if stats.active, let current = schedule {
            result.elapsedSeconds = Double(min(DispatchTime.now().uptimeNanoseconds, current.end) - current.start) / 1e9
        }
        return result
    }
}
