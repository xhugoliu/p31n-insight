import AppKit
@preconcurrency import CoreBluetooth

private let probeService = CBUUID(string: "A0310000-5B5A-4B4D-9A6E-5033314E0001")
private let eventUUID = CBUUID(string: "A0310001-5B5A-4B4D-9A6E-5033314E0001")
private let controlUUID = CBUUID(string: "A0310002-5B5A-4B4D-9A6E-5033314E0001")
private let studioService = CBUUID(string: "00000000-0196-6107-C967-C5CFB1C2482A")

@MainActor
final class ProbeApp: NSObject, NSApplicationDelegate,
                      @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralDelegate {
    private var window: NSWindow!
    private let connectionLabel = NSTextField(labelWithString: "正在初始化蓝牙…")
    private let counterLabel = NSTextField(labelWithString: "尚未接收事件")
    private let logView = NSTextView()
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var eventCharacteristic: CBCharacteristic?
    private var controlCharacteristic: CBCharacteristic?
    private var tracker = ProbeTracker()
    private var firmwareStatus: FirmwareStatus?
    private var timer: Timer?
    private var paused = false
    private var starting = false
    private var tried = Set<UUID>()
    private var logFile: FileHandle?
    private var csvFile: FileHandle?
    private var logDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
    private var pauseButton: NSButton!
    private var resetButton: NSButton!

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildWindow()
        openLogs()
        log("物理位置标签来自当前默认层。计时使用固件时间；本程序不监听系统键盘输入。")
        central = CBCentralManager(delegate: self, queue: .main)
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        if let p = peripheral {
            if let control = controlCharacteristic {
                p.writeValue(Data([0]), for: control, type: .withResponse)
            }
            central.cancelPeripheralConnection(p)
        }
        log(tracker.summary())
        try? logFile?.close()
        try? csvFile?.close()
    }

    private func buildWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 680),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "P31n Telemetry Probe"
        window.center()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor, constant: -18)
        ])
        connectionLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        connectionLabel.lineBreakMode = .byWordWrapping
        counterLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        counterLabel.maximumNumberOfLines = 2
        stack.addArrangedSubview(connectionLabel)
        stack.addArrangedSubview(counterLabel)
        let actions = NSStackView()
        actions.orientation = .horizontal
        actions.spacing = 10
        actions.addArrangedSubview(NSButton(title: "重新连接", target: self, action: #selector(reconnect)))
        resetButton = NSButton(title: "重新计数", target: self, action: #selector(resetCapture))
        pauseButton = NSButton(title: "暂停", target: self, action: #selector(togglePause))
        actions.addArrangedSubview(resetButton)
        actions.addArrangedSubview(pauseButton)
        actions.addArrangedSubview(NSButton(title: "复制摘要", target: self, action: #selector(copySummary)))
        actions.addArrangedSubview(NSButton(title: "打开日志", target: self, action: #selector(showLogs)))
        resetButton.isEnabled = false
        pauseButton.isEnabled = false
        stack.addArrangedSubview(actions)
        let note = NSTextField(labelWithString: "测试时拔掉 USB 并退出 ZMK Studio。先短按 A 20 次，再测试 B＋N 并击。重新计数会开启新的独立采集会话。")
        note.font = .systemFont(ofSize: 12)
        note.maximumNumberOfLines = 2
        stack.addArrangedSubview(note)
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        logView.isEditable = false
        logView.isSelectable = true
        logView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        logView.textContainerInset = NSSize(width: 8, height: 8)
        logView.autoresizingMask = [.width]
        logView.isVerticallyResizable = true
        logView.isHorizontallyResizable = false
        logView.textContainer?.widthTracksTextView = true
        scroll.documentView = logView
        stack.addArrangedSubview(scroll)
        scroll.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 300).isActive = true
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openLogs() {
        if let path = Bundle.main.object(forInfoDictionaryKey: "ProbeLogDirectory") as? String {
            logDirectory = URL(fileURLWithPath: path, isDirectory: true)
        }
        do {
            try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
            let name = formatter.string(from: Date())
            let textURL = logDirectory.appendingPathComponent("probe-\(name).log")
            let csvURL = logDirectory.appendingPathComponent("events-\(name).csv")
            FileManager.default.createFile(atPath: textURL.path, contents: Data())
            FileManager.default.createFile(atPath: csvURL.path, contents: Data("host_time,boot_id,session,sequence,position,pressed,device_ms\n".utf8))
            logFile = try FileHandle(forWritingTo: textURL)
            csvFile = try FileHandle(forWritingTo: csvURL)
            try csvFile?.seekToEnd()
            log("日志：\(textURL.path)")
        } catch { log("无法保存日志：\(error.localizedDescription)") }
    }

    private func log(_ message: String) {
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
        logView.textStorage?.append(NSAttributedString(string: line, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.textColor
        ]))
        if let storage = logView.textStorage, storage.length > 180_000 {
            storage.deleteCharacters(in: NSRange(location: 0, length: 60_000))
        }
        logView.scrollToEndOfDocument(nil)
        try? logFile?.write(contentsOf: Data(line.utf8))
    }

    private func refreshCounters() {
        let firmware = firmwareStatus.map { "固件丢弃=\($0.dropped) 已去重=\($0.replayed)" } ?? "固件状态待读取"
        counterLabel.stringValue = "DOWN=\(tracker.downs) UP=\(tracker.ups) 按住=\(tracker.active.count) 缺失=\(tracker.missing) 重复=\(tracker.duplicates) 配对异常=\(tracker.incomplete)\n\(firmware)"
    }

    private func poll() {
        if let p = peripheral, p.state == .connected, let c = controlCharacteristic {
            p.readValue(for: c)
        } else if peripheral == nil, central.state == .poweredOn {
            findKeyboard()
        }
    }

    private func findKeyboard() {
        guard central.state == .poweredOn, peripheral == nil else { return }
        connectionLabel.stringValue = "寻找已通过蓝牙连接的 P31n…"
        let connected = central.retrieveConnectedPeripherals(withServices: [probeService, studioService, CBUUID(string: "1812")])
        if let p = connected.first(where: { ($0.name ?? "").localizedCaseInsensitiveContains("p31n") && !tried.contains($0.identifier) }) {
            connect(p)
        } else {
            central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        }
    }

    private func connect(_ p: CBPeripheral) {
        guard peripheral == nil else { return }
        central.stopScan()
        peripheral = p
        p.delegate = self
        tried.insert(p.identifier)
        connectionLabel.stringValue = "正在连接 \(p.name ?? "P31n")…"
        central.connect(p)
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn: findKeyboard()
        case .unauthorized: connectionLabel.stringValue = "请在系统设置 → 隐私与安全性 → 蓝牙中允许 P31n Telemetry Probe。"
        case .poweredOff: connectionLabel.stringValue = "Mac 蓝牙已关闭。"
        default: connectionLabel.stringValue = "蓝牙状态：\(central.state.rawValue)"
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover p: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = p.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? ""
        if name.localizedCaseInsensitiveContains("p31n") && !tried.contains(p.identifier) { connect(p) }
    }

    func centralManager(_ central: CBCentralManager, didConnect p: CBPeripheral) {
        log("已连接 \(p.name ?? "P31n")，查找独立遥测服务。")
        p.discoverServices([probeService])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        guard peripheral?.identifier == p.identifier else { return }
        log("连接失败：\(error?.localizedDescription ?? "unknown")")
        clearConnection()
        connectionLabel.stringValue = "连接失败，请点重新连接。"
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        guard peripheral?.identifier == p.identifier else { return }
        log("键盘连接结束：\(error?.localizedDescription ?? "disconnected")")
        tracker.invalidateHeldKeys()
        clearConnection()
        refreshCounters()
        connectionLabel.stringValue = "键盘已断开，等待恢复。"
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.tried.remove(p.identifier)
            self?.findKeyboard()
        }
    }

    private func clearConnection() {
        peripheral = nil
        eventCharacteristic = nil
        controlCharacteristic = nil
        starting = false
        firmwareStatus = nil
        resetButton.isEnabled = false
        pauseButton.isEnabled = false
    }

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        if let error { log("服务发现失败：\(error.localizedDescription)"); return }
        guard let service = p.services?.first(where: { $0.uuid == probeService }) else {
            connectionLabel.stringValue = "键盘已连接，但当前固件没有遥测服务。刷入试验固件后点“重新连接”。"
            log("未找到试验遥测服务；普通 ZMK/Studio 固件不会产生此类事件。")
            return
        }
        p.discoverCharacteristics([eventUUID, controlUUID], for: service)
    }

    func peripheral(_ p: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        log("键盘 GATT 服务已更新，重新发现。")
        tracker.invalidateHeldKeys()
        eventCharacteristic = nil
        controlCharacteristic = nil
        p.discoverServices([probeService])
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error { log("特征发现失败：\(error.localizedDescription)"); return }
        eventCharacteristic = service.characteristics?.first { $0.uuid == eventUUID }
        controlCharacteristic = service.characteristics?.first { $0.uuid == controlUUID }
        guard let event = eventCharacteristic, controlCharacteristic != nil else {
            connectionLabel.stringValue = "遥测服务不完整，请检查试验固件。"; return
        }
        p.setNotifyValue(true, for: event)
    }

    func peripheral(_ p: CBPeripheral, didUpdateNotificationStateFor c: CBCharacteristic, error: Error?) {
        if let error { log("订阅失败：\(error.localizedDescription)"); return }
        guard c.uuid == eventUUID, c.isNotifying else { return }
        startCapture()
    }

    private func startCapture() {
        guard let p = peripheral, let c = controlCharacteristic else { return }
        tracker = ProbeTracker()
        firmwareStatus = nil
        paused = false
        starting = true
        pauseButton.title = "暂停"
        refreshCounters()
        log("请求新采集会话。")
        p.writeValue(Data([1]), for: c, type: .withResponse)
    }

    func peripheral(_ p: CBPeripheral, didWriteValueFor c: CBCharacteristic, error: Error?) {
        guard c.uuid == controlUUID else { return }
        starting = false
        if let error { connectionLabel.stringValue = "采集控制失败"; log(error.localizedDescription); return }
        connectionLabel.stringValue = paused ? "已暂停采集" : "蓝牙遥测已开启，开始按键测试。"
        resetButton.isEnabled = true
        pauseButton.isEnabled = true
        p.readValue(for: c)
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor c: CBCharacteristic, error: Error?) {
        if let error { log("读取失败：\(error.localizedDescription)"); return }
        guard let data = c.value else { return }
        if c.uuid == eventUUID {
            guard let packet = ProbePacket(data: data) else {
                log("报文格式无效，长度=\(data.count)"); return
            }
            let result = tracker.apply(packet)
            log(result.message)
            if result.accepted {
                let line = "\(ISO8601DateFormatter().string(from: Date())),\(packet.bootID),\(packet.session),\(packet.sequence),\(packet.position),\(packet.pressed ? 1 : 0),\(packet.deviceMs)\n"
                try? csvFile?.write(contentsOf: Data(line.utf8))
            }
        } else if c.uuid == controlUUID, let status = FirmwareStatus(data: data) {
            let changed = firmwareStatus == nil || firmwareStatus?.dropped != status.dropped ||
                          firmwareStatus?.replayed != status.replayed || firmwareStatus?.enabled != status.enabled
            firmwareStatus = status
            if changed {
                log("固件状态 boot=\(status.bootID) session=\(status.session) enabled=\(status.enabled) captured=\(status.captured) sent=\(status.sent) dropped=\(status.dropped) replayed=\(status.replayed)")
            }
            if !status.enabled && !paused && !starting && eventCharacteristic?.isNotifying == true {
                log("固件会话已停止，重新开启。")
                startCapture()
            }
        }
        refreshCounters()
    }

    @objc private func reconnect() {
        tried.removeAll()
        if let p = peripheral {
            central.cancelPeripheralConnection(p)
            tracker.invalidateHeldKeys()
            connectionLabel.stringValue = "正在重新连接…"
            // Wait for didDisconnect before issuing a fresh connect for the same peripheral.
            return
        }
        findKeyboard()
    }

    @objc private func resetCapture() {
        log(tracker.summary())
        startCapture()
    }

    @objc private func togglePause() {
        guard let p = peripheral, let c = controlCharacteristic else { return }
        if paused { startCapture() }
        else {
            paused = true
            tracker.invalidateHeldKeys()
            pauseButton.title = "继续"
            p.writeValue(Data([0]), for: c, type: .withResponse)
        }
    }

    @objc private func copySummary() {
        var text = tracker.summary()
        if let s = firmwareStatus {
            text += "\n固件 captured=\(s.captured) sent=\(s.sent) dropped=\(s.dropped) replayed=\(s.replayed) enabled=\(s.enabled)"
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        log("摘要已复制。")
    }

    @objc private func showLogs() { NSWorkspace.shared.open(logDirectory) }
}

@main
enum ProbeMain {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--self-test") { runProtocolChecks(); return }
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = ProbeApp()
        app.delegate = delegate
        let menu = NSMenu()
        let item = NSMenuItem()
        let submenu = NSMenu(title: "P31n Telemetry Probe")
        submenu.addItem(withTitle: "退出 P31n Telemetry Probe", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = submenu
        menu.addItem(item)
        app.mainMenu = menu
        app.run()
        withExtendedLifetime(delegate) {}
    }
}
