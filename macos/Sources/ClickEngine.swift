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
    var targetCPS = ClickLimits.defaultCPS
    var requestedSeconds = 10
    var mode: ClickMode = .fast
    var targets: [TargetStats] = []
    var stopReason = "준비"
    var postedCPS: Double { elapsedSeconds > 0 ? Double(postedPairs) / elapsedSeconds : 0 }
}

final class ClickEngine {
    typealias PairOutput = (_ target: Int, _ time: UInt64, _ number: Int64) -> Void
    private let queue = DispatchQueue(label: "dev.tapbench.clicks", qos: .userInteractive)
    private let lock = NSLock()
    private let now: () -> UInt64
    private let prepare: ([CGPoint]) -> PairOutput?
    private let usesTimer: Bool
    private var timer: DispatchSourceTimer?
    private var schedule: RunSchedule?
    private var stats = RunStats()
    private var output: PairOutput?
    private var reservedPairs = 0
    private(set) var generation: UInt64 = 0

    // CI exercises the actual engine with a fake clock/output, without desktop input.
    init(now: @escaping () -> UInt64 = { DispatchTime.now().uptimeNanoseconds },
         prepare: @escaping ([CGPoint]) -> PairOutput? = ClickEngine.systemOutput,
         usesTimer: Bool = true) {
        self.now = now
        self.prepare = prepare
        self.usesTimer = usesTimer
    }

    static func systemOutput(points: [CGPoint]) -> PairOutput? {
        guard AXIsProcessTrusted(), let source = CGEventSource(stateID: .privateState) else { return nil }
        source.localEventsSuppressionInterval = 0
        var prepared: [(down: CGEvent, up: CGEvent)] = []
        for point in points {
            guard let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown,
                                     mouseCursorPosition: point, mouseButton: .left),
                  let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp,
                                   mouseCursorPosition: point, mouseButton: .left) else { return nil }
            for event in [down, up] {
                event.flags = []
                event.setIntegerValueField(.mouseEventClickState, value: 1)
            }
            down.setDoubleValueField(.mouseEventPressure, value: 1)
            up.setDoubleValueField(.mouseEventPressure, value: 0)
            prepared.append((down, up))
        }
        // Reuse the two event objects per target, including in fast mode.
        return { index, time, number in
            let (down, up) = prepared[index]
            down.timestamp = time
            down.setIntegerValueField(.mouseEventNumber, value: number)
            down.post(tap: .cghidEventTap)
            up.timestamp = DispatchTime.now().uptimeNanoseconds
            up.setIntegerValueField(.mouseEventNumber, value: number)
            up.post(tap: .cghidEventTap)
        }
    }

    func start(points: [CGPoint], cps: Int, seconds: Int, mode: ClickMode = .fast) -> Bool {
        guard (1...ClickLimits.maxCPS).contains(cps), (1...3600).contains(seconds),
              (1...2).contains(points.count), points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }),
              let prepared = prepare(points) else { return false }
        lock.lock()
        defer { lock.unlock() }
        guard !stats.active else { return false }
        generation &+= 1
        let run = generation
        schedule = RunSchedule(cps: cps, seconds: seconds, start: now())
        stats = RunStats(active: true, targetCPS: cps, requestedSeconds: seconds, mode: mode,
                         targets: points.map { TargetStats(x: $0.x, y: $0.y) }, stopReason: "실행 중")
        output = prepared
        reservedPairs = 0
        if usesTimer {
            let source = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
            source.schedule(deadline: .now(), repeating: .nanoseconds(Int(mode.timerInterval(cps: cps))),
                            leeway: .nanoseconds(0))
            source.setEventHandler { [weak self] in self?.tick(generation: run) }
            timer = source
            source.resume()
        }
        return true
    }

    // The serial queue allows one batch at a time; generation rejects old queued callbacks.
    func tick(generation run: UInt64) {
        lock.lock()
        guard stats.active, run == generation, var current = schedule else { lock.unlock(); return }
        let time = now()
        stats.elapsedSeconds = Double(min(time, current.end) - current.start) / 1e9
        guard time < current.end else { finishLocked("시간 완료"); lock.unlock(); return }
        let count = current.takeBatch(at: time, limit: stats.mode.batchLimit)
        schedule = current
        stats.skippedSlots = current.skipped
        reservedPairs = count
        lock.unlock()

        for _ in 0..<count {
            lock.lock()
            guard stats.active, run == generation, let post = output else { lock.unlock(); return }
            let time = now()
            guard time < current.end else {
                stats.elapsedSeconds = Double(current.end - current.start) / 1e9
                finishLocked("시간 완료")
                lock.unlock()
                return
            }
            let index = TargetOrder.index(after: stats.postedPairs, targetCount: stats.targets.count)
            // Keep down/up together; release between pairs so stop need not wait for a batch.
            post(index, time, Int64(stats.postedPairs + 1))
            stats.postedPairs += 1
            stats.targets[index].postedPairs += 1
            reservedPairs -= 1
            lock.unlock()
        }
    }

    private func finishLocked(_ reason: String) {
        stats.active = false
        stats.stopReason = reason
        stats.skippedSlots += UInt64(reservedPairs)
        reservedPairs = 0
        timer?.cancel()
        timer = nil
        output = nil
    }

    func stop(_ reason: String = "사용자 중지") {
        lock.lock()
        defer { lock.unlock() }
        guard stats.active else { return }
        if let current = schedule {
            stats.elapsedSeconds = Double(min(now(), current.end) - current.start) / 1e9
        }
        finishLocked(reason)
    }

    func snapshot() -> RunStats {
        lock.lock()
        defer { lock.unlock() }
        var result = stats
        if stats.active, let current = schedule {
            result.elapsedSeconds = Double(min(now(), current.end) - current.start) / 1e9
        }
        return result
    }
}
