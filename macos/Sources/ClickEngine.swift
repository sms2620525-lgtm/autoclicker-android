import Foundation
import ApplicationServices

struct TargetStats: Codable {
    let x: Double
    let y: Double
    var postedPairs: UInt64 = 0
}

struct RunStats: Codable {
    var active = false
    var postedPairs: UInt64 = 0
    var skippedSlots: UInt64 = 0
    var elapsedSeconds = 0.0
    var targetCPS = 5000
    var requestedSeconds = 10
    var targets: [TargetStats] = []
    var stopReason = "준비"
    var postedCPS: Double { elapsedSeconds > 0 ? Double(postedPairs) / elapsedSeconds : 0 }
}

final class ClickEngine {
    private let queue = DispatchQueue(label: "dev.tapbench.clicks", qos: .userInteractive)
    private let lock = NSLock()
    private var timer: DispatchSourceTimer?
    private var schedule: RunSchedule?
    private var stats = RunStats()
    private var events: [(down: CGEvent, up: CGEvent)] = []

    func start(points: [CGPoint], cps: Int, seconds: Int) -> Bool {
        guard AXIsProcessTrusted(), (1...5000).contains(cps), (1...3600).contains(seconds),
              (1...2).contains(points.count), points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }),
              let source = CGEventSource(stateID: .privateState) else { return false }
        source.localEventsSuppressionInterval = 0
        var prepared: [(down: CGEvent, up: CGEvent)] = []
        for point in points {
            guard let downEvent = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown,
                                          mouseCursorPosition: point, mouseButton: .left),
                  let upEvent = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp,
                                        mouseCursorPosition: point, mouseButton: .left) else { return false }
            for event in [downEvent, upEvent] {
                event.flags = []
                event.setIntegerValueField(.mouseEventClickState, value: 1)
            }
            downEvent.setDoubleValueField(.mouseEventPressure, value: 1)
            upEvent.setDoubleValueField(.mouseEventPressure, value: 0)
            prepared.append((downEvent, upEvent))
        }
        lock.lock()
        defer { lock.unlock() }
        guard !stats.active else { return false }
        let now = DispatchTime.now().uptimeNanoseconds
        schedule = RunSchedule(cps: cps, seconds: seconds, start: now)
        stats = RunStats(active: true, targetCPS: cps, requestedSeconds: seconds,
                         targets: points.map { TargetStats(x: $0.x, y: $0.y) }, stopReason: "실행 중")
        events = prepared
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
        guard due, !events.isEmpty else { return }
        let index = TargetOrder.index(after: stats.postedPairs, targetCount: events.count)
        let (down, up) = events[index]
        // Exactly one complete pair per callback. Nothing is queued after stop.
        let number = Int64(stats.postedPairs + 1)
        down.timestamp = now
        down.setIntegerValueField(.mouseEventNumber, value: number)
        down.post(tap: .cghidEventTap)
        up.timestamp = DispatchTime.now().uptimeNanoseconds
        up.setIntegerValueField(.mouseEventNumber, value: number)
        up.post(tap: .cghidEventTap)
        stats.postedPairs += 1
        stats.targets[index].postedPairs += 1
    }

    private func finishLocked(_ reason: String) {
        stats.active = false
        stats.stopReason = reason
        timer?.cancel()
        timer = nil
        events.removeAll()
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
