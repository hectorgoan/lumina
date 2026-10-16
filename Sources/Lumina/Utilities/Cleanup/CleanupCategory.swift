import Foundation

/// A kind of junk Cleanup can remove. Everything lives in the user's own
/// folders: anything system-wide would need administrator rights.
enum CleanupCategory: String, CaseIterable, Sendable {
    case caches, developer, trash, logs, downloads, mail

    var name: String {
        switch self {
        case .caches: "App Caches"
        case .developer: "Developer Junk"
        case .trash: "Trash"
        case .logs: "Logs & Crash Reports"
        case .downloads: "Old Downloads"
        case .mail: "Mail Attachments"
        }
    }

    /// A one-word name for the tile's legend.
    var shortName: String {
        switch self {
        case .caches: "Caches"
        case .developer: "Developer"
        case .trash: "Trash"
        case .logs: "Logs"
        case .downloads: "Downloads"
        case .mail: "Mail"
        }
    }

    var detail: String {
        switch self {
        case .caches: "~/Library/Caches"
        case .developer: "Xcode build data, npm, Gradle"
        case .trash: "Empties the Trash"
        case .logs: "~/Library/Logs"
        case .downloads: "Older than 30 days, to the Trash"
        case .mail: "Downloaded copies of attachments"
        }
    }

    var symbol: String {
        switch self {
        case .caches: "shippingbox.fill"
        case .developer: "hammer.fill"
        case .trash: "trash.fill"
        case .logs: "doc.text.fill"
        case .downloads: "arrow.down.circle.fill"
        case .mail: "paperclip"
        }
    }

    /// Cleaned unless the user turns it off. Downloads and Mail hold files
    /// people may still want, so they start off.
    var isOnByDefault: Bool {
        switch self {
        case .caches, .developer, .trash, .logs: true
        case .downloads, .mail: false
        }
    }

    /// Whether macOS only lets apps with Full Disk Access read it.
    var needsFullDiskAccess: Bool {
        self == .trash || self == .mail
    }

    /// Old downloads go to the Trash rather than away for good: they're the
    /// user's files, not junk an app can rebuild.
    var movesToTrash: Bool { self == .downloads }

    /// Downloads added longer ago than this count as old.
    static let oldDownloadAge: TimeInterval = 30 * 24 * 60 * 60

    /// The folders whose contents this category removes.
    func folders(in home: URL) -> [URL] {
        func path(_ components: String) -> URL { home.appending(path: components, directoryHint: .isDirectory) }
        switch self {
        case .caches:
            return [path("Library/Caches")]
        case .developer:
            return [
                path("Library/Developer/Xcode/DerivedData"),
                path("Library/Developer/Xcode/iOS DeviceSupport"),
                path("Library/Developer/Xcode/watchOS DeviceSupport"),
                path("Library/Developer/Xcode/tvOS DeviceSupport"),
                path("Library/Developer/Xcode/visionOS DeviceSupport"),
                path("Library/Developer/CoreSimulator/Caches"),
                path(".npm/_cacache"),
                path(".gradle/caches"),
            ]
        case .trash:
            return [path(".Trash")]
        case .logs:
            return [path("Library/Logs")]
        case .downloads:
            return [path("Downloads")]
        case .mail:
            return [path("Library/Containers/com.apple.mail/Data/Library/Mail Downloads")]
        }
    }

    /// Apps whose data this category holds, so it's left alone while one
    /// of them is open. Caches are matched per folder instead.
    var ownerBundleIDs: Set<String> {
        switch self {
        case .developer: ["com.apple.dt.Xcode", "com.apple.iphonesimulator", "com.google.android.studio"]
        case .mail: ["com.apple.mail"]
        default: []
        }
    }
}
