import AppKit
import Observation
import Sparkle

/// Keeps Lumina up to date with Sparkle.
///
/// Sparkle checks the release feed once a day. Instead of interrupting with
/// its own window, a scheduled check that finds an update shows a banner in
/// the panel; choosing Update there hands over to Sparkle, which downloads,
/// verifies and installs the update and relaunches Lumina.
@MainActor
@Observable
final class UpdateController: NSObject {
    static let shared = UpdateController()

    /// The version a scheduled check found, while the user hasn't acted on it.
    private(set) var availableVersion: String?
    private(set) var canCheckForUpdates = false

    @ObservationIgnored private var updaterController: SPUStandardUpdaterController?
    @ObservationIgnored private var canCheckObservation: NSKeyValueObservation?

    private override init() {
        super.init()
        // Builds without a release key (like local development builds before
        // running scripts/setup-release-secrets.sh) can't verify updates.
        guard Self.isConfigured else { return }

        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: self
        )
        updaterController = controller
        canCheckObservation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            // Sparkle reports changes on the main thread.
            MainActor.assumeIsolated { self?.canCheckForUpdates = updater.canCheckForUpdates }
        }
    }

    /// Checks now and shows Sparkle's window with the result.
    func checkForUpdates() {
        updaterController?.checkForUpdates(nil)
    }

    /// Hides the banner until the next scheduled check.
    func dismissBanner() {
        availableVersion = nil
    }

    private static var isConfigured: Bool {
        guard Bundle.main.bundleURL.pathExtension == "app",
              let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        else { return false }
        return !key.isEmpty && !key.hasPrefix("REPLACE_")
    }
}

extension UpdateController: @preconcurrency SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    /// Lumina shows scheduled updates in its own banner.
    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        false
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        if !handleShowingUpdate {
            availableVersion = update.displayVersionString
        }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        availableVersion = nil
    }

    func standardUserDriverWillFinishUpdateSession() {
        availableVersion = nil
    }
}
