import Foundation
@preconcurrency import CoreBluetooth

@MainActor
public final class TelemetryCollector: NSObject, @preconcurrency CBCentralManagerDelegate,
                                       @preconcurrency CBPeripheralDelegate {
    private let serviceUUID = CBUUID(string: "A0310000-5B5A-4B4D-9A6E-5033314E0001")
    private let eventUUID = CBUUID(string: "A0310001-5B5A-4B4D-9A6E-5033314E0001")
    private let controlUUID = CBUUID(string: "A0310002-5B5A-4B4D-9A6E-5033314E0001")
    private let studioUUID = CBUUID(string: "00000000-0196-6107-C967-C5CFB1C2482A")
    private let configuration: AppConfiguration
    private let onEvent: @Sendable (TelemetryEvent) -> Void
    private let onStatus: @Sendable (CollectorStatus) -> Void
    private let onHealth: @Sendable (CollectorHealth) -> Void
    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var events: CBCharacteristic?
    private var control: CBCharacteristic?
    private var timer: Timer?
    private var running = false
    private var starting = false
    private var attempts: [UUID: Date] = [:]
    private var context: [UInt32] = []
    private var lastSequence: UInt32?
    private var health = CollectorHealth()

    public init(configuration: AppConfiguration = .p31n,
                onEvent: @escaping @Sendable (TelemetryEvent) -> Void,
                onStatus: @escaping @Sendable (CollectorStatus) -> Void,
                onHealth: @escaping @Sendable (CollectorHealth) -> Void = { _ in }) {
        self.configuration = configuration
        self.onEvent = onEvent; self.onStatus = onStatus; self.onHealth = onHealth
        super.init()
    }

    public func start() {
        guard !running else { return }
        running = true
        onStatus(.waiting(.initial))
        if central == nil { central = CBCentralManager(delegate: self, queue: .main) }
        else if central?.state == .poweredOn { findKeyboard() }
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    public func stop() {
        running = false
        timer?.invalidate(); timer = nil
        central?.stopScan()
        if let p = peripheral {
            if let control { p.writeValue(Data([0]), for: control, type: .withResponse) }
            if let events { p.setNotifyValue(false, for: events) }
            central?.cancelPeripheralConnection(p)
        }
        clearConnection()
        onStatus(.stopped)
    }

    public func reconnect() {
        guard running else { start(); return }
        attempts.removeAll()
        if let p = peripheral { central?.cancelPeripheralConnection(p) }
        else { findKeyboard() }
    }

    private func clearConnection() {
        peripheral = nil; events = nil; control = nil; starting = false
        context = []; lastSequence = nil
    }

    private func poll() {
        guard running else { return }
        if let p = peripheral, p.state == .connected, let control { p.readValue(for: control) }
        else if peripheral == nil { findKeyboard() }
    }

    private func findKeyboard() {
        guard running, let central, central.state == .poweredOn, peripheral == nil else { return }
        attempts = attempts.filter { Date().timeIntervalSince($0.value) < 10 }
        let devices = central.retrieveConnectedPeripherals(withServices: [serviceUUID, studioUUID, CBUUID(string: "1812")])
        if let p = devices.first(where: { matches($0.name) && attempts[$0.identifier] == nil }) { connect(p) }
        else { central.scanForPeripherals(withServices: nil, options: nil) }
    }

    private func matches(_ name: String?) -> Bool { (name ?? "").localizedCaseInsensitiveContains(configuration.deviceName) }

    private func connect(_ p: CBPeripheral) {
        guard running, peripheral == nil else { return }
        central?.stopScan(); peripheral = p; p.delegate = self
        attempts[p.identifier] = Date()
        central?.connect(p)
    }

    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard running else { return }
        switch central.state {
        case .poweredOn: findKeyboard()
        case .unauthorized: onStatus(.issue(.permissionDenied))
        case .poweredOff, .unsupported: onStatus(.issue(.bluetoothUnavailable))
        default: onStatus(.waiting(.initial))
        }
    }

    public func centralManager(_ central: CBCentralManager, didDiscover p: CBPeripheral,
                               advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = p.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
        if matches(name), attempts[p.identifier] == nil { connect(p) }
    }

    public func centralManager(_ central: CBCentralManager, didConnect p: CBPeripheral) {
        guard running, peripheral?.identifier == p.identifier else { return }
        p.discoverServices([serviceUUID])
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        guard peripheral?.identifier == p.identifier else { return }
        clearConnection()
        onStatus(.issue(.transport(error?.localizedDescription ?? "Could not connect P31n.")))
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        guard peripheral?.identifier == p.identifier else { return }
        clearConnection()
        if running { onStatus(.waiting(.disconnected)) }
    }

    public func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        guard running else { return }
        if let error { onStatus(.issue(.transport(error.localizedDescription))); return }
        guard let service = p.services?.first(where: { $0.uuid == serviceUUID }) else {
            onStatus(.issue(.serviceMissing)); return
        }
        p.discoverCharacteristics([eventUUID, controlUUID], for: service)
    }

    public func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard running else { return }
        if let error { onStatus(.issue(.transport(error.localizedDescription))); return }
        events = service.characteristics?.first { $0.uuid == eventUUID }
        control = service.characteristics?.first { $0.uuid == controlUUID }
        guard let events, control != nil else { onStatus(.issue(.serviceMissing)); return }
        p.setNotifyValue(true, for: events)
    }

    public func peripheral(_ p: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        guard running else { return }
        events = nil; control = nil
        onStatus(.waiting(.disconnected))
        p.discoverServices([serviceUUID])
    }

    public func peripheral(_ p: CBPeripheral, didUpdateNotificationStateFor c: CBCharacteristic, error: Error?) {
        guard running else { return }
        if let error { onStatus(.issue(.transport(error.localizedDescription))); return }
        if c.uuid == eventUUID, c.isNotifying { startSession() }
    }

    private func startSession() {
        guard running, !starting, let p = peripheral, let control else { return }
        starting = true
        context = []; lastSequence = nil; health = CollectorHealth(); onHealth(health)
        p.writeValue(Data([1]), for: control, type: .withResponse)
    }

    public func peripheral(_ p: CBPeripheral, didWriteValueFor c: CBCharacteristic, error: Error?) {
        guard running, c.uuid == controlUUID else { return }
        starting = false
        if let error { onStatus(.issue(.transport(error.localizedDescription))); return }
        onStatus(.connected(p.name ?? configuration.deviceName))
        p.readValue(for: c)
    }

    public func peripheral(_ p: CBPeripheral, didUpdateValueFor c: CBCharacteristic, error: Error?) {
        guard running else { return }
        if let error { onStatus(.issue(.transport(error.localizedDescription))); return }
        guard let data = c.value else { return }
        if c.uuid == eventUUID {
            guard let event = TelemetryPacket.parse([UInt8](data)) else {
                onStatus(.issue(.unsupportedTelemetry(length: data.count))); return
            }
            let newContext = [event.bootID, event.session]
            if newContext != context { context = newContext; lastSequence = nil }
            if let previous = lastSequence {
                let distance = event.sequence &- previous
                if distance == 0 || distance > UInt32.max / 2 {
                    health.duplicatePackets += 1; onHealth(health); return
                }
                if distance > 1 { health.missingPackets += UInt64(distance - 1) }
            } else if event.sequence > 0 { health.missingPackets += UInt64(event.sequence) }
            lastSequence = event.sequence
            onEvent(event); onHealth(health)
        } else if c.uuid == controlUUID, let status = FirmwareStatus(data: data) {
            health.firmwareDropped = status.dropped; health.firmwareReplayed = status.replayed
            onHealth(health)
            if !status.enabled && !starting && events?.isNotifying == true { startSession() }
        }
    }
}
