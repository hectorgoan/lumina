import AppKit
import CoreAudio
import Observation

/// An action that asks for a second click before it runs, for things that
/// are hard to undo: the first click arms it for a few seconds.
@MainActor
@Observable
final class TwoStepAction {
    private(set) var awaitsConfirmation = false
    @ObservationIgnored private var timeout: Task<Void, Never>?

    /// Arms the action, or runs it if it's armed already.
    func tap(_ perform: () -> Void) {
        if awaitsConfirmation {
            reset()
            perform()
        } else {
            awaitsConfirmation = true
            timeout = Task {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                awaitsConfirmation = false
            }
        }
    }

    func reset() {
        timeout?.cancel()
        awaitsConfirmation = false
    }
}

// MARK: - Sleep

/// Puts the Mac to sleep, after a second click.
@MainActor
@Observable
final class SleepController {
    static let shared = SleepController()

    let confirmation = TwoStepAction()

    private init() {}

    func tap() {
        confirmation.tap {
            // `pmset sleepnow` needs no administrator rights or permission.
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
            process.arguments = ["sleepnow"]
            try? process.run()
        }
    }
}

// MARK: - Silence

/// Mutes the Mac's sound output, and follows mute changes made elsewhere
/// (the keyboard, Control Center) and switches of the output device.
@MainActor
@Observable
final class SilenceController {
    static let shared = SilenceController()

    private(set) var isSilenced = false
    /// Whether the current output device can be muted at all; some (like
    /// many HDMI displays) can't.
    private(set) var isAvailable = true

    @ObservationIgnored private var device: AudioObjectID?
    @ObservationIgnored private var muteListener: AudioObjectPropertyListenerBlock?

    private static var defaultDeviceAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    private static var muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )

    private init() {
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &Self.defaultDeviceAddress, .main) { _, _ in
            MainActor.assumeIsolated { SilenceController.shared.followDefaultDevice() }
        }
        followDefaultDevice()
    }

    func toggle() {
        guard let device, isAvailable else { return }
        var value: UInt32 = isSilenced ? 0 : 1
        let status = AudioObjectSetPropertyData(device, &Self.muteAddress, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
        if status == noErr { isSilenced = value == 1 }
    }

    /// Watches the current output device's mute setting.
    private func followDefaultDevice() {
        if let device, let muteListener {
            AudioObjectRemovePropertyListenerBlock(device, &Self.muteAddress, .main, muteListener)
        }
        muteListener = nil
        device = Self.defaultOutputDevice()

        guard let device else {
            isAvailable = false
            return
        }
        var settable: DarwinBoolean = false
        isAvailable = AudioObjectHasProperty(device, &Self.muteAddress)
            && AudioObjectIsPropertySettable(device, &Self.muteAddress, &settable) == noErr
            && settable.boolValue
        readMute()

        let listener: AudioObjectPropertyListenerBlock = { _, _ in
            MainActor.assumeIsolated { SilenceController.shared.readMute() }
        }
        AudioObjectAddPropertyListenerBlock(device, &Self.muteAddress, .main, listener)
        muteListener = listener
    }

    private func readMute() {
        guard let device else { return }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        if AudioObjectGetPropertyData(device, &Self.muteAddress, 0, nil, &size, &value) == noErr {
            isSilenced = value == 1
        }
    }

    private static func defaultOutputDevice() -> AudioObjectID? {
        var device = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &defaultDeviceAddress, 0, nil, &size, &device)
        return status == noErr && device != 0 ? device : nil
    }
}

// MARK: - Empty Trash

/// Empties the Trash through Finder, after a second click, and shows how
/// much is in it when Lumina can look (the Trash needs Full Disk Access).
@MainActor
@Observable
final class EmptyTrashController {
    static let shared = EmptyTrashController()

    let confirmation = TwoStepAction()
    /// What the Trash holds, or nil when Lumina can't look inside.
    private(set) var trashBytes: Int64?
    private(set) var isEmptying = false
    private(set) var failed = false

    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    private init() {}

    private static var trashURL: URL {
        FileManager.default.urls(for: .trashDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: ".Trash", directoryHint: .isDirectory)
    }

    func refresh() {
        refreshTask?.cancel()
        let url = Self.trashURL
        refreshTask = Task {
            let bytes = await Task.detached(priority: .utility) { () -> Int64? in
                guard let items = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) else {
                    return nil
                }
                return items.reduce(0) { $0 + CleanupScanner.size(of: $1) }
            }.value
            guard !Task.isCancelled else { return }
            trashBytes = bytes
        }
    }

    func tap() {
        guard !isEmptying else { return }
        failed = false
        confirmation.tap {
            isEmptying = true
            Task {
                let emptied = await FinderScript.emptyTrash()
                isEmptying = false
                failed = !emptied
                refresh()
            }
        }
    }
}
