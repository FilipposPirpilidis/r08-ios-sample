import Foundation
import Combine
import Core

public final class SmartRingController {
    private let manager: SmartRingBLEManaging

    public var discoveredDevicesPublisher: AnyPublisher<[SmartRingDiscoveredDevice], Never> {
        manager.discoveredDevicesPublisher
    }

    public var connectionStatePublisher: AnyPublisher<SmartRingConnectionState, Never> {
        manager.connectionStatePublisher
    }

    public var tapEventPublisher: AnyPublisher<SmartRingTapEvent?, Never> {
        manager.tapEventPublisher
    }

    public var logsPublisher: AnyPublisher<String, Never> {
        manager.logsPublisher
    }

    public init(manager: SmartRingBLEManaging = BLEManager()) {
        self.manager = manager
    }

    public func startDiscovery() {
        manager.startDiscovery()
    }

    public func connect(target: SmartRingTarget) {
        manager.start(target: target)
    }

    public func disconnect() {
        manager.disconnect()
    }

    public func sendTouchControlOn() {
        manager.sendTouchControlOn()
    }

    public func sendTouchControlOff() {
        manager.sendTouchControlOff()
    }
}
