import AppKit
import Observation

/// Quits every open app, as if pressing ⌘Q in each, except the ones the user
/// chose to keep open. Apps with unsaved changes still ask to save.
@MainActor
@Observable
final class QuitAllController {
    struct AppInfo: Identifiable {
        let bundleID: String
        let name: String
        let icon: NSImage

        var id: String { bundleID }
    }

    static let shared = QuitAllController()

    /// Apps that are never quit: Finder (which doesn't really quit) and Lumina.
    static let alwaysKeptBundleIDs: Set<String> = [
        "com.apple.finder",
        Bundle.main.bundleIdentifier ?? "app.lumina.Lumina",
    ]

    private static let keptKey = "quitAll.keptBundleIDs"

    /// Bundle IDs of the apps to keep open, in the order they were added.
    private(set) var keptBundleIDs: [String] {
        didSet { defaults.set(keptBundleIDs, forKey: Self.keptKey) }
    }

    /// Briefly true after quitting, so the button can confirm it worked.
    private(set) var showsConfirmation = false
    /// Counts quits; changes to it trigger the button's bounce.
    private(set) var quitCount = 0

    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var confirmationTask: Task<Void, Never>?

    private init() {
        keptBundleIDs = defaults.stringArray(forKey: Self.keptKey) ?? []
    }

    func quitApps() {
        for app in appsToQuit {
            app.terminate()
        }
        confirm()
    }

    private func confirm() {
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        quitCount += 1
        showsConfirmation = true
        confirmationTask?.cancel()
        confirmationTask = Task {
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            showsConfirmation = false
        }
    }

    /// The running apps a press would quit.
    var appsToQuit: [NSRunningApplication] {
        let kept = Set(keptBundleIDs).union(Self.alwaysKeptBundleIDs)
        return NSWorkspace.shared.runningApplications.filter { app in
            app.activationPolicy == .regular
                && app.processIdentifier != ProcessInfo.processInfo.processIdentifier
                && !kept.contains(app.bundleIdentifier ?? "")
        }
    }

    // MARK: - Keep-open list

    var keptApps: [AppInfo] {
        keptBundleIDs.map(Self.info(for:))
    }

    /// Running apps that could be added to the keep-open list.
    var addableRunningApps: [AppInfo] {
        let excluded = Set(keptBundleIDs).union(Self.alwaysKeptBundleIDs)
        let ids = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap(\.bundleIdentifier)
            .filter { !excluded.contains($0) }
        return Array(Set(ids)).map(Self.info(for:))
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func keep(_ bundleID: String) {
        guard !keptBundleIDs.contains(bundleID), !Self.alwaysKeptBundleIDs.contains(bundleID) else { return }
        keptBundleIDs.append(bundleID)
    }

    func stopKeeping(_ bundleID: String) {
        keptBundleIDs.removeAll { $0 == bundleID }
    }

    /// Lets the user pick any installed app to keep open.
    func chooseAppToKeep() {
        let panel = NSOpenPanel()
        panel.title = "Keep App Open"
        panel.prompt = "Keep Open"
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        NSApp.activate()
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let bundleID = Bundle(url: url)?.bundleIdentifier {
                keep(bundleID)
            }
        }
    }

    private static func info(for bundleID: String) -> AppInfo {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return AppInfo(bundleID: bundleID, name: bundleID, icon: NSWorkspace.shared.icon(for: .application))
        }
        let name = FileManager.default.displayName(atPath: url.path)
        return AppInfo(
            bundleID: bundleID,
            name: name.hasSuffix(".app") ? String(name.dropLast(4)) : name,
            icon: NSWorkspace.shared.icon(forFile: url.path)
        )
    }
}
