import AppKit
import Observation

/// Finds junk in the user's folders and removes it: app caches, developer
/// build data, logs, the Trash and, if chosen, old downloads and Mail's
/// copies of attachments.
@MainActor
@Observable
final class CleanupController {
    /// How long a scan stays fresh before opening the panel scans again.
    enum ScanInterval: Int, CaseIterable {
        case oneMinute = 60
        case fiveMinutes = 300
        case fifteenMinutes = 900
        case thirtyMinutes = 1800
        case oneHour = 3600

        /// For example "15 min".
        var title: String {
            switch self {
            case .oneMinute: "1 min"
            case .fiveMinutes: "5 min"
            case .fifteenMinutes: "15 min"
            case .thirtyMinutes: "30 min"
            case .oneHour: "1 hour"
            }
        }
    }

    enum Phase: Equatable {
        /// Not scanned yet: only while scans are manual.
        case idle
        case scanning
        case ready
        /// `progress` runs from 0 to 1.
        case cleaning(progress: Double, category: CleanupCategory)
        case done(freed: Int64)
    }

    static let shared = CleanupController()

    private(set) var phase: Phase = .idle
    /// What the last scan found, for the categories that are on.
    private(set) var findings: [CleanupCategory: CleanupFinding] = [:]
    private(set) var availableCapacity: Int64?
    private(set) var hasFullDiskAccess = true
    /// True for a moment after the first click on Clean, which then asks to
    /// be clicked again.
    private(set) var awaitsConfirmation = false

    var enabledCategories: Set<CleanupCategory> {
        didSet {
            defaults.set(enabledCategories.map(\.rawValue), forKey: Self.enabledKey)
            guard enabledCategories != oldValue else { return }
            // Newly chosen categories need scanning (unless scans are
            // manual); dropped ones just leave.
            if !enabledCategories.subtracting(oldValue).isEmpty, scansAutomatically, hasScanned {
                scan()
            } else {
                findings = findings.filter { enabledCategories.contains($0.key) }
            }
        }
    }

    /// Scans when the panel opens and the last scan is older than
    /// `scanInterval`. When off, scans only happen when the user asks.
    var scansAutomatically: Bool {
        didSet {
            defaults.set(scansAutomatically, forKey: Self.automaticKey)
            if scansAutomatically && !oldValue { refreshIfStale() }
        }
    }

    var scanInterval: ScanInterval {
        didSet { defaults.set(scanInterval.rawValue, forKey: Self.intervalKey) }
    }

    /// Leaves the caches of apps that are open alone: they'd be rebuilt
    /// right away, and removing them under a running app can upset it.
    var skipsOpenApps: Bool {
        didSet {
            defaults.set(skipsOpenApps, forKey: Self.skipKey)
            if skipsOpenApps != oldValue, scansAutomatically, hasScanned { scan() }
        }
    }

    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private let home = FileManager.default.homeDirectoryForCurrentUser
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var confirmationTask: Task<Void, Never>?
    @ObservationIgnored private var lastScan: Date?

    private static let enabledKey = "cleanup.enabledCategories"
    private static let skipKey = "cleanup.skipsOpenApps"
    private static let automaticKey = "cleanup.scansAutomatically"
    private static let intervalKey = "cleanup.scanInterval"

    private init() {
        let defaults = UserDefaults.standard
        if let saved = defaults.stringArray(forKey: Self.enabledKey) {
            enabledCategories = Set(saved.compactMap(CleanupCategory.init))
        } else {
            enabledCategories = Set(CleanupCategory.allCases.filter(\.isOnByDefault))
        }
        skipsOpenApps = defaults.object(forKey: Self.skipKey) as? Bool ?? true
        scansAutomatically = defaults.object(forKey: Self.automaticKey) as? Bool ?? true
        scanInterval = ScanInterval(rawValue: defaults.integer(forKey: Self.intervalKey)) ?? .fifteenMinutes
    }

    // MARK: - What was found

    /// The categories to clean, in display order, with what they hold.
    var cleanable: [(category: CleanupCategory, bytes: Int64)] {
        CleanupCategory.allCases.compactMap { category in
            guard enabledCategories.contains(category), let finding = findings[category],
                  !finding.isBlocked, finding.bytes > 0
            else { return nil }
            return (category, finding.bytes)
        }
    }

    var cleanableBytes: Int64 {
        cleanable.reduce(0) { $0 + $1.bytes }
    }

    // MARK: - Scanning

    /// Whether there's a scan to show (or being made) rather than nothing yet.
    var hasScanned: Bool { phase != .idle }

    /// Scans when the panel opens, unless scans are manual or the last one
    /// is still fresh.
    func refreshIfStale() {
        guard scansAutomatically else { return }
        switch phase {
        case .scanning, .cleaning: return
        case .idle, .ready, .done: break
        }
        if let lastScan, phase == .ready,
           Date.now.timeIntervalSince(lastScan) < TimeInterval(scanInterval.rawValue) { return }
        scan()
    }

    func scan() {
        if case .cleaning = phase { return }
        task?.cancel()
        cancelConfirmation()
        phase = .scanning
        let categories = CleanupCategory.allCases.filter(enabledCategories.contains)
        let open = skipsOpenApps ? Self.openBundleIDs() : nil
        let home = home
        task = Task {
            let (found, access) = await Task.detached(priority: .utility) {
                (CleanupScanner.scan(categories, home: home, skipping: open), CleanupScanner.hasFullDiskAccess(home: home))
            }.value
            guard !Task.isCancelled else { return }
            findings = found
            hasFullDiskAccess = access
            lastScan = .now
            refreshCapacity()
            phase = .ready
        }
    }

    // MARK: - Cleaning

    /// The Clean button: the first click asks for a second one, which cleans.
    func cleanTapped() {
        guard phase == .ready, cleanableBytes > 0 else { return }
        if awaitsConfirmation {
            cancelConfirmation()
            clean()
        } else {
            awaitsConfirmation = true
            confirmationTask = Task {
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { return }
                awaitsConfirmation = false
            }
        }
    }

    func stop() {
        guard case .cleaning = phase else { return }
        task?.cancel()
    }

    private func clean() {
        let work = cleanable.map { ($0.category, findings[$0.category]?.items ?? []) }
        let total = max(cleanableBytes, 1)
        let skipped = skipsOpenApps ? Self.openBundleIDs() : []
        guard let first = work.first?.0 else { return }
        phase = .cleaning(progress: 0, category: first)

        task = Task {
            var freed: Int64 = 0
            var handled: Int64 = 0
            for (category, items) in work {
                for item in items {
                    if Task.isCancelled { break }
                    // An app opened since the scan keeps its cache.
                    if category == .caches, skipped.contains(item.url.lastPathComponent) { continue }
                    freed += await Task.detached(priority: .utility) {
                        CleanupScanner.remove(item, in: category)
                    }.value
                    handled += item.bytes
                    phase = .cleaning(progress: min(1, Double(handled) / Double(total)), category: category)
                }
            }
            findings = [:]
            lastScan = nil
            refreshCapacity()
            phase = .done(freed: freed)
        }
    }

    private func cancelConfirmation() {
        confirmationTask?.cancel()
        awaitsConfirmation = false
    }

    // MARK: - System

    func openFullDiskAccessSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
        NSWorkspace.shared.open(url)
    }

    #if MARKETING
    /// Shows fixed results instead of this Mac's, for the images
    /// scripts/render-marketing.sh makes (it builds with MARKETING defined).
    func showSampleResults(_ sample: [CleanupCategory: Int64], availableCapacity: Int64) {
        task?.cancel()
        findings = sample.mapValues { bytes in
            CleanupFinding(items: [CleanupItem(url: URL(fileURLWithPath: "/sample"), bytes: bytes)])
        }
        enabledCategories = Set(sample.keys)
        hasFullDiskAccess = true
        self.availableCapacity = availableCapacity
        lastScan = .now
        phase = .ready
    }
    #endif

    private func refreshCapacity() {
        let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        availableCapacity = values?.volumeAvailableCapacityForImportantUsage
    }

    private static func openBundleIDs() -> Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }
}

enum CleanupFormat {
    /// For example "4.1 GB".
    static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }
}
