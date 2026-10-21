import Foundation
import ApplicationServices

@main
struct EngineTests {
    static func main() {
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ description: String) {
            guard value() else { fatalError("FAIL: \(description)") }
            checks += 1
        }
        let points = [CGPoint(x: 10, y: 10), CGPoint(x: 20, y: 20)]
        var clock: UInt64 = 0
        var targets: [Int] = []
        var numbers: [Int64] = []
        let engine = ClickEngine(now: { clock }, prepare: { _ in
            { index, _, number in targets.append(index); numbers.append(number) }
        }, usesTimer: false)
        check(engine.start(points: points, cps: 10_000, seconds: 1), "start fast engine")
        let firstRun = engine.generation
        engine.tick(generation: firstRun)
        clock = 1_000_000
        engine.tick(generation: firstRun)
        check(engine.snapshot().postedPairs == 11, "counts only the eleven calls actually emitted")
        engine.tick(generation: firstRun)
        check(engine.snapshot().postedPairs == 11, "duplicate callback does not send")
        clock = 100_000_000
        engine.tick(generation: firstRun)
        check(engine.snapshot().postedPairs == 43, "long delay emits only one bounded batch")
        check(engine.snapshot().skippedSlots == 958, "engine exposes dropped backlog")
        check(targets == (0..<43).map { $0 % 2 }, "alternation survives fast batches and skipped backlog")
        check(numbers == (1...43).map { Int64($0) }, "event numbers follow actual pairs")
        check(engine.snapshot().targets.map { $0.postedPairs } == [22, 21], "per-target totals agree")
        engine.stop()
        engine.tick(generation: firstRun)
        check(targets.count == 43 && !engine.snapshot().active, "no output after stopping")
        check(engine.start(points: points, cps: 5000, seconds: 1, mode: .steady), "restart in legacy mode")
        engine.tick(generation: firstRun)
        check(engine.snapshot().postedPairs == 0, "queued callback from old run cannot affect new run")
        let secondRun = engine.generation
        engine.tick(generation: secondRun)
        check(targets.last == 0, "restart begins at first target")
        clock += 1_000_000
        engine.tick(generation: secondRun)
        check(engine.snapshot().postedPairs == 2, "legacy mode emits one pair per callback")
        engine.stop()
        for rate in [0, -1, 20_001, Int.max] {
            check(!engine.start(points: points, cps: rate, seconds: 1), "reject invalid CPS \(rate)")
        }
        check(!engine.start(points: [], cps: 10_000, seconds: 1), "reject missing target")
        check(!engine.start(points: points + points, cps: 10_000, seconds: 1), "reject unsupported target count")
        let denied = ClickEngine(prepare: { _ in nil }, usesTimer: false)
        check(!denied.start(points: points, cps: 10_000, seconds: 1), "cannot start without a usable output")

        var deadlineClock: UInt64 = 0
        var sentAt: [UInt64] = []
        let deadline = ClickEngine(now: { deadlineClock }, prepare: { _ in
            { _, time, _ in sentAt.append(time); deadlineClock += 50_000 }
        }, usesTimer: false)
        check(deadline.start(points: points, cps: 20_000, seconds: 1), "start deadline fixture")
        deadlineClock = 999_900_000
        deadline.tick(generation: deadline.generation)
        check(sentAt == [999_900_000, 999_950_000], "deadline checked between pairs within a batch")
        check(!deadline.snapshot().active && deadline.snapshot().elapsedSeconds == 1, "deadline stops engine")
        check(deadline.snapshot().postedPairs == 2, "unposted reservations are never counted as clicks")

        // Real concurrent stop while the output is in flight; no system input is posted.
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let finished = DispatchSemaphore(value: 0)
        let stopped = DispatchSemaphore(value: 0)
        let stopping = DispatchSemaphore(value: 0)
        var racingClock: UInt64 = 0
        let racing = ClickEngine(now: { racingClock }, prepare: { _ in
            { _, _, number in
                if number == 1 { entered.signal(); _ = release.wait(timeout: .now() + 2) }
            }
        }, usesTimer: false)
        check(racing.start(points: points, cps: 10_000, seconds: 1), "start concurrent stop fixture")
        racingClock = 1_000_000
        let racingRun = racing.generation
        DispatchQueue.global().async { racing.tick(generation: racingRun); finished.signal() }
        check(entered.wait(timeout: .now() + 2) == .success, "output entered")
        let snapshotReady = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            let snapshot = racing.snapshot()
            precondition(snapshot.active && snapshot.postedPairs == 0,
                         "in-flight output is not counted as completed")
            snapshotReady.signal()
        }
        check(snapshotReady.wait(timeout: .now() + 0.5) == .success,
              "UI snapshot remains responsive while OS output is blocked")
        DispatchQueue.global().async { stopping.signal(); racing.stop(); stopped.signal() }
        check(stopping.wait(timeout: .now() + 2) == .success, "stop requested during output")
        release.signal()
        check(stopped.wait(timeout: .now() + 2) == .success, "stop completes after in-flight pair")
        let atStop = racing.snapshot().postedPairs
        check(finished.wait(timeout: .now() + 2) == .success, "in-flight callback finishes")
        racing.tick(generation: racingRun)
        check(racing.snapshot().postedPairs == atStop && (1...11).contains(atStop), "nothing is emitted after stop returns, even during a batch")
        print("PASS: \(checks) engine checks using a fake output. No actual mouse clicks or received-CPS claims.")
    }
}
