import Foundation

enum ClickLimits {
    static let maxCPS = 20_000
    static let defaultCPS = 1_000
    static let defaultMode: ClickMode = .fast
    static let maxBatch = 32
}

enum ClickMode: String, Codable, CaseIterable, Identifiable {
    case fast, steady
    var id: String { rawValue }
    var title: String { self == .fast ? "고속" : "기존 방식" }
    var batchLimit: Int { self == .fast ? ClickLimits.maxBatch : 1 }
    func timerInterval(cps: Int) -> UInt64 {
        let interval = 1_000_000_000 / UInt64(cps)
        return self == .fast ? max(interval, 500_000) : interval
    }
}

/// Monotonic rate budget. Only slots already due may be reserved; old backlog is bounded.
struct RunSchedule {
    let start: UInt64
    let end: UInt64
    let interval: UInt64
    let cps: UInt64
    private(set) var nextSlot: UInt64 = 0
    private(set) var skipped: UInt64 = 0

    init(cps: Int, seconds: Int, start: UInt64) {
        precondition((1...ClickLimits.maxCPS).contains(cps) && (1...3600).contains(seconds))
        self.start = start
        self.cps = UInt64(cps)
        self.interval = 1_000_000_000 / UInt64(cps)
        self.end = start + UInt64(seconds) * 1_000_000_000
    }

    mutating func takeSlot(at now: UInt64) -> Bool {
        takeBatch(at: now, limit: 1) == 1
    }

    mutating func takeBatch(at now: UInt64, limit: Int) -> Int {
        precondition((1...ClickLimits.maxBatch).contains(limit))
        guard now >= start && now < end else { return 0 }
        // Integer rate arithmetic avoids accumulating a rounded interval error.
        // Bounds (20,000 CPS for 3,600 s) keep this multiplication within UInt64.
        let due = (now - start) * cps / 1_000_000_000 + 1
        guard due > nextSlot else { return 0 }
        let available = due - nextSlot
        let count = min(available, UInt64(limit))
        skipped += available - count
        nextSlot = due
        return Int(count)
    }
}

/// Advance by clicks actually posted so delayed callbacks cannot starve a target.
enum TargetOrder {
    static func index(after postedPairs: UInt64, targetCount: Int) -> Int {
        precondition((1...2).contains(targetCount))
        return Int(postedPairs % UInt64(targetCount))
    }
}
