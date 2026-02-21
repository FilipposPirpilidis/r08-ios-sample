import Foundation

public struct SmartRingTarget {
    public let deviceIdentifier: UUID

    public init(deviceIdentifier: UUID) {
        self.deviceIdentifier = deviceIdentifier
    }
}
