import IOKit.pwr_mgt
import Observation

/// Keeps the Mac awake by holding a power management assertion while active.
///
/// The assertion keeps the display awake, which also stops the screen saver
/// from starting and keeps the system from idle sleep. macOS releases it
/// automatically if Lumina quits.
@MainActor
@Observable
final class CaffeineController {
    static let shared = CaffeineController()

    private(set) var isActive = false

    @ObservationIgnored private var assertionID: IOPMAssertionID = 0

    private init() {}

    func toggle() {
        isActive ? deactivate() : activate()
    }

    private func activate() {
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Lumina Caffeine is keeping the Mac awake" as CFString,
            &assertionID
        )
        isActive = result == kIOReturnSuccess
    }

    private func deactivate() {
        IOPMAssertionRelease(assertionID)
        assertionID = 0
        isActive = false
    }
}
