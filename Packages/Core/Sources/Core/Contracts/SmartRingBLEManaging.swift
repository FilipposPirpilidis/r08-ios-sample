import Foundation
import Combine

public protocol SmartRingBLEManaging: AnyObject {
    var discoveredDevicesPublisher: AnyPublisher<[SmartRingDiscoveredDevice], Never> { get }
    var connectionStatePublisher: AnyPublisher<SmartRingConnectionState, Never> { get }
    var tapEventPublisher: AnyPublisher<SmartRingTapEvent?, Never> { get }
    var logsPublisher: AnyPublisher<String, Never> { get }

    func startDiscovery()
    func start(target: SmartRingTarget)
    func disconnect()
    func sendTouchControlOn()
    func sendTouchControlOff()
}
