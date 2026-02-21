import Foundation

public enum SmartRingConnectionState: Equatable {
    case disconnected
    case scanning
    case connecting
    case connected
    case error(String)
}
