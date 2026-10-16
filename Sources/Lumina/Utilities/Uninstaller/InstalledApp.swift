import AppKit

/// An app the user can uninstall.
struct InstalledApp: Identifiable, Hashable, Sendable {
    let url: URL
    let bundleID: String
    let name: String
    let version: String?
    let vendor: String?
    /// When the user last opened it, from Spotlight; when it was added if
    /// it was never opened.
    let lastUsed: Date?
    /// The space the app bundle takes; nil until measured.
    var bytes: Int64?

    var id: String { url.path }

    @MainActor var icon: NSImage { NSWorkspace.shared.icon(forFile: url.path) }

    /// Running copies of the app.
    @MainActor var runningInstances: [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
    }
}

/// Finds the apps in /Applications and ~/Applications.
enum AppCatalog {
    /// Apps the user can't or shouldn't remove: Apple's, and Lumina itself.
    static func isProtected(bundleID: String) -> Bool {
        bundleID.hasPrefix("com.apple.") || bundleID == Bundle.main.bundleIdentifier
    }

    static var folders: [URL] {
        [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser.appending(path: "Applications", directoryHint: .isDirectory),
        ]
    }

    /// Every removable app, without sizes. Looks one folder deep too, for
    /// apps kept in folders like /Applications/Utilities.
    static func scan(sizes: [String: Int64] = [:]) -> [InstalledApp] {
        var apps: [InstalledApp] = []
        var seen = Set<String>()
        for folder in folders {
            for url in appBundles(in: folder, depth: 2) {
                guard let app = app(at: url, knownBytes: sizes[url.path]),
                      !isProtected(bundleID: app.bundleID),
                      seen.insert(app.bundleID).inserted
                else { continue }
                apps.append(app)
            }
        }
        return apps
    }

    static func app(at url: URL, knownBytes: Int64? = nil) -> InstalledApp? {
        guard let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier else { return nil }
        let info = bundle.infoDictionary ?? [:]
        let name = (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        let metadata = NSMetadataItem(url: url)
        let lastUsed = metadata?.value(forAttribute: "kMDItemLastUsedDate") as? Date
            ?? metadata?.value(forAttribute: "kMDItemDateAdded") as? Date
        return InstalledApp(
            url: url,
            bundleID: bundleID,
            name: name,
            version: info["CFBundleShortVersionString"] as? String,
            vendor: (info["NSHumanReadableCopyright"] as? String).flatMap(vendor(fromCopyright:)),
            lastUsed: lastUsed,
            bytes: knownBytes
        )
    }

    private static func appBundles(in folder: URL, depth: Int) -> [URL] {
        guard depth > 0,
              let children = try? FileManager.default.contentsOfDirectory(
                  at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
              )
        else { return [] }
        return children.flatMap { child -> [URL] in
            if child.pathExtension == "app" { return [child] }
            let isFolder = (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            return isFolder ? appBundles(in: child, depth: depth - 1) : []
        }
    }

    /// "Copyright © 2024 Docker Inc. All rights reserved." → "Docker Inc."
    private static func vendor(fromCopyright copyright: String) -> String? {
        var text = copyright
        for noise in ["Copyright", "©", "(c)", "(C)", "All rights reserved.", "All rights reserved"] {
            text = text.replacingOccurrences(of: noise, with: "")
        }
        text = text.replacingOccurrences(of: #"\b(19|20)\d\d(\s*[-–]\s*(19|20)\d\d)?\b"#, with: "", options: .regularExpression)
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: " .,;"))
        return text.isEmpty || text.count > 40 ? nil : text
    }
}

/// How long an app has gone unused, in words: "11 months ago".
enum UninstallerFormat {
    static func lastOpened(_ date: Date?) -> String {
        guard let date else { return "Never opened" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Opened " + formatter.localizedString(for: date, relativeTo: .now)
    }

    /// For the tile: "11 months".
    static func age(_ date: Date?) -> String {
        guard let date else { return "Never" }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.year, .month, .day]
        formatter.maximumUnitCount = 1
        formatter.unitsStyle = .full
        return formatter.string(from: date, to: .now) ?? ""
    }
}
