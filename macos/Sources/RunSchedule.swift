import Foundation

/// A monotonic, single-flight schedule. Late slots are dropped, never replayed in a burst.
struct RunSchedule {
    let start: UInt64
    let end: UInt64
    let interval: UInt64
    private(set) var nextSlot: UInt64 = 0
    private(set) var skipped: UInt64 = 0

    init(cps: Int, seconds: Int, start: UInt64) {
        precondition((1...5000).contains(cps) && (1...3600).contains(seconds))
        self.start = start
        self.interval = 1_000_000_000 / UInt64(cps)
        self.end = start + UInt64(seconds) * 1_000_000_000
    }

    mutating func takeSlot(at now: UInt64) -> Bool {
        guard now >= start && now < end else { return false }
        let slot = (now - start) / interval
        guard slot >= nextSlot else { return false }
        skipped += slot - nextSlot
        nextSlot = slot + 1
        return true
    }
}
