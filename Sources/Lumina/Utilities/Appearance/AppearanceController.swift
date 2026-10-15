import AppKit
import Observation

/// Reads and changes the system-wide Light/Dark appearance.
///
/// macOS has no public API to change the appearance, so this goes through
/// System Events, which requires the user's Automation permission.
@MainActor
@Observable
final class AppearanceController {
    enum Mode: String, CaseIterable, Identifiable {
        case light, dark

        var id: Self { self }
        var title: String { self == .dark ? "Dark" : "Light" }
    }

    static let shared = AppearanceController()

    private(set) var mode: Mode
    private(set) var needsPermission = false
    private(set) var failed = false

    @ObservationIgnored private var isApplying = false
    @ObservationIgnored private var observation: NSKeyValueObservation?

    private init() {
        mode = Self.systemMode()
        observation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func toggle() {
        set(mode == .dark ? .light : .dark)
    }

    func set(_ newMode: Mode) {
        guard newMode != mode, !isApplying else { return }

        let previous = mode
        mode = newMode
        isApplying = true

        Task {
            let result = await Self.runAppleScript(
                "tell application \"System Events\" to tell appearance preferences to set dark mode to \(newMode == .dark)"
            )
            isApplying = false
            switch result {
            case .success:
                needsPermission = false
                failed = false
            case .notAuthorized:
                mode = previous
                needsPermission = true
            case .failed:
                mode = previous
                failed = true
            }
        }
    }

    func openAutomationSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!
        NSWorkspace.shared.open(url)
    }

    private func refresh() {
        guard !isApplying else { return }
        mode = Self.systemMode()
    }

    private static func systemMode() -> Mode {
        NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
    }

    // MARK: - AppleScript

    private enum ScriptResult { case success, notAuthorized, failed }

    /// Runs the script through `osascript` so a permission prompt never
    /// blocks the UI.
    private nonisolated static func runAppleScript(_ source: String) async -> ScriptResult {
        await withCheckedContinuation { continuation in
            let process = Process()
            let errorPipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", source]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = errorPipe
            process.terminationHandler = { process in
                guard process.terminationStatus != 0 else {
                    continuation.resume(returning: .success)
                    return
                }
                let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let message = String(decoding: data, as: UTF8.self)
                // -1743: the user denied (or hasn't granted) Automation access.
                continuation.resume(returning: message.contains("-1743") ? .notAuthorized : .failed)
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: .failed)
            }
        }
    }
}
