import Foundation

/// Something Cleanup found: a file or folder, and the space it takes.
struct CleanupItem: Sendable {
    let url: URL
    let bytes: Int64
}

/// What a scan found for one category.
struct CleanupFinding: Sendable {
    var items: [CleanupItem] = []
    /// macOS didn't let Lumina look: the category needs Full Disk Access.
    var isBlocked = false
    /// Left alone because an app that uses it is open.
    var isInUse = false

    var bytes: Int64 { items.reduce(0) { $0 + $1.bytes } }
}

/// Finds and removes junk. Runs off the main actor: walking a few gigabytes
/// of caches takes seconds.
enum CleanupScanner {
    /// Scans the given categories. `openBundleIDs` lists apps that are open,
    /// whose data is skipped; pass nil to include everything.
    static func scan(
        _ categories: [CleanupCategory],
        home: URL,
        skipping openBundleIDs: Set<String>?,
        now: Date = .now
    ) -> [CleanupCategory: CleanupFinding] {
        var findings: [CleanupCategory: CleanupFinding] = [:]
        for category in categories {
            if Task.isCancelled { break }
            var finding = CleanupFinding()
            if let openBundleIDs, !category.ownerBundleIDs.isDisjoint(with: openBundleIDs) {
                finding.isInUse = true
                findings[category] = finding
                continue
            }
            for folder in category.folders(in: home) {
                if Task.isCancelled { break }
                switch children(of: folder) {
                case .missing:
                    continue
                case .blocked:
                    finding.isBlocked = true
                case .found(let children):
                    for child in children where shouldInclude(child, in: category, skipping: openBundleIDs, now: now) {
                        if Task.isCancelled { break }
                        finding.items.append(CleanupItem(url: child, bytes: size(of: child)))
                    }
                }
            }
            findings[category] = finding
        }
        return findings
    }

    /// Removes an item, returning the space it freed. Items that can only
    /// be partly removed (some files belong to the system) free what they can.
    static func remove(_ item: CleanupItem, in category: CleanupCategory) -> Int64 {
        let fileManager = FileManager.default
        do {
            if category.movesToTrash {
                try fileManager.trashItem(at: item.url, resultingItemURL: nil)
            } else {
                try fileManager.removeItem(at: item.url)
            }
            return item.bytes
        } catch {
            let left = fileManager.fileExists(atPath: item.url.path) ? size(of: item.url) : 0
            return max(0, item.bytes - left)
        }
    }

    /// Whether this Mac lets Lumina read folders that need Full Disk Access.
    static func hasFullDiskAccess(home: URL) -> Bool {
        if case .blocked = children(of: home.appending(path: ".Trash", directoryHint: .isDirectory)) {
            return false
        }
        return true
    }

    // MARK: - Helpers

    private enum Listing {
        case missing, blocked
        case found([URL])
    }

    private static let listingKeys: [URLResourceKey] = [.addedToDirectoryDateKey, .creationDateKey]

    private static func children(of folder: URL) -> Listing {
        do {
            let children = try FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: listingKeys,
                options: []
            )
            return .found(children)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return .missing
        } catch let error as CocoaError where error.code == .fileReadNoPermission {
            return .blocked
        } catch {
            return .missing
        }
    }

    private static func shouldInclude(
        _ child: URL,
        in category: CleanupCategory,
        skipping openBundleIDs: Set<String>?,
        now: Date
    ) -> Bool {
        let name = child.lastPathComponent
        // Finder's folder settings, not junk.
        if name == ".DS_Store" && category != .trash { return false }
        switch category {
        case .caches:
            // Cache folders are named after their app's bundle ID. Lumina's
            // own cache is never cleaned while it runs.
            if name == Bundle.main.bundleIdentifier { return false }
            if let openBundleIDs, openBundleIDs.contains(name) { return false }
            return true
        case .downloads:
            let values = try? child.resourceValues(forKeys: Set(listingKeys))
            guard let added = values?.addedToDirectoryDate ?? values?.creationDate else { return false }
            return now.timeIntervalSince(added) > CleanupCategory.oldDownloadAge
        default:
            return true
        }
    }

    private static let sizeKeys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isDirectoryKey]

    /// The space a file or folder takes on disk.
    static func size(of url: URL) -> Int64 {
        func allocated(_ values: URLResourceValues?) -> Int64 {
            Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
        }
        let values = try? url.resourceValues(forKeys: sizeKeys)
        guard values?.isDirectory == true else { return allocated(values) }

        var total: Int64 = 0
        let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Array(sizeKeys),
            options: [],
            errorHandler: { _, _ in true }
        )
        while let file = enumerator?.nextObject() as? URL {
            if Task.isCancelled { break }
            total += allocated(try? file.resourceValues(forKeys: sizeKeys))
        }
        return total
    }
}
