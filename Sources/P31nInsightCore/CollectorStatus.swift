import Foundation

public enum CollectorWaitingReason: Equatable, Sendable { case initial, disconnected }
public enum CollectorIssue: Equatable, Sendable {
    case bluetoothUnavailable
    case permissionDenied
    case serviceMissing
    case transport(String)
    case unsupportedTelemetry(length: Int)
    public var title: String {
        switch self {
        case .bluetoothUnavailable: "Bluetooth unavailable"
        case .permissionDenied: "Bluetooth permission required"
        case .serviceMissing: "Telemetry firmware required"
        case .transport: "Connection problem"
        case .unsupportedTelemetry: "Unsupported telemetry"
        }
    }
    public var detail: String {
        switch self {
        case .bluetoothUnavailable: "Turn on Bluetooth to connect P31n."
        case .permissionDenied: "Allow P31n Insight in System Settings → Privacy & Security → Bluetooth."
        case .serviceMissing: "Install P31n firmware with the telemetry module, then reconnect."
        case .transport(let detail): detail
        case .unsupportedTelemetry(let length): "Received an unsupported \(length)-byte packet. Update the app and telemetry firmware together."
        }
    }
}
public enum CollectorStatus: Equatable, Sendable {
    case stopped
    case waiting(CollectorWaitingReason)
    case connected(String)
    case issue(CollectorIssue)
    public var title: String {
        switch self {
        case .stopped: "Paused"
        case .waiting(.initial): "Waiting for keyboard"
        case .waiting(.disconnected): "Keyboard disconnected"
        case .connected(let name): name
        case .issue(let issue): issue.title
        }
    }
    public var detail: String? {
        switch self {
        case .stopped: "Physical key collection is paused."
        case .waiting(.initial): "Connect P31n over Bluetooth. Quit Telemetry Probe before recording here."
        case .waiting(.disconnected): "Reconnect P31n to resume logging automatically."
        case .connected: "Recording physical key events locally over Bluetooth."
        case .issue(let issue): issue.detail
        }
    }
    public var isConnected: Bool { if case .connected = self { true } else { false } }
    public var showsIssue: Bool { if case .issue = self { true } else { false } }
}

public struct CollectorHealth: Equatable, Sendable {
    public var missingPackets: UInt64 = 0
    public var duplicatePackets: UInt64 = 0
    public var firmwareDropped: UInt32 = 0
    public var firmwareReplayed: UInt32 = 0
    public init() {}
    public var hasLoss: Bool { missingPackets > 0 || firmwareDropped > 0 }
}
