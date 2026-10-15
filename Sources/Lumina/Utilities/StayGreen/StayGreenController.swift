import IOKit.pwr_mgt
import Observation

/// Keeps chat apps such as Microsoft Teams showing you as available.
///
/// Rather than nudging the cursor, this periodically tells the system the
/// user is active, which resets the idle timers those apps read. It needs no
/// Accessibility permission and never moves the pointer. Like any real
/// activity, it also keeps the display from sleeping while on.
@MainActor
@Observable
final class StayGreenController {
    static let shared = StayGreenController()

    /// Well below the shortest idle threshold of common chat apps (Teams: 5 min).
    private static let interval: Duration = .seconds(30)

    private(set) var isActive = false

    @ObservationIgnored private var assertionID: IOPMAssertionID = 0
    @ObservationIgnored private var heartbeat: Task<Void, Never>?

    private init() {}

    func toggle() {
        isActive ? deactivate() : activate()
    }

    private func activate() {
        isActive = true
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                self?.declareActivity()
                try? await Task.sleep(for: Self.interval)
            }
        }
    }

    private func deactivate() {
        heartbeat?.cancel()
        heartbeat = nil
        if assertionID != 0 {
            IOPMAssertionRelease(assertionID)
            assertionID = 0
        }
        isActive = false
    }

    private func declareActivity() {
        // Reusing the same ID refreshes the existing assertion.
        IOPMAssertionDeclareUserActivity(
            "Lumina Stay Green is keeping you available" as CFString,
            kIOPMUserActiveLocal,
            &assertionID
        )
    }
}
