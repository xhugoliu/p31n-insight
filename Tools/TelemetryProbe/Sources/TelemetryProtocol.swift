import Foundation

struct ProbePacket: Equatable {
    let position: UInt8
    let pressed: Bool
    let sequence: UInt32
    let deviceMs: UInt32
    let bootID: UInt32
    let session: UInt32

    init?(data: Data) {
        let bytes = [UInt8](data)
        guard bytes.count == 20, bytes[0] == 1, bytes[1] < 31,
              bytes[2] < 2, bytes[3] == 0 else { return nil }
        position = bytes[1]
        pressed = bytes[2] == 1
        sequence = little32(bytes, 4)
        deviceMs = little32(bytes, 8)
        bootID = little32(bytes, 12)
        session = little32(bytes, 16)
    }
}

struct FirmwareStatus {
    let enabled: Bool
    let bootID: UInt32
    let session: UInt32
    let captured: UInt32
    let sent: UInt32
    let dropped: UInt32
    let replayed: UInt32
    let nextSequence: UInt32

    init?(data: Data) {
        let b = [UInt8](data)
        guard b.count == 32, b[0] == 1, b[1] < 2 else { return nil }
        enabled = b[1] == 1
        bootID = little32(b, 4)
        session = little32(b, 8)
        captured = little32(b, 12)
        sent = little32(b, 16)
        dropped = little32(b, 20)
        replayed = little32(b, 24)
        nextSequence = little32(b, 28)
    }
}

private func little32(_ b: [UInt8], _ offset: Int) -> UInt32 {
    UInt32(b[offset]) | UInt32(b[offset + 1]) << 8 |
        UInt32(b[offset + 2]) << 16 | UInt32(b[offset + 3]) << 24
}

struct KeyCounter {
    var down = 0
    var up = 0
    var heldMs: UInt64 = 0
}

struct ProbeTracker {
    private(set) var keys: [UInt8: KeyCounter] = [:]
    private(set) var active: [UInt8: UInt32] = [:]
    private(set) var missing: UInt64 = 0
    private(set) var duplicates = 0
    private(set) var incomplete = 0
    private(set) var bootID: UInt32?
    private(set) var session: UInt32?
    private(set) var lastSequence: UInt32?

    var downs: Int { keys.values.reduce(0) { $0 + $1.down } }
    var ups: Int { keys.values.reduce(0) { $0 + $1.up } }

    mutating func invalidateHeldKeys() {
        incomplete += active.count
        active.removeAll()
    }

    mutating func apply(_ p: ProbePacket) -> (accepted: Bool, message: String) {
        if bootID != p.bootID || session != p.session {
            self = ProbeTracker()
            bootID = p.bootID
            session = p.session
        }
        if let previous = lastSequence {
            let distance = p.sequence &- previous
            if distance == 0 || distance > UInt32.max / 2 {
                duplicates += 1
                return (false, "忽略重复或过期报文 seq=\(p.sequence)")
            }
            if distance > 1 {
                missing += UInt64(distance - 1)
                invalidateHeldKeys()
            }
        } else if p.sequence > 0 {
            missing += UInt64(p.sequence)
        }
        lastSequence = p.sequence
        var counter = keys[p.position, default: KeyCounter()]
        var suffix = ""
        if p.pressed {
            counter.down += 1
            if active[p.position] != nil {
                incomplete += 1
                suffix = " [缺少上一次 UP]"
            }
            active[p.position] = p.deviceMs
        } else {
            counter.up += 1
            if let start = active.removeValue(forKey: p.position) {
                let duration = p.deviceMs &- start
                if duration <= 3_600_000 {
                    counter.heldMs += UInt64(duration)
                    suffix = " held_ms=\(duration)"
                } else {
                    incomplete += 1
                    suffix = " [时长异常，未累计]"
                }
            } else {
                incomplete += 1
                suffix = " [缺少 DOWN，未累计时长]"
            }
        }
        keys[p.position] = counter
        return (true, "seq=\(p.sequence) pos=\(p.position)[\(physicalLabel(p.position))] \(p.pressed ? "DOWN" : "UP") device_ms=\(p.deviceMs)\(suffix)")
    }

    func summary() -> String {
        var lines = ["P31n Telemetry Probe", "boot=\(bootID.map(String.init) ?? "-") session=\(session.map(String.init) ?? "-")",
                     "DOWN=\(downs) UP=\(ups) 按住=\(active.count) 缺失报文=\(missing) 重复报文=\(duplicates) 不完整配对=\(incomplete)"]
        for position in keys.keys.sorted() {
            let k = keys[position]!
            lines.append("pos=\(position)[\(physicalLabel(position))] down=\(k.down) up=\(k.up) held_ms=\(k.heldMs)")
        }
        return lines.joined(separator: "\n")
    }
}

func physicalLabel(_ position: UInt8) -> String {
    let labels = ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P",
                  "A", "S", "D", "F", "G", "H", "J", "K", "L", ";",
                  "Z", "X", "C", "V", "B", "中央", "N", "M", ",", ".", "/"]
    return Int(position) < labels.count ? labels[Int(position)] : "?"
}

func runProtocolChecks() {
    func packet(_ pos: UInt8, _ pressed: Bool, _ seq: UInt32, _ time: UInt32,
                boot: UInt32 = 12, session: UInt32 = 3) -> ProbePacket {
        var bytes: [UInt8] = [1, pos, pressed ? 1 : 0, 0]
        for value in [seq, time, boot, session] {
            bytes += (0..<4).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) }
        }
        return ProbePacket(data: Data(bytes))!
    }
    precondition(ProbePacket(data: Data(repeating: 0, count: 20)) == nil)
    precondition(ProbePacket(data: Data(repeating: 1, count: 19)) == nil)
    let p = packet(24, true, 0x12345678, 0x87654321)
    precondition(p.sequence == 0x12345678 && p.deviceMs == 0x87654321 && p.bootID == 12 && p.session == 3)
    var t = ProbeTracker()
    _ = t.apply(packet(24, true, 0, 100))
    _ = t.apply(packet(24, false, 1, 400))
    precondition(t.downs == 1 && t.ups == 1 && t.keys[24]?.heldMs == 300)
    precondition(!t.apply(packet(24, false, 1, 400)).accepted && t.duplicates == 1)
    _ = t.apply(packet(26, true, 2, 500))
    _ = t.apply(packet(26, false, 4, 700))
    precondition(t.missing == 1 && t.keys[26]?.heldMs == 0 && t.active.isEmpty)
    _ = t.apply(packet(24, true, 0, UInt32.max - 10, session: 4))
    _ = t.apply(packet(24, false, 1, 20, session: 4))
    precondition(t.keys[24]?.heldMs == 31 && t.downs == 1 && t.missing == 0)
    _ = t.apply(packet(24, true, 2, 100, session: 4))
    t.invalidateHeldKeys()
    _ = t.apply(packet(24, false, 3, 1000, session: 4))
    precondition(t.keys[24]?.heldMs == 31)
    _ = t.apply(packet(26, true, 0, 10, boot: 13, session: 1))
    precondition(t.downs == 1 && t.ups == 0 && t.bootID == 13)
    print("PASS: packet validation, pairing, duplicates, loss, timer wrap, reconnect, and reboot")
}
