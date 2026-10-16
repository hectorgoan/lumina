import Foundation

/// The kinds of files an app leaves around, grouped the way the review
/// page shows them.
enum LeftoverKind: String, CaseIterable, Sendable {
    case app, applicationSupport, caches, containers, preferences, launchAgents, savedState, webData, logs

    var title: String {
        switch self {
        case .app: "App"
        case .applicationSupport: "Application Support"
        case .caches: "Caches"
        case .containers: "Containers"
        case .preferences: "Preferences"
        case .launchAgents: "Launch Agents"
        case .savedState: "Saved State"
        case .webData: "Cookies & Web Data"
        case .logs: "Logs"
        }
    }

    var symbol: String {
        switch self {
        case .app: "app.fill"
        case .applicationSupport: "folder.fill"
        case .caches: "shippingbox.fill"
        case .containers: "square.stack.3d.up.fill"
        case .preferences: "gearshape.fill"
        case .launchAgents: "bolt.horizontal.fill"
        case .savedState: "macwindow"
        case .webData: "network"
        case .logs: "doc.text.fill"
        }
    }
}

/// A file or folder that belongs to an app.
struct Leftover: Identifiable, Hashable, Sendable {
    let url: URL
    let kind: LeftoverKind
    let bytes: Int64

    var id: String { url.path }
}

/// Files whose app is gone: what "Left Behind" lists.
struct LeftBehindApp: Identifiable, Hashable, Sendable {
    let bundleID: String
    let name: String
    let items: [Leftover]

    var id: String { bundleID }
    var bytes: Int64 { items.reduce(0) { $0 + $1.bytes } }
}

/// Finds the files apps keep in the user's Library. Matches only exact
/// names (the app's bundle ID or name), never partial ones, so another
/// app's files are never swept up.
enum LeftoverFinder {
    /// Where apps keep their files, and how each place names them.
    private struct Place: Sendable {
        let path: String
        let kind: LeftoverKind
        /// Turns an entry's file name into the name to match against.
        var key: @Sendable (String) -> String = { $0 }
    }

    private static let places: [Place] = [
        Place(path: "Library/Application Support", kind: .applicationSupport),
        Place(path: "Library/Caches", kind: .caches, key: { $0.replacingOccurrences(of: ".ShipIt", with: "") }),
        Place(path: "Library/Containers", kind: .containers),
        Place(path: "Library/Application Scripts", kind: .containers),
        Place(path: "Library/Preferences", kind: .preferences, key: { strip($0, ".plist") }),
        Place(path: "Library/Preferences/ByHost", kind: .preferences, key: { byHostKey($0) }),
        Place(path: "Library/LaunchAgents", kind: .launchAgents, key: { strip($0, ".plist") }),
        Place(path: "Library/Saved Application State", kind: .savedState, key: { strip($0, ".savedState") }),
        Place(path: "Library/HTTPStorages", kind: .webData, key: { strip($0, ".binarycookies") }),
        Place(path: "Library/WebKit", kind: .webData),
        Place(path: "Library/Cookies", kind: .webData, key: { strip($0, ".binarycookies") }),
        Place(path: "Library/Logs", kind: .logs),
    ]

    /// Everything an installed app has in the user's Library.
    static func leftovers(bundleID: String, name: String, home: URL) -> [Leftover] {
        let names: Set<String> = [bundleID.lowercased(), name.lowercased()]
        var found: [Leftover] = []
        for place in places {
            for entry in entries(in: home.appending(path: place.path)) {
                let key = place.key(entry.lastPathComponent).lowercased()
                // Launch agents are often named after the app with a suffix
                // ("com.vendor.app.helper.plist").
                let matches = names.contains(key)
                    || (place.kind == .launchAgents && key.hasPrefix(bundleID.lowercased() + "."))
                if matches {
                    found.append(Leftover(url: entry, kind: place.kind, bytes: CleanupScanner.size(of: entry)))
                }
            }
        }
        // Group containers: "<team ID>.<bundle ID>", an exact match only, as
        // suites share broader ones between their apps.
        for entry in entries(in: home.appending(path: "Library/Group Containers"))
        where entry.lastPathComponent.lowercased().hasSuffix("." + bundleID.lowercased())
            && entry.lastPathComponent.count == bundleID.count + 11 {
            found.append(Leftover(url: entry, kind: .containers, bytes: CleanupScanner.size(of: entry)))
        }
        return found
    }

    /// Files named after a bundle ID whose app isn't installed. Apple's own
    /// files are skipped, and so is anything sharing a vendor with an
    /// installed app ("com.docker.helper" while Docker is installed), since
    /// helpers often aren't apps themselves. Containers aren't checked:
    /// macOS asks before letting one app look inside another's.
    static func leftBehind(home: URL, installedBundleIDs: Set<String>, minimumBytes: Int64 = 1_000_000) -> [LeftBehindApp] {
        let installed = Set(installedBundleIDs.map { $0.lowercased() })
        let vendors = Set(installed.map(vendor))
        var byBundleID: [String: [Leftover]] = [:]

        for place in places where place.kind != .containers {
            for entry in entries(in: home.appending(path: place.path)) {
                let key = place.key(entry.lastPathComponent)
                let lowered = key.lowercased()
                guard isBundleID(key),
                      !lowered.hasPrefix("com.apple."),
                      !installed.contains(lowered),
                      !vendors.contains(vendor(lowered))
                else { continue }
                byBundleID[lowered, default: []].append(Leftover(url: entry, kind: place.kind, bytes: CleanupScanner.size(of: entry)))
            }
        }

        return byBundleID
            .map { LeftBehindApp(bundleID: $0.key, name: displayName(forBundleID: $0.key), items: $0.value) }
            .filter { $0.bytes >= minimumBytes }
            .sorted { $0.bytes > $1.bytes }
    }

    // MARK: - Helpers

    private static func entries(in folder: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [])) ?? []
    }

    private static func strip(_ name: String, _ suffix: String) -> String {
        name.hasSuffix(suffix) ? String(name.dropLast(suffix.count)) : name
    }

    /// "com.vendor.app.<host UUID>.plist" → "com.vendor.app".
    private static func byHostKey(_ name: String) -> String {
        let parts = strip(name, ".plist").split(separator: ".")
        return parts.count > 1 ? parts.dropLast().joined(separator: ".") : name
    }

    /// Reverse-DNS names like "com.spotify.client".
    private static func isBundleID(_ name: String) -> Bool {
        name.range(of: #"^[A-Za-z0-9-]+(\.[A-Za-z0-9_-]+){2,}$"#, options: .regularExpression) != nil
    }

    /// "com.docker.docker" → "com.docker".
    private static func vendor(_ bundleID: String) -> String {
        bundleID.split(separator: ".").prefix(2).joined(separator: ".")
    }

    /// A readable name for a bundle ID: "com.spotify.client" → "Spotify".
    static func displayName(forBundleID bundleID: String) -> String {
        let generic: Set<String> = ["client", "app", "desktop", "mac", "macos", "osx", "xos", "helper", "agent", "main"]
        let parts = bundleID.split(separator: ".").map(String.init).dropFirst()
        let name = parts.reversed().first { !generic.contains($0.lowercased()) } ?? parts.last ?? bundleID
        return name.prefix(1).uppercased() + name.dropFirst()
    }
}
