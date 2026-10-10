import Foundation

public enum TelemetryPacket {
    public static let reportSize = 20
    public static func parse(_ bytes: [UInt8], hostTime: Date = Date()) -> TelemetryEvent? {
        guard bytes.count == reportSize, bytes[0] == 1, bytes[1] < 31,
              bytes[2] <= 1, bytes[3] == 0 else { return nil }
        let key = P31nGeometry.keys[Int(bytes[1])]
        return TelemetryEvent(hostTime: hostTime,
                              hostTimeNs: Int64(hostTime.timeIntervalSince1970 * 1_000_000_000),
                              deviceTimeMs: readUInt32(bytes, 8), sequence: readUInt32(bytes, 4),
                              row: UInt8(key.row), col: UInt8(key.col), pressed: bytes[2] == 1,
                              bootID: readUInt32(bytes, 12), session: readUInt32(bytes, 16))
    }
    static func readUInt32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 |
            UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
    }
}

public struct FirmwareStatus: Equatable, Sendable {
    public let enabled: Bool
    public let bootID: UInt32
    public let session: UInt32
    public let captured: UInt32
    public let sent: UInt32
    public let dropped: UInt32
    public let replayed: UInt32
    public let nextSequence: UInt32
    public init?(data: Data) {
        let bytes = [UInt8](data)
        guard bytes.count == 32, bytes[0] == 1, bytes[1] <= 1 else { return nil }
        enabled = bytes[1] == 1
        bootID = TelemetryPacket.readUInt32(bytes, 4)
        session = TelemetryPacket.readUInt32(bytes, 8)
        captured = TelemetryPacket.readUInt32(bytes, 12)
        sent = TelemetryPacket.readUInt32(bytes, 16)
        dropped = TelemetryPacket.readUInt32(bytes, 20)
        replayed = TelemetryPacket.readUInt32(bytes, 24)
        nextSequence = TelemetryPacket.readUInt32(bytes, 28)
    }
}
