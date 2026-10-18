import Foundation

@main
struct ScheduleTests {
    static func main() {
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ description: String) {
            guard value() else { fatalError("FAIL: \(description)") }
            checks += 1
        }
        var schedule = RunSchedule(cps: 5000, seconds: 1, start: 1_000_000_000)
        check(!schedule.takeSlot(at: 999_999_999), "no early clicks")
        check(schedule.takeSlot(at: 1_000_000_000), "first click at start")
        check(!schedule.takeSlot(at: 1_000_000_000), "no duplicate slot")
        check(!schedule.takeSlot(at: 1_000_199_999), "respect 200 microsecond spacing")
        check(schedule.takeSlot(at: 1_000_200_000), "next slot")
        check(schedule.takeSlot(at: 1_001_000_000), "late callback emits one click")
        check(schedule.skipped == 3, "late slots dropped and counted")
        check(!schedule.takeSlot(at: 1_001_000_000), "no catch-up burst")
        check(!schedule.takeSlot(at: 2_000_000_000), "deadline excluded")
        check(!schedule.takeSlot(at: 3_000_000_000), "nothing after duration")
        var dense = RunSchedule(cps: 5000, seconds: 10, start: 0)
        var total = 0
        for t in stride(from: UInt64(0), to: UInt64(10_000_000_000), by: 200_000) {
            if dense.takeSlot(at: t) { total += 1 }
        }
        check(total == 50_000, "exact 5000/s scheduled over ten seconds")
        check(dense.skipped == 0, "no skipped slots with ideal clock")
        var slow = RunSchedule(cps: 1, seconds: 2, start: 0)
        check(slow.takeSlot(at: 0), "one CPS start")
        check(!slow.takeSlot(at: 999_999_999), "one CPS limit")
        check(slow.takeSlot(at: 1_000_000_000), "one CPS next second")
        check(!slow.takeSlot(at: 2_000_000_000), "one CPS deadline")
        check((0..<6).map { TargetOrder.index(after: UInt64($0), targetCount: 2) } == [0, 1, 0, 1, 0, 1], "two points alternate")
        check((0..<6).allSatisfy { TargetOrder.index(after: UInt64($0), targetCount: 1) == 0 }, "single point remains supported")
        var late = RunSchedule(cps: 5000, seconds: 1, start: 0)
        var routed: [Int] = []
        let times: [UInt64] = [0, 400_000, 1_200_000, 1_200_000, 1_600_000]
        for time in times {
            if late.takeSlot(at: time) {
                routed.append(TargetOrder.index(after: UInt64(routed.count), targetCount: 2))
            }
        }
        check(routed == [0, 1, 0, 1], "dropped and duplicate timer slots do not break alternation")
        check(late.skipped == 5, "late slots are accounted separately from targets")
        let even = (0..<50_000).map { TargetOrder.index(after: UInt64($0), targetCount: 2) }
        check(even.filter { $0 == 0 }.count == 25_000 && even.filter { $0 == 1 }.count == 25_000,
              "total target is shared equally, not doubled")
        check(TargetOrder.index(after: 0, targetCount: 2) == 0, "a restarted run starts at target one")
        print("PASS: \(checks) schedule checks. These are deterministic logic tests, not received-click performance measurements.")
    }
}
