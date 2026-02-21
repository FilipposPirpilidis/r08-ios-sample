import Foundation
import CoreBluetooth

public enum SmartRingUUIDs {
    public static let tapService = CBUUID(string: "6E40FFF0-B5A3-F393-E0A9-E50E24DCCA9E")
    public static let tapNotifyCharacteristic = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")

    public static let preferredWriteCharacteristicUUIDs: [CBUUID] = [
        CBUUID(string: "DE5BF72A-D711-4E47-AF26-65E3012A5DC7"),
        CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
    ]

    public static let scanServices: [CBUUID] = [tapService]
}
