import Foundation

public struct AppConfiguration: Equatable, Sendable {
    public let deviceName: String
    public let layout: KeyboardLayout
    public static let p31n = AppConfiguration(deviceName: "P31n", layout: .p31n)
}

public enum HandGroup: String, Sendable { case left, right, center }

public struct PhysicalKey: Identifiable, Equatable, Sendable {
    public let position: UInt8
    public let row: Int
    public let col: Int
    public let label: String
    public let x: Double
    public let y: Double
    public let width: Double
    public let hand: HandGroup
    public var id: UInt8 { position }
}

public enum P31nGeometry {
    public static let width = 11.5
    public static let keys: [PhysicalKey] = {
        let labels = ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P",
                      "A", "S", "D", "F", "G", "H", "J", "K", "L", ";",
                      "Z", "X", "C", "V", "B", "Fn", "N", "M", ",", ".", "/"]
        return (0..<31).map { position in
            let row = position < 20 ? position / 10 : 2
            let index = position < 20 ? position % 10 : position - 20
            let center = position == 25
            let col = row < 2 && index >= 5 ? index + 1 : index
            let hand: HandGroup = center ? .center : (col < 5 ? .left : .right)
            return PhysicalKey(position: UInt8(position), row: row, col: col,
                               label: labels[position], x: Double(col) + (hand == .right ? 0.5 : 0),
                               y: Double(row), width: center ? 1.5 : 1, hand: hand)
        }
    }()
    public static func key(row: Int, col: Int) -> PhysicalKey? {
        keys.first { $0.row == row && $0.col == col }
    }
}
