import Foundation
import Combine
import Core
import SmartRingCommunicationModule

final class HomeViewModel {
    private enum Keys {
        static let targetDeviceUUID = "smartring.target.device.uuid"
    }

    private let defaults: UserDefaults
    private let controller = SmartRingCommunicationModuleOrganizer.shared.smartRingController
    private let linkedTargetSubject = CurrentValueSubject<String, Never>("No linked target")
    private let tapEventTextSubject = CurrentValueSubject<String, Never>("Waiting for tap events...")

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        refreshLinkedTargetText()
    }

    struct Input {
        let viewDidLoadIn: AnyPublisher<Void, Never>
        let connectTapIn: AnyPublisher<Void, Never>
        let disconnectTapIn: AnyPublisher<Void, Never>
        let touchOnTapIn: AnyPublisher<Void, Never>
        let touchOffTapIn: AnyPublisher<Void, Never>
        let unlinkTapIn: AnyPublisher<Void, Never>
        let deviceSelectedIn: AnyPublisher<SmartRingDiscoveredDevice, Never>
    }

    struct Output {
        let connectionStateOut: AnyPublisher<SmartRingConnectionState, Never>
        let discoveredDevicesOut: AnyPublisher<[SmartRingDiscoveredDevice], Never>
        let logsOut: AnyPublisher<String, Never>
        let linkedTargetOut: AnyPublisher<String, Never>
        let tapEventTextOut: AnyPublisher<String, Never>
        let connectTapOut: AnyPublisher<Void, Never>
        let disconnectTapOut: AnyPublisher<Void, Never>
        let touchOnTapOut: AnyPublisher<Void, Never>
        let touchOffTapOut: AnyPublisher<Void, Never>
        let unlinkTapOut: AnyPublisher<Void, Never>
        let deviceSelectedOut: AnyPublisher<SmartRingDiscoveredDevice, Never>
    }

    func convert(input: Input) -> Output {
        let connectTapHandler = input.connectTapIn
            .handleEvents(receiveOutput: { [weak self] _ in
                self?.connectUsingSavedTargetOrStartDiscovery()
            })
            .eraseToAnyPublisher()

        let disconnectTapHandler = input.disconnectTapIn
            .handleEvents(receiveOutput: { [weak self] _ in
                self?.controller.disconnect()
            })
            .eraseToAnyPublisher()

        let touchOnTapHandler = input.touchOnTapIn
            .handleEvents(receiveOutput: { [weak self] _ in
                self?.controller.sendTouchControlOn()
            })
            .eraseToAnyPublisher()

        let touchOffTapHandler = input.touchOffTapIn
            .handleEvents(receiveOutput: { [weak self] _ in
                self?.controller.sendTouchControlOff()
            })
            .eraseToAnyPublisher()

        let unlinkTapHandler = input.unlinkTapIn
            .handleEvents(receiveOutput: { [weak self] _ in
                self?.defaults.removeObject(forKey: Keys.targetDeviceUUID)
                self?.refreshLinkedTargetText()
                self?.controller.disconnect()
                self?.controller.startDiscovery()
            })
            .eraseToAnyPublisher()

        let deviceSelectedHandler = input.deviceSelectedIn
            .handleEvents(receiveOutput: { [weak self] device in
                guard let self else { return }
                self.defaults.set(device.id.uuidString, forKey: Keys.targetDeviceUUID)
                self.refreshLinkedTargetText()
                self.controller.connect(target: SmartRingTarget(deviceIdentifier: device.id))
            })
            .eraseToAnyPublisher()

        let viewDidLoadHandler = input.viewDidLoadIn
            .handleEvents(receiveOutput: { [weak self] _ in
                self?.connectUsingSavedTargetOrStartDiscovery()
            })
            .eraseToAnyPublisher()

        controller.tapEventPublisher
            .sink { [weak self] event in
                guard let self else { return }
                if let event {
                    self.tapEventTextSubject.send("Last tap event: \(event.rawValue)")
                }
            }
            .store(in: &cancellables)

        return Output(
            connectionStateOut: controller.connectionStatePublisher,
            discoveredDevicesOut: controller.discoveredDevicesPublisher,
            logsOut: controller.logsPublisher,
            linkedTargetOut: linkedTargetSubject.eraseToAnyPublisher(),
            tapEventTextOut: tapEventTextSubject.eraseToAnyPublisher(),
            connectTapOut: connectTapHandler.merge(with: viewDidLoadHandler).eraseToAnyPublisher(),
            disconnectTapOut: disconnectTapHandler,
            touchOnTapOut: touchOnTapHandler,
            touchOffTapOut: touchOffTapHandler,
            unlinkTapOut: unlinkTapHandler,
            deviceSelectedOut: deviceSelectedHandler
        )
    }

    private var cancellables = Set<AnyCancellable>()

    private func connectUsingSavedTargetOrStartDiscovery() {
        if let target = savedTarget() {
            controller.connect(target: target)
        } else {
            controller.startDiscovery()
        }
    }

    private func savedTarget() -> SmartRingTarget? {
        guard let uuidString = defaults.string(forKey: Keys.targetDeviceUUID) else { return nil }
        guard let uuid = UUID(uuidString: uuidString) else { return nil }
        return SmartRingTarget(deviceIdentifier: uuid)
    }

    private func refreshLinkedTargetText() {
        if let uuid = defaults.string(forKey: Keys.targetDeviceUUID), !uuid.isEmpty {
            linkedTargetSubject.send("Linked target: \(uuid)")
        } else {
            linkedTargetSubject.send("No linked target")
        }
    }
}
