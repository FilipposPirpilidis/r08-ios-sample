import Foundation
import CoreBluetooth

public struct SmartRingDiscoveredDevice: Identifiable, Equatable {
    public let id: UUID
    public let name: String
    public let rssi: Int
    public let peripheral: CBPeripheral

    public init(id: UUID, name: String, rssi: Int, peripheral: CBPeripheral) {
        self.id = id
        self.name = name
        self.rssi = rssi
        self.peripheral = peripheral
    }

    public static func == (lhs: SmartRingDiscoveredDevice, rhs: SmartRingDiscoveredDevice) -> Bool {
        lhs.id == rhs.id
    }
}
