import Foundation
import Testing
@testable import P31nInsightCore

private func wirePacket(position: UInt8 = 25, pressed: UInt8 = 1,
                        seq: UInt32 = 3, ms: UInt32 = 100, boot: UInt32 = 4, session: UInt32 = 1) -> [UInt8] {
    var bytes: [UInt8] = [1, position, pressed, 0]
    for value in [seq, ms, boot, session] {
        bytes += (0..<4).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) }
    }
    return bytes
}

@Test func mapsAll31PhysicalKeysIncludingTheWideCenter() throws {
    #expect(P31nGeometry.keys.count == 31)
    #expect(SummarySnapshot.empty(layout: .p31n).keySummaries.count == 31)
    let center = P31nGeometry.keys[25]
    #expect(center.row == 2 && center.col == 5 && center.hand == .center && center.width == 1.5)
    #expect(P31nGeometry.keys[26].x == center.x + center.width)
    #expect(P31nGeometry.keys.filter { $0.hand == .left }.count == 15)
    #expect(P31nGeometry.keys.filter { $0.hand == .right }.count == 15)
    #expect(P31nGeometry.keys.last!.x + 1 == 11.5)
    #expect(!KeyboardLayout.p31n.contains(row: 0, col: 5))
    #expect(!KeyboardLayout.p31n.contains(row: 1, col: 5))
    for key in P31nGeometry.keys {
        let event = try #require(TelemetryPacket.parse(wirePacket(position: key.position)))
        #expect(event.position == key.position && Int(event.row) == key.row && Int(event.col) == key.col)
    }
}

@Test func decodesLittleEndianDeviceTimeBootAndSession() throws {
    let time = Date(timeIntervalSince1970: 123)
    let event = try #require(TelemetryPacket.parse(wirePacket(seq: 0x12345678, ms: 0x87654321, boot: 0xf1234567), hostTime: time))
    #expect(event.sequence == 0x12345678 && event.deviceTimeMs == 0x87654321)
    #expect(event.bootID == 0xf1234567 && event.session == 1)
    #expect(event.hostTime == time && event.hostTimeNs == 123_000_000_000)
    #expect(TelemetryPacket.parse(wirePacket(position: 31)) == nil)
    #expect(TelemetryPacket.parse(wirePacket(pressed: 2)) == nil)
    #expect(TelemetryPacket.parse(Array(wirePacket().dropLast())) == nil)
}

@Test func dropsHeldDurationAcrossMissingPacketsAndNewSessions() throws {
    var tracker = LiveSummaryTracker(layout: .p31n)
    tracker.apply(try #require(TelemetryPacket.parse(wirePacket(seq: 0, ms: 100))))
    tracker.apply(try #require(TelemetryPacket.parse(wirePacket(pressed: 0, seq: 2, ms: 1000))))
    #expect(tracker.snapshot.heldMs == 0)
    tracker.apply(try #require(TelemetryPacket.parse(wirePacket(seq: 3, ms: 2000))))
    tracker.apply(try #require(TelemetryPacket.parse(wirePacket(pressed: 0, seq: 0, ms: 3000, session: 2))))
    #expect(tracker.snapshot.heldMs == 0 && tracker.activeKeys.isEmpty)
    tracker.apply(try #require(TelemetryPacket.parse(wirePacket(seq: 1, ms: UInt32.max - 10, session: 2))))
    tracker.apply(try #require(TelemetryPacket.parse(wirePacket(pressed: 0, seq: 2, ms: 20, session: 2))))
    #expect(tracker.snapshot.heldMs == 31)
}

@Test func persistsBootIdentifiersWithoutSigned32BitTruncation() throws {
    let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: path) }
    let db = try SQLiteDatabase(url: path)
    try db.insert(try #require(TelemetryPacket.parse(wirePacket(seq: 0, ms: 100, boot: 0xf1234567))))
    try db.insert(try #require(TelemetryPacket.parse(wirePacket(pressed: 0, seq: 1, ms: 125, boot: 0xf1234567))))
    let snapshot = try db.summarySnapshot(since: Date(timeIntervalSince1970: 0))
    #expect(snapshot.pressCount == 1 && snapshot.heldMs == 25)
    #expect(snapshot.keySummaries.first { $0.row == 2 && $0.col == 5 }?.heldMs == 25)
}

@Test func reportsBluetoothPermissionAndFirmwareIssuesClearly() {
    #expect(CollectorStatus.issue(.permissionDenied).detail?.contains("Privacy") == true)
    #expect(CollectorStatus.issue(.serviceMissing).showsIssue)
    #expect(CollectorStatus.connected("P31n").isConnected)
    #expect(!CollectorStatus.waiting(.disconnected).isConnected)
}

@Test func replaysTheFourVerifiedHardwareSessions() throws {
    struct Session: Decodable { let name: String; let events: [Event] }
    struct Event: Decodable {
        let position: UInt8; let pressed: Bool; let sequence: UInt32
        let device_ms: UInt32; let boot: UInt32; let session: UInt32
    }
    let url = try #require(Bundle.module.url(forResource: "verified-sessions", withExtension: "json", subdirectory: "Fixtures"))
    let sessions = try JSONDecoder().decode([Session].self, from: Data(contentsOf: url))
    let expected: [String: (Int, Int64)] = ["a20": (20, 2258), "bn20": (40, 5056), "qTapHold": (2, 2935), "reconnectA5": (5, 490)]
    for session in sessions {
        var tracker = LiveSummaryTracker(layout: .p31n)
        for event in session.events {
            tracker.apply(try #require(TelemetryPacket.parse(wirePacket(position: event.position,
                pressed: event.pressed ? 1 : 0, seq: event.sequence, ms: event.device_ms,
                boot: event.boot, session: event.session))))
        }
        #expect(tracker.snapshot.pressCount == expected[session.name]!.0)
        #expect(tracker.snapshot.heldMs == expected[session.name]!.1)
        #expect(tracker.activeKeys.isEmpty)
    }
}
