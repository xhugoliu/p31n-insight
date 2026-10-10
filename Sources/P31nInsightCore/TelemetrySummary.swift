import Foundation

public struct KeyboardLayout: Equatable, Sendable {
    public let rows: Int
    public let columns: Int

    public init(rows: Int, columns: Int) {
        self.rows = rows
        self.columns = columns
    }

    public static let p31n = KeyboardLayout(rows: 3, columns: 11)

    public func contains(row: Int, col: Int) -> Bool {
        guard row >= 0, row < rows, col >= 0, col < columns else { return false }
        return self != .p31n || P31nGeometry.key(row: row, col: col) != nil
    }
}

public struct SummarySnapshot: Equatable, Sendable {
    public var keySummaries: [KeySummary]
    public var pressCount: Int
    public var heldMs: Int64

    public init(keySummaries: [KeySummary], pressCount: Int, heldMs: Int64) {
        self.keySummaries = keySummaries
        self.pressCount = pressCount
        self.heldMs = heldMs
    }

    public static func empty(layout: KeyboardLayout) -> SummarySnapshot {
        var keySummaries: [KeySummary] = []
        for row in 0..<layout.rows {
            for col in 0..<layout.columns {
                guard layout.contains(row: row, col: col) else { continue }
                keySummaries.append(KeySummary(row: row, col: col, pressCount: 0, heldMs: 0))
            }
        }
        return SummarySnapshot(keySummaries: keySummaries, pressCount: 0, heldMs: 0)
    }
}

public struct DailySummary: Equatable, Sendable {
    public let dayStart: Date
    public let pressCount: Int
    public let heldMs: Int64

    public init(dayStart: Date, pressCount: Int, heldMs: Int64) {
        self.dayStart = dayStart
        self.pressCount = pressCount
        self.heldMs = heldMs
    }
}

public struct DashboardSnapshot: Equatable, Sendable {
    public let today: SummarySnapshot
    public let range: SummarySnapshot
    public let dailySummaries: [DailySummary]

    public init(today: SummarySnapshot, range: SummarySnapshot, dailySummaries: [DailySummary]) {
        self.today = today
        self.range = range
        self.dailySummaries = dailySummaries
    }
}

public struct LiveSummaryTracker: Sendable {
    public private(set) var snapshot: SummarySnapshot
    public private(set) var activeKeys: Set<String> = []

    private let layout: KeyboardLayout
    private var activeDeviceTimes: [String: UInt32] = [:]
    private var context: [UInt32] = []
    private var lastSequence: UInt32?

    public init(layout: KeyboardLayout, snapshot: SummarySnapshot? = nil) {
        self.layout = layout
        self.snapshot = snapshot ?? SummarySnapshot.empty(layout: layout)
    }

    public mutating func rebase(snapshot: SummarySnapshot) {
        self.snapshot = snapshot
    }

    public mutating func reset(snapshot: SummarySnapshot? = nil) {
        self.snapshot = snapshot ?? SummarySnapshot.empty(layout: layout)
        activeKeys.removeAll()
        activeDeviceTimes.removeAll()
        context = []
        lastSequence = nil
    }

    public mutating func apply(_ event: TelemetryEvent) {
        let row = Int(event.row)
        let col = Int(event.col)
        guard layout.contains(row: row, col: col) else {
            return
        }

        let newContext = [event.bootID, event.session]
        if context != newContext || (event.session != 0 && lastSequence.map { event.sequence != $0 &+ 1 } == true) {
            activeKeys.removeAll()
            activeDeviceTimes.removeAll()
        }
        context = newContext
        lastSequence = event.sequence

        let key = Self.keyID(row: row, col: col)
        if event.pressed {
            activeKeys.insert(key)
            guard activeDeviceTimes[key] == nil else {
                return
            }

            activeDeviceTimes[key] = event.deviceTimeMs
            snapshot.pressCount += 1
            updateKey(row: row, col: col) { summary in
                KeySummary(
                    row: row,
                    col: col,
                    pressCount: summary.pressCount + 1,
                    heldMs: summary.heldMs
                )
            }
            return
        }

        activeKeys.remove(key)
        guard let startedAt = activeDeviceTimes.removeValue(forKey: key) else {
            return
        }

        guard let elapsedMs = deviceElapsedMs(from: startedAt, to: event.deviceTimeMs) else {
            return
        }

        let heldMs = Int64(elapsedMs)
        snapshot.heldMs += heldMs
        updateKey(row: row, col: col) { summary in
            KeySummary(
                row: row,
                col: col,
                pressCount: summary.pressCount,
                heldMs: summary.heldMs + heldMs
            )
        }
    }

    public static func keyID(row: Int, col: Int) -> String {
        "\(row),\(col)"
    }

    private mutating func updateKey(row: Int, col: Int, transform: (KeySummary) -> KeySummary) {
        guard let index = snapshot.keySummaries.firstIndex(where: { $0.row == row && $0.col == col }) else {
            return
        }
        snapshot.keySummaries[index] = transform(snapshot.keySummaries[index])
    }
}

public struct DayScopedLiveSummaryTracker: Sendable {
    public private(set) var dayStart: Date

    private var tracker: LiveSummaryTracker
    private let calendar: Calendar

    public init(
        layout: KeyboardLayout,
        dayStart: Date,
        calendar: Calendar = .current,
        snapshot: SummarySnapshot? = nil
    ) {
        self.calendar = calendar
        self.dayStart = calendar.startOfDay(for: dayStart)
        tracker = LiveSummaryTracker(layout: layout, snapshot: snapshot)
    }

    public var snapshot: SummarySnapshot {
        tracker.snapshot
    }

    public var activeKeys: Set<String> {
        tracker.activeKeys
    }

    public mutating func rebase(dayStart: Date, snapshot: SummarySnapshot) {
        reset(dayStart: dayStart, snapshot: snapshot)
    }

    public mutating func reset(dayStart: Date, snapshot: SummarySnapshot? = nil) {
        self.dayStart = calendar.startOfDay(for: dayStart)
        tracker.reset(snapshot: snapshot)
    }

    @discardableResult
    public mutating func apply(_ event: TelemetryEvent) -> Bool {
        let eventDayStart = calendar.startOfDay(for: event.hostTime)
        if eventDayStart < dayStart {
            return false
        }

        var didRollDay = false
        if eventDayStart > dayStart {
            reset(dayStart: eventDayStart)
            didRollDay = true
        }

        tracker.apply(event)
        return didRollDay
    }
}

public enum SummaryCalculator {
    public static func snapshot(from events: [TelemetryEvent], layout: KeyboardLayout) -> SummarySnapshot {
        var tracker = LiveSummaryTracker(layout: layout)
        for event in events {
            tracker.apply(event)
        }
        return tracker.snapshot
    }
}

func deviceElapsedMs(from start: UInt32, to end: UInt32) -> UInt32? {
    let elapsed: UInt32
    if end >= start {
        elapsed = end - start
    } else {
        elapsed = (UInt32.max - start) + end + 1
    }

    // Very large single-key holds usually mean the keyboard rebooted and its
    // device timer restarted, not that a key was physically held for hours.
    guard elapsed <= maximumCredibleKeyHoldMs else {
        return nil
    }

    return elapsed
}

private let maximumCredibleKeyHoldMs: UInt32 = 12 * 60 * 60 * 1_000
