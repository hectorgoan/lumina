import AppKit
import Observation
import SwiftUI
import UserNotifications

/// One app (or the files of one deleted app) on the review page, with the
/// kinds of files to remove.
struct UninstallEntry: Identifiable {
    /// Nil for files left behind by an app that's already gone.
    let app: InstalledApp?
    let bundleID: String
    let name: String
    var leftovers: [Leftover]
    var isIncluded = true
    var excludedKinds: Set<LeftoverKind> = []
    /// On the Never Uninstall list: shown, but can't be included.
    var isProtected = false

    var id: String { bundleID }

    /// Everything found, the app itself first.
    var items: [Leftover] {
        let bundle = app.map { [Leftover(url: $0.url, kind: .app, bytes: $0.bytes ?? 0)] } ?? []
        return bundle + leftovers
    }

    var kinds: [LeftoverKind] {
        LeftoverKind.allCases.filter { kind in items.contains { $0.kind == kind } }
    }

    func items(of kind: LeftoverKind) -> [Leftover] { items.filter { $0.kind == kind } }

    /// What Move to Trash removes.
    var selectedItems: [Leftover] {
        guard isIncluded, !isProtected else { return [] }
        return items.filter { !excludedKinds.contains($0.kind) }
    }
}

/// What a review page shows.
struct UninstallPlan {
    var entries: [UninstallEntry]
    var isLoading = true

    var selectedItems: [Leftover] { entries.flatMap(\.selectedItems) }
    var selectedBytes: Int64 { selectedItems.reduce(0) { $0 + $1.bytes } }
    var title: String {
        entries.count == 1 ? entries[0].name : "Uninstall \(entries.count) Apps"
    }
}

/// What Move to Trash did, so it can be put back.
struct UninstallResult {
    let names: [String]
    let bytes: Int64
    /// Original location → where it is in the Trash.
    let moved: [URL: URL]
    var failures: [String] = []
    var putBackFailed = false
    var isPutBack = false
    var isTrashEmptied = false
    var emptyFailed = false

    var title: String {
        let subject = names.count == 1 ? names[0] : "\(names.count) apps"
        if isTrashEmptied { return "\(subject) Removed" }
        return isPutBack ? "\(subject) Put Back" : "\(subject) Moved to the Trash"
    }
}

/// An app on the Never Uninstall list.
struct ProtectedApp: Codable, Hashable, Identifiable {
    let bundleID: String
    let name: String
    let path: String

    var id: String { bundleID }
}

/// Removes apps and everything they leave in the user's Library, always
/// through the Trash so it can be undone. Suggests apps that haven't been
/// opened in a while, finds files left by apps already deleted, and notices
/// when an app is deleted in Finder.
@MainActor
@Observable
final class UninstallerController: NSObject {
    /// The list page's tabs: three orders for the apps, and Left Behind.
    enum ListTab: CaseIterable {
        case size, lastOpened, name, leftBehind

        var title: String {
            switch self {
            case .size: "Size"
            case .lastOpened: "Last Opened"
            case .name: "Name"
            case .leftBehind: "Left Behind"
            }
        }
    }

    enum UnusedThreshold: Int, CaseIterable {
        case threeMonths = 3, sixMonths = 6, oneYear = 12

        var title: String {
            switch self {
            case .threeMonths: "3 months"
            case .sixMonths: "6 months"
            case .oneYear: "1 year"
            }
        }
    }

    static let shared = UninstallerController()

    // MARK: Settings

    var unusedThreshold: UnusedThreshold {
        didSet { defaults.set(unusedThreshold.rawValue, forKey: Keys.threshold) }
    }

    /// Offers to clean up after apps deleted in Finder.
    var noticesDeletions: Bool {
        didSet {
            defaults.set(noticesDeletions, forKey: Keys.notices)
            if noticesDeletions { requestNotifications() } else { notice = nil }
        }
    }

    /// Never suggested, and never uninstalled.
    private(set) var protectedApps: [ProtectedApp] {
        didSet { defaults.set(try? JSONEncoder().encode(protectedApps), forKey: Keys.protected) }
    }

    /// Shows the largest unused apps on the tile. Off by default: the tile
    /// then offers search, Left Behind and the Dumpster.
    var showsUnusedOnTile: Bool {
        didSet { defaults.set(showsUnusedOnTile, forKey: Keys.showsUnused) }
    }

    // MARK: State

    private(set) var apps: [InstalledApp] = []
    private(set) var leftBehind: [LeftBehindApp] = []
    private(set) var hasScanned = false
    /// A scan is under way; earlier results, if any, are still shown.
    private(set) var isScanning = false
    /// The list page's tab, set by whatever opened it.
    var listTab: ListTab = .lastOpened
    /// An app just deleted in Finder, and what it left.
    private(set) var notice: LeftBehindApp?
    /// The review page's contents.
    var plan: UninstallPlan?
    private(set) var result: UninstallResult?
    private(set) var isWorking = false

    /// The panel's store, for switching pages.
    @ObservationIgnored weak var store: UtilityStore?

    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private let home = FileManager.default.homeDirectoryForCurrentUser
    @ObservationIgnored private var lastScan: Date?
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var sizeCache: [String: [Double]]
    @ObservationIgnored private var watcher: DispatchSourceFileSystemObject?
    @ObservationIgnored private var watchDebounce: Task<Void, Never>?
    /// Apps Lumina itself removed, so their disappearance isn't "noticed".
    @ObservationIgnored private var removedByLumina = Set<String>()

    private enum Keys {
        static let threshold = "uninstaller.unusedMonths"
        static let notices = "uninstaller.noticesDeletions"
        static let protected = "uninstaller.neverUninstall"
        static let showsUnused = "uninstaller.showsUnusedOnTile"
        static let sizes = "uninstaller.sizeCache"
    }

    nonisolated static let notificationCategory = "uninstaller.leftovers"

    private override init() {
        let defaults = UserDefaults.standard
        unusedThreshold = UnusedThreshold(rawValue: defaults.integer(forKey: Keys.threshold)) ?? .sixMonths
        noticesDeletions = defaults.object(forKey: Keys.notices) as? Bool ?? true
        protectedApps = defaults.data(forKey: Keys.protected)
            .flatMap { try? JSONDecoder().decode([ProtectedApp].self, from: $0) } ?? []
        showsUnusedOnTile = defaults.bool(forKey: Keys.showsUnused)
        sizeCache = defaults.dictionary(forKey: Keys.sizes) as? [String: [Double]] ?? [:]
        super.init()
    }

    // MARK: - Suggestions

    func isProtected(bundleID: String) -> Bool {
        protectedApps.contains { $0.bundleID == bundleID }
    }

    /// Apps not opened within the threshold, largest first.
    var unusedApps: [InstalledApp] {
        let cutoff = Calendar.current.date(byAdding: .month, value: -unusedThreshold.rawValue, to: .now) ?? .distantPast
        return apps
            .filter { ($0.lastUsed ?? .distantPast) < cutoff && !isProtected(bundleID: $0.bundleID) }
            .sorted { ($0.bytes ?? 0) > ($1.bytes ?? 0) }
    }

    var unusedBytes: Int64 { unusedApps.reduce(0) { $0 + ($1.bytes ?? 0) } }

    // MARK: - Scanning

    /// Scans the apps, at most every ten minutes or after /Applications changes.
    func refreshIfStale() {
        startWatching()
        if let lastScan, Date.now.timeIntervalSince(lastScan) < 600 { return }
        scan()
    }

    /// Scans the apps, measures them and looks for files left behind, then
    /// shows everything at once, so nothing on screen changes piece by
    /// piece. Earlier results stay while a new scan runs.
    func scan() {
        scanTask?.cancel()
        lastScan = .now
        isScanning = true
        let cache = sizeCache
        let home = home
        let started = Date.now
        scanTask = Task {
            let (found, measured) = await Task.detached(priority: .utility) {
                Self.catalog(cache: cache)
            }.value
            guard !Task.isCancelled else { return }
            let installed = Set(found.map(\.bundleID))
            let candidates = await Task.detached(priority: .utility) {
                LeftoverFinder.leftBehind(home: home, installedBundleIDs: installed)
            }.value
            guard !Task.isCancelled else { return }
            // Apps installed somewhere else still count as installed.
            let orphans = candidates.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleID) == nil }

            sizeCache.merge(measured) { $1 }
            defaults.set(sizeCache, forKey: Keys.sizes)
            // With cached sizes a scan can take a blink; keep the feedback
            // on screen long enough to read as "it scanned".
            let elapsed = Date.now.timeIntervalSince(started)
            if elapsed < 0.8 { try? await Task.sleep(for: .seconds(0.8 - elapsed)) }
            guard !Task.isCancelled else { return }
            withAnimation(Motion.present) {
                apps = found
                leftBehind = orphans
                hasScanned = true
                isScanning = false
            }
        }
    }

    /// The apps with their sizes: cached ones whose bundle hasn't changed,
    /// measured otherwise. Also returns the new cache entries.
    private nonisolated static func catalog(cache: [String: [Double]]) -> ([InstalledApp], [String: [Double]]) {
        var apps = AppCatalog.scan(sizes: cachedSizes(cache))
        var measured: [String: [Double]] = [:]
        for index in apps.indices where apps[index].bytes == nil {
            if Task.isCancelled { break }
            let url = apps[index].url
            let bytes = CleanupScanner.size(of: url)
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate?.timeIntervalSince1970 ?? 0
            apps[index].bytes = bytes
            measured[url.path] = [modified, Double(bytes)]
        }
        return (apps, measured)
    }

    /// Sizes of app bundles whose modification date hasn't changed.
    private nonisolated static func cachedSizes(_ cache: [String: [Double]]) -> [String: Int64] {
        var sizes: [String: Int64] = [:]
        for (path, entry) in cache where entry.count == 2 {
            let modified = (try? URL(fileURLWithPath: path).resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate?.timeIntervalSince1970
            if modified == entry[0] { sizes[path] = Int64(entry[1]) }
        }
        return sizes
    }

    // MARK: - Pages

    func openList(tab: ListTab = .lastOpened) {
        guard let store else { return }
        result = nil
        listTab = tab
        store.swapPage { store.uninstallerPage = .list }
    }

    /// Reviews apps: finds their files, then shows them.
    func review(_ apps: [InstalledApp]) {
        let entries = apps.map { app in
            UninstallEntry(
                app: app, bundleID: app.bundleID, name: app.name, leftovers: [],
                isIncluded: !isProtected(bundleID: app.bundleID), isProtected: isProtected(bundleID: app.bundleID)
            )
        }
        startReview(entries)
    }

    func review(leftBehind group: LeftBehindApp) {
        var entry = UninstallEntry(app: nil, bundleID: group.bundleID, name: group.name, leftovers: group.items)
        entry.isIncluded = true
        startReview([entry], isLoaded: true)
    }

    /// Opens the review page in the panel, opening the panel if needed:
    /// for apps tossed in the Dumpster.
    /// Returns whether the panel opened; if not, the review waits there
    /// for the next time it's opened.
    @discardableResult
    func reviewFromOutside(_ apps: [InstalledApp]) -> Bool {
        result = nil
        review(apps)
        return MenuBarPanel.open()
    }

    private func startReview(_ entries: [UninstallEntry], isLoaded: Bool = false) {
        guard let store else { return }
        result = nil
        plan = UninstallPlan(entries: entries, isLoading: !isLoaded)
        store.swapPage { store.uninstallerPage = .review }
        guard !isLoaded else { return }

        let home = home
        Task {
            var loaded = entries
            for index in loaded.indices {
                var entry = loaded[index]
                let appURL = entry.app?.url
                let bundleID = entry.bundleID, name = entry.name
                let (leftovers, appBytes) = await Task.detached(priority: .userInitiated) {
                    (LeftoverFinder.leftovers(bundleID: bundleID, name: name, home: home),
                     appURL.map(CleanupScanner.size(of:)))
                }.value
                entry.leftovers = leftovers
                if let appBytes, var app = entry.app {
                    app.bytes = appBytes
                    entry = UninstallEntry(
                        app: app, bundleID: entry.bundleID, name: entry.name, leftovers: leftovers,
                        isIncluded: entry.isIncluded, excludedKinds: entry.excludedKinds, isProtected: entry.isProtected
                    )
                }
                loaded[index] = entry
            }
            // The review may have been left meanwhile.
            guard plan?.entries.map(\.id) == entries.map(\.id) else { return }
            plan?.entries = loaded
            plan?.isLoading = false
        }
    }

    func backToGrid() {
        guard let store else { return }
        let change: () -> Void = {
            store.uninstallerPage = nil
            self.plan = nil
            self.result = nil
        }
        store.swapPage(change)
    }

    // MARK: - Removing

    /// Quits the apps, then moves everything selected to the Trash.
    func moveToTrash() {
        guard let plan, !isWorking else { return }
        let items = plan.selectedItems
        guard !items.isEmpty else { return }
        isWorking = true
        let names = plan.entries.filter { $0.isIncluded && !$0.isProtected }.map(\.name)
        let bytes = plan.selectedBytes

        Task {
            var failures: [String] = []
            for entry in plan.entries where entry.isIncluded && entry.app != nil {
                if await !quit(bundleID: entry.bundleID) { failures.append("\(entry.name) didn’t quit.") }
                removedByLumina.insert(entry.bundleID)
            }
            var moved: [URL: URL] = [:]
            for item in items {
                // One at a time, so one failure doesn't stop the rest.
                var trashed = (try? await NSWorkspace.shared.recycle([item.url]))?.values.first
                // macOS keeps apps from removing other apps, so an app can
                // still be there; Finder may move it.
                if FileManager.default.fileExists(atPath: item.url.path) {
                    trashed = await FinderScript.trash(item.url)
                }
                if let trashed, !FileManager.default.fileExists(atPath: item.url.path) {
                    moved[item.url] = trashed
                } else {
                    failures.append(item.url.lastPathComponent)
                }
            }
            isWorking = false
            let result = UninstallResult(names: names, bytes: bytes, moved: moved, failures: failures)
            if let store {
                let change: () -> Void = {
                    self.result = result
                    store.uninstallerPage = .done
                }
                store.swapPage(change)
            }
            leftBehind.removeAll { group in plan.entries.contains { $0.bundleID == group.bundleID && $0.isIncluded } }
            if notice.map({ group in plan.entries.contains { $0.bundleID == group.bundleID } }) == true { notice = nil }
            scan()
        }
    }

    /// Moves everything back from the Trash to where it was.
    func putBack() {
        guard let result, !result.isPutBack, !isWorking else { return }
        isWorking = true
        Task {
            var failed = false
            for (original, trashed) in result.moved {
                let folder = original.deletingLastPathComponent()
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                if (try? FileManager.default.moveItem(at: trashed, to: original)) == nil {
                    // Apps go back through Finder, which may put them in
                    // /Applications when Lumina can't.
                    _ = await FinderScript.move(trashed, into: folder)
                }
                if !FileManager.default.fileExists(atPath: original.path) { failed = true }
            }
            var updated = result
            updated.putBackFailed = failed
            updated.isPutBack = !failed
            withAnimation(.snappy(duration: 0.25)) { self.result = updated }
            isWorking = false
            scan()
        }
    }

    /// True for a moment after the first click on Empty Trash, which then
    /// asks to be clicked again.
    private(set) var awaitsEmptyConfirmation = false
    @ObservationIgnored private var emptyConfirmationTask: Task<Void, Never>?

    /// Empty Trash: the first click asks for a second one, which empties the
    /// whole Trash through Finder, freeing the space for good.
    func emptyTrashTapped() {
        guard let result, !result.isTrashEmptied, !isWorking else { return }
        guard awaitsEmptyConfirmation else {
            awaitsEmptyConfirmation = true
            emptyConfirmationTask = Task {
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { return }
                awaitsEmptyConfirmation = false
            }
            return
        }
        emptyConfirmationTask?.cancel()
        awaitsEmptyConfirmation = false
        isWorking = true
        Task {
            let emptied = await FinderScript.emptyTrash()
            var updated = result
            if emptied { updated.isTrashEmptied = true } else { updated.emptyFailed = true }
            withAnimation(.snappy(duration: 0.25)) { self.result = updated }
            isWorking = false
        }
    }

    func openTrash() {
        NSWorkspace.shared.open(home.appending(path: ".Trash"))
    }

    /// Asks running copies of an app to quit, and waits up to five seconds.
    private func quit(bundleID: String) async -> Bool {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        guard !running.isEmpty else { return true }
        running.forEach { $0.terminate() }
        for _ in 0..<50 {
            if running.allSatisfy(\.isTerminated) { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return running.allSatisfy(\.isTerminated)
    }

    // MARK: - Never Uninstall

    func protect(_ url: URL) {
        guard let app = AppCatalog.app(at: url), !isProtected(bundleID: app.bundleID) else { return }
        protectedApps.append(ProtectedApp(bundleID: app.bundleID, name: app.name, path: url.path))
    }

    func unprotect(_ app: ProtectedApp) {
        protectedApps.removeAll { $0.bundleID == app.bundleID }
    }

    /// Lets the user pick an app for the Never Uninstall list.
    func chooseAppToProtect() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Never Uninstall"
        NSApp.activate()
        if panel.runModal() == .OK, let url = panel.url { protect(url) }
    }

    // MARK: - Noticing deletions

    /// Watches /Applications: when an app disappears that Lumina didn't
    /// remove, it looks for what the app left and offers to clean it up.
    private func startWatching() {
        guard watcher == nil else { return }
        let descriptor = open("/Applications", O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.applicationsChanged() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        watcher = source
        registerNotificationActions()
    }

    private func applicationsChanged() {
        watchDebounce?.cancel()
        watchDebounce = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            let before = apps
            let now = await Task.detached(priority: .utility) { AppCatalog.scan() }.value
            let remaining = Set(now.map(\.bundleID))
            let removed = before.filter { !remaining.contains($0.bundleID) && !removedByLumina.contains($0.bundleID) }
            removedByLumina.subtract(before.map(\.bundleID).filter { !remaining.contains($0) })
            lastScan = nil
            scan()
            if noticesDeletions, let app = removed.first { await noticeDeletion(of: app) }
        }
    }

    private func noticeDeletion(of app: InstalledApp) async {
        let home = home
        let leftovers = await Task.detached(priority: .utility) {
            LeftoverFinder.leftovers(bundleID: app.bundleID, name: app.name, home: home)
        }.value
        let group = LeftBehindApp(bundleID: app.bundleID, name: app.name, items: leftovers)
        guard group.bytes > 0 else { return }
        notice = group
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }

        let content = UNMutableNotificationContent()
        content.title = "\(app.name) left \(CleanupFormat.bytes(group.bytes)) behind"
        content.body = "Its settings, caches and other files are still on your Mac."
        content.categoryIdentifier = Self.notificationCategory
        content.userInfo = ["bundleID": app.bundleID]
        // Asked only once there's something to say.
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "uninstaller.\(app.bundleID)", content: content, trigger: nil)
        )
    }

    /// The tile's and notification's Clean Up.
    func reviewNotice() {
        guard let notice else { return }
        result = nil
        review(leftBehind: notice)
        MenuBarPanel.open()
    }

    func ignoreNotice() {
        notice = nil
    }

    /// Handles the notification's buttons.
    func handleNotificationAction(_ action: String) {
        switch action {
        case "cleanUp", UNNotificationDefaultActionIdentifier: reviewNotice()
        case "ignore": ignoreNotice()
        default: break
        }
    }

    private func registerNotificationActions() {
        // Notifications need an app bundle; renders like the marketing
        // images run Lumina's views without one.
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        let category = UNNotificationCategory(
            identifier: Self.notificationCategory,
            actions: [
                UNNotificationAction(identifier: "cleanUp", title: "Clean Up", options: [.foreground]),
                UNNotificationAction(identifier: "ignore", title: "Ignore", options: []),
            ],
            intentIdentifiers: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    private func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
    }
}
