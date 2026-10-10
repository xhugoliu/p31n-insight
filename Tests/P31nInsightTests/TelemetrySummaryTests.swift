import Foundation
import Testing
@testable import P31nInsightCore

struct TelemetrySummaryTests {
    @Test func liveSummaryTrackerTracksActiveKeysAndTotals() {
        var tracker = LiveSummaryTracker(layout: .p31n)

        tracker.apply(event(deviceTimeMs: 50, row: 0, col: 0, pressed: true))
        #expect(tracker.snapshot.pressCount == 1)
        #expect(tracker.snapshot.heldMs == 0)
        #expect(tracker.activeKeys.contains(LiveSummaryTracker.keyID(row: 0, col: 0)))

        tracker.apply(event(deviceTimeMs: 80, row: 0, col: 0, pressed: false))
        #expect(tracker.snapshot.pressCount == 1)
        #expect(tracker.snapshot.heldMs == 30)
        #expect(!tracker.activeKeys.contains(LiveSummaryTracker.keyID(row: 0, col: 0)))
    }

    @Test func summaryCalculatorBuildsSnapshotForWholeRange() {
        let snapshot = SummaryCalculator.snapshot(
            from: [
                event(deviceTimeMs: 100, row: 1, col: 1, pressed: true),
                event(deviceTimeMs: 180, row: 1, col: 1, pressed: false),
                event(deviceTimeMs: 200, row: 2, col: 4, pressed: true),
                event(deviceTimeMs: 260, row: 2, col: 4, pressed: false),
            ],
            layout: .p31n
        )

        let key11 = snapshot.keySummaries.first { $0.row == 1 && $0.col == 1 }
        let key24 = snapshot.keySummaries.first { $0.row == 2 && $0.col == 4 }

        #expect(snapshot.pressCount == 2)
        #expect(snapshot.heldMs == 140)
        #expect(key11?.pressCount == 1)
        #expect(key11?.heldMs == 80)
        #expect(key24?.pressCount == 1)
        #expect(key24?.heldMs == 60)
    }

    @Test func dayScopedTrackerRollsToNewDay() throws {
        let calendar = Calendar(identifier: .gregorian)
        let day1 = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let day2 = try #require(calendar.date(byAdding: .day, value: 1, to: day1))
        var tracker = DayScopedLiveSummaryTracker(layout: .p31n, dayStart: day1, calendar: calendar)

        tracker.apply(event(on: day1, secondsIntoDay: 10, deviceTimeMs: 100, row: 0, col: 0, pressed: true))
        tracker.apply(event(on: day1, secondsIntoDay: 11, deviceTimeMs: 160, row: 0, col: 0, pressed: false))
        #expect(tracker.snapshot.pressCount == 1)
        #expect(tracker.snapshot.heldMs == 60)

        let didRollDay = tracker.apply(event(on: day2, secondsIntoDay: 1, deviceTimeMs: 200, row: 1, col: 1, pressed: true))
        tracker.apply(event(on: day2, secondsIntoDay: 2, deviceTimeMs: 260, row: 1, col: 1, pressed: false))

        #expect(didRollDay)
        #expect(tracker.dayStart == day2)
        #expect(tracker.snapshot.pressCount == 1)
        #expect(tracker.snapshot.heldMs == 60)
        #expect(tracker.snapshot.keySummaries.first { $0.row == 0 && $0.col == 0 }?.pressCount == 0)
        #expect(tracker.snapshot.keySummaries.first { $0.row == 1 && $0.col == 1 }?.pressCount == 1)
    }

    @Test func ignoresImplausibleHoldAfterDeviceTimerRestart() {
        let snapshot = SummaryCalculator.snapshot(
            from: [
                event(deviceTimeMs: 60_000, row: 2, col: 2, pressed: true),
                event(deviceTimeMs: 10_000, row: 2, col: 2, pressed: false),
            ],
            layout: .p31n
        )

        #expect(snapshot.pressCount == 1)
        #expect(snapshot.heldMs == 0)
        #expect(snapshot.keySummaries.first { $0.row == 2 && $0.col == 2 }?.heldMs == 0)
    }

    private func event(deviceTimeMs: UInt32, row: UInt8, col: UInt8, pressed: Bool) -> TelemetryEvent {
        TelemetryEvent(
            hostTime: Date(timeIntervalSince1970: 0),
            hostTimeNs: Int64(deviceTimeMs) * 1_000_000,
            deviceTimeMs: deviceTimeMs,
            sequence: deviceTimeMs,
            row: row,
            col: col,
            pressed: pressed
        )
    }

    private func event(
        on dayStart: Date,
        secondsIntoDay: TimeInterval,
        deviceTimeMs: UInt32,
        row: UInt8,
        col: UInt8,
        pressed: Bool
    ) -> TelemetryEvent {
        let hostTime = dayStart.addingTimeInterval(secondsIntoDay)
        return TelemetryEvent(
            hostTime: hostTime,
            hostTimeNs: Int64(hostTime.timeIntervalSince1970 * 1_000_000_000),
            deviceTimeMs: deviceTimeMs,
            sequence: deviceTimeMs,
            row: row,
            col: col,
            pressed: pressed
        )
    }
}
