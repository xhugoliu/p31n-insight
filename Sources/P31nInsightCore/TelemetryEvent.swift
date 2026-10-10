import Foundation

public struct TelemetryEvent: Equatable, Sendable {
    public let hostTime: Date
    public let hostTimeNs: Int64
    public let deviceTimeMs: UInt32
    public let sequence: UInt32
    public let row: UInt8
    public let col: UInt8
    public let pressed: Bool
    public let bootID: UInt32
    public let session: UInt32
    public var position: UInt8 { P31nGeometry.key(row: Int(row), col: Int(col))?.position ?? 255 }
    public init(hostTime: Date, hostTimeNs: Int64, deviceTimeMs: UInt32, sequence: UInt32,
                row: UInt8, col: UInt8, pressed: Bool, bootID: UInt32 = 0, session: UInt32 = 0) {
        self.hostTime = hostTime; self.hostTimeNs = hostTimeNs
        self.deviceTimeMs = deviceTimeMs; self.sequence = sequence
        self.row = row; self.col = col; self.pressed = pressed
        self.bootID = bootID; self.session = session
    }
}

public struct KeySummary: Equatable, Sendable {
    public let row: Int
    public let col: Int
    public let pressCount: Int
    public let heldMs: Int64
    public init(row: Int, col: Int, pressCount: Int, heldMs: Int64) {
        self.row = row; self.col = col; self.pressCount = pressCount; self.heldMs = heldMs
    }
}
