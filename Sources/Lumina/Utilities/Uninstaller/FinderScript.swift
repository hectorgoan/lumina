import Foundation

/// Asks Finder to do what an app can't do itself. macOS keeps apps from
/// changing or removing other apps (App Management), so an app bundle can
/// stay put when Lumina moves it to the Trash. Finder may, asking for an
/// administrator password when needed. Runs through `osascript` so a
/// permission prompt never blocks the UI; the first use asks to let Lumina
/// control Finder.
enum FinderScript {
    /// Moves a file to the Trash; returns where it went.
    static func trash(_ url: URL) async -> URL? {
        let output = await run("""
            set theItem to POSIX file "\(escaped(url.path))" as alias
            tell application "Finder" to set trashed to delete theItem
            return POSIX path of (trashed as alias)
            """)
        return output.map { URL(fileURLWithPath: $0) }
    }

    /// Moves a file into a folder.
    static func move(_ url: URL, into folder: URL) async -> Bool {
        await run("""
            tell application "Finder" to move (POSIX file "\(escaped(url.path))" as alias) to (POSIX file "\(escaped(folder.path))" as alias)
            """) != nil
    }

    /// Empties the Trash, everything in it.
    static func emptyTrash() async -> Bool {
        await run(#"tell application "Finder" to empty trash"#) != nil
    }

    private static func escaped(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Runs a script; its output, or nil if it failed.
    private static func run(_ source: String) async -> String? {
        await withCheckedContinuation { continuation in
            let process = Process()
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", source]
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { process in
                let data = output.fileHandleForReading.readDataToEndOfFile()
                let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.resume(returning: process.terminationStatus == 0 ? text : nil)
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }
}
