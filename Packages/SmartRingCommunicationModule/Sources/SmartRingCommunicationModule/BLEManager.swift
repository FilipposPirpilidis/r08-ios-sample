import Foundation
import CoreBluetooth
import Combine
import Core

public final class BLEManager: NSObject, SmartRingBLEManaging {
    private static let queue = DispatchQueue(label: "smartring.ble.queue", qos: .userInitiated)

    private let discoveredDevicesSubject = CurrentValueSubject<[SmartRingDiscoveredDevice], Never>([])
    private let connectionStateSubject = CurrentValueSubject<SmartRingConnectionState, Never>(.disconnected)
    private let tapEventSubject = CurrentValueSubject<SmartRingTapEvent?, Never>(nil)
    private let logsSubject = PassthroughSubject<String, Never>()

    private lazy var centralManager = CBCentralManager(delegate: self, queue: Self.queue)

    private var target: SmartRingTarget?
    private var connectedPeripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?

    private let tapWindowSeconds: TimeInterval = 0.6
    private var tapCount: Int = 0
    private var lastTapTime: TimeInterval?
    private var tapFinalizeWorkItem: DispatchWorkItem?

    public var discoveredDevicesPublisher: AnyPublisher<[SmartRingDiscoveredDevice], Never> {
        discoveredDevicesSubject.eraseToAnyPublisher()
    }

    public var connectionStatePublisher: AnyPublisher<SmartRingConnectionState, Never> {
        connectionStateSubject.eraseToAnyPublisher()
    }

    public var tapEventPublisher: AnyPublisher<SmartRingTapEvent?, Never> {
        tapEventSubject.eraseToAnyPublisher()
    }

    public var logsPublisher: AnyPublisher<String, Never> {
        logsSubject.eraseToAnyPublisher()
    }

    public override init() {
        super.init()
    }

    public func startDiscovery() {
        target = nil
        Self.queue.async { [weak self] in
            self?.startDiscoveryInternal(resetList: true)
        }
    }

    public func start(target: SmartRingTarget) {
        self.target = target
        Self.queue.async { [weak self] in
            guard let self else { return }
            self.discoveredDevicesSubject.send([])
            self.connectIfKnownElseScanTarget()
        }
    }

    public func disconnect() {
        Self.queue.async { [weak self] in
            guard let self, let connectedPeripheral else { return }
            self.centralManager.cancelPeripheralConnection(connectedPeripheral)
        }
    }

    public func sendTouchControlOn() {
        guard let peripheral = connectedPeripheral, let writeCharacteristic else {
            log("sendTouchControlOn skipped: no connected peripheral / write characteristic")
            return
        }

        let cmd1 = Data([
            0x3B, 0x02, 0x00, 0x03, 0x01, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x41
        ])
        let cmd2 = Data([
            0x3B, 0x02, 0x01, 0x00, 0x01, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x3F
        ])

        peripheral.writeValue(cmd1, for: writeCharacteristic, type: .withResponse)
        peripheral.writeValue(cmd2, for: writeCharacteristic, type: .withResponse)
        log("➡️ sendTouchControlOn cmd1: \(hexString(cmd1))")
        log("➡️ sendTouchControlOn cmd2: \(hexString(cmd2))")
    }

    public func sendTouchControlOff() {
        guard let peripheral = connectedPeripheral, let writeCharacteristic else {
            log("sendTouchControlOff skipped: no connected peripheral / write characteristic")
            return
        }

        let cmd1 = Data([
            0x3B, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x3C
        ])
        let cmd2 = Data([
            0x3B, 0x02, 0x00, 0x03, 0x01, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x41
        ])
        let cmd3 = Data([
            0x3B, 0x02, 0x01, 0x00, 0x01, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x3F
        ])
        let cmd4 = Data([
            0x3B, 0x02, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x3E
        ])

        peripheral.writeValue(cmd1, for: writeCharacteristic, type: .withResponse)
        Self.queue.asyncAfter(deadline: .now() + 0.15) {
            peripheral.writeValue(cmd2, for: writeCharacteristic, type: .withResponse)
        }
        Self.queue.asyncAfter(deadline: .now() + 0.30) {
            peripheral.writeValue(cmd3, for: writeCharacteristic, type: .withResponse)
        }
        Self.queue.asyncAfter(deadline: .now() + 0.45) {
            peripheral.writeValue(cmd4, for: writeCharacteristic, type: .withResponse)
        }

        log("➡️ sendTouchControlOff cmd1: \(hexString(cmd1))")
        log("➡️ sendTouchControlOff cmd2: \(hexString(cmd2))")
        log("➡️ sendTouchControlOff cmd3: \(hexString(cmd3))")
        log("➡️ sendTouchControlOff cmd4: \(hexString(cmd4))")
    }

    private func connectIfKnownElseScanTarget() {
        guard centralManager.state == .poweredOn else {
            connectionStateSubject.send(.error("Bluetooth is not powered on"))
            log("Bluetooth not ready: \(centralManager.state.rawValue)")
            return
        }

        guard let target else {
            connectionStateSubject.send(.error("Target device is missing"))
            return
        }

        let known = centralManager.retrievePeripherals(withIdentifiers: [target.deviceIdentifier])
        if let peripheral = known.first {
            upsertDevice(peripheral: peripheral, rssi: -50)
            log("Found known target \(peripheral.identifier.uuidString), connecting")
            connect(peripheral)
            return
        }

        startDiscoveryInternal(resetList: false)
    }

    private func startDiscoveryInternal(resetList: Bool) {
        guard centralManager.state == .poweredOn else {
            connectionStateSubject.send(.error("Bluetooth is not powered on"))
            log("Bluetooth not ready: \(centralManager.state.rawValue)")
            return
        }

        if resetList {
            discoveredDevicesSubject.send([])
        }

        let connected = centralManager.retrieveConnectedPeripherals(withServices: SmartRingUUIDs.scanServices)
        for peripheral in connected {
            upsertDevice(peripheral: peripheral, rssi: -50)
        }

        connectionStateSubject.send(.scanning)
        log("Scanning Smart Ring tap service and listing connected peripherals")
        centralManager.scanForPeripherals(withServices: SmartRingUUIDs.scanServices, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    private func connect(_ peripheral: CBPeripheral) {
        connectionStateSubject.send(.connecting)
        centralManager.stopScan()
        peripheral.delegate = self
        centralManager.connect(peripheral, options: nil)
    }

    private func upsertDevice(peripheral: CBPeripheral, rssi: Int) {
        let discovered = SmartRingDiscoveredDevice(
            id: peripheral.identifier,
            name: peripheral.name ?? "Unknown",
            rssi: rssi,
            peripheral: peripheral
        )

        var current = discoveredDevicesSubject.value
        if let index = current.firstIndex(where: { $0.id == discovered.id }) {
            current[index] = discovered
        } else {
            current.append(discovered)
        }
        discoveredDevicesSubject.send(current)
    }

    private func resetCharacteristicHandles() {
        writeCharacteristic = nil
    }

    private func isTapPacket(serviceUUID: CBUUID?, charUUID: CBUUID, data: Data) -> Bool {
        guard serviceUUID == SmartRingUUIDs.tapService,
              charUUID == SmartRingUUIDs.tapNotifyCharacteristic,
              data.count >= 2 else { return false }

        let bytes = [UInt8](data)
        return bytes[0] == 0x73 && bytes[1] == 0x25
    }

    private func handleTapEvent() {
        let now = Date().timeIntervalSince1970
        if let lastTapTime, now - lastTapTime <= tapWindowSeconds {
            tapCount += 1
        } else {
            tapCount = 1
        }
        lastTapTime = now

        tapFinalizeWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let event: SmartRingTapEvent
            switch self.tapCount {
            case 1: event = .single
            case 2: event = .double
            case 3: event = .triple
            default: event = .quad
            }
            self.tapEventSubject.send(event)
            self.log("👆 Tap event: \(event.rawValue)")
            self.tapCount = 0
            self.lastTapTime = nil
        }
        tapFinalizeWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + tapWindowSeconds, execute: workItem)
    }

    private func log(_ message: String) {
        logsSubject.send(message)
    }

    private func hexString(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}

extension BLEManager: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            connectionStateSubject.send(.disconnected)
            if let target {
                start(target: target)
            } else {
                startDiscoveryInternal(resetList: false)
            }
        case .poweredOff:
            connectionStateSubject.send(.error("Bluetooth is powered off"))
        case .unauthorized:
            connectionStateSubject.send(.error("Bluetooth unauthorized"))
        case .unsupported:
            connectionStateSubject.send(.error("Bluetooth unsupported"))
        case .resetting:
            connectionStateSubject.send(.error("Bluetooth resetting"))
        case .unknown:
            connectionStateSubject.send(.error("Bluetooth unknown"))
        @unknown default:
            connectionStateSubject.send(.error("Bluetooth unknown"))
        }
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String : Any],
        rssi RSSI: NSNumber
    ) {
        _ = advertisementData
        upsertDevice(peripheral: peripheral, rssi: RSSI.intValue)

        guard let target else { return }
        guard peripheral.identifier == target.deviceIdentifier else { return }

        log("Target discovered \(peripheral.identifier.uuidString), connecting")
        connect(peripheral)
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectedPeripheral = peripheral
        resetCharacteristicHandles()
        connectionStateSubject.send(.connected)
        log("Connected to \(peripheral.identifier.uuidString)")
        peripheral.discoverServices(nil)
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connectionStateSubject.send(.error("Failed to connect: \(error?.localizedDescription ?? "Unknown")"))
        log("Connection failed for \(peripheral.identifier.uuidString)")

        if target == nil {
            startDiscoveryInternal(resetList: false)
        }
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        _ = error
        connectedPeripheral = nil
        resetCharacteristicHandles()
        connectionStateSubject.send(.disconnected)
        log("Disconnected \(peripheral.identifier.uuidString)")
    }
}

extension BLEManager: CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            connectionStateSubject.send(.error("Service discovery failed: \(error.localizedDescription)"))
            return
        }

        guard let services = peripheral.services else { return }
        let discoveredServiceUUIDs = services.map(\.uuid.uuidString).joined(separator: ", ")
        log("Discovered services: \(discoveredServiceUUIDs)")
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error {
            connectionStateSubject.send(.error("Characteristic discovery failed: \(error.localizedDescription)"))
            return
        }

        guard let characteristics = service.characteristics else { return }

        for characteristic in characteristics {
            log("Found characteristic \(characteristic.uuid.uuidString) on \(service.uuid.uuidString) props=\(characteristic.properties.rawValue)")

            if writeCharacteristic == nil,
               SmartRingUUIDs.preferredWriteCharacteristicUUIDs.contains(characteristic.uuid) {
                writeCharacteristic = characteristic
                log("Write characteristic ready: \(characteristic.uuid.uuidString)")
            }

            if characteristic.uuid == SmartRingUUIDs.tapNotifyCharacteristic,
               (characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate)),
               !characteristic.isNotifying {
                peripheral.setNotifyValue(true, for: characteristic)
                log("Requesting tap notifications on \(characteristic.uuid.uuidString)")
            }
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            log("❌ Notify state update failed for \(characteristic.uuid.uuidString): \(error.localizedDescription)")
            return
        }

        let state = characteristic.isNotifying ? "ENABLED" : "DISABLED"
        log("✅ Notify state \(state) for \(characteristic.uuid.uuidString)")
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            log("Notify read error \(characteristic.uuid.uuidString): \(error.localizedDescription)")
            return
        }

        guard let value = characteristic.value else { return }
        log("📩 Notify \(characteristic.uuid.uuidString) (\(value.count) bytes): \(hexString(value))")

        if isTapPacket(serviceUUID: characteristic.service?.uuid, charUUID: characteristic.uuid, data: value) {
            handleTapEvent()
        }
    }
}
