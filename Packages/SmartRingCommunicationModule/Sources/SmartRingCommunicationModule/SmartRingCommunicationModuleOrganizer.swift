import Foundation

public final class SmartRingCommunicationModuleOrganizer {
    public static let shared = SmartRingCommunicationModuleOrganizer()

    public let smartRingController = SmartRingController()

    private init() {}
}
