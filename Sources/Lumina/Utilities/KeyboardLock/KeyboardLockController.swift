import AppKit
import ApplicationServices
import Observation

/// Swallows all keyboard input while locked, so the keyboard can be cleaned.
///
/// Uses an event tap, which needs Accessibility permission. Mouse and
/// trackpad input keep working, so the lock can always be lifted from the
/// panel; quitting Lumina lifts it too.
@MainActor
@Observable
final class KeyboardLockController {
    static let shared = KeyboardLockController()

    private(set) var isLocked = false
    private(set) var needsPermission = false

    @ObservationIgnored private let tapBox = TapBox()
    @ObservationIgnored private var runLoopSource: CFRunLoopSource?

    private init() {}

    func toggle() {
        isLocked ? unlock() : lock()
    }

    private func lock() {
        // The first attempt shows macOS's own prompt; later ones go straight
        // to the Accessibility settings.
        guard Self.isTrusted(prompt: !needsPermission) else {
            if needsPermission {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
            needsPermission = true
            return
        }

        let mask: CGEventMask = [CGEventType.keyDown, .keyUp, .flagsChanged]
            .reduce(1 << systemDefinedEventType) { $0 | (1 << $1.rawValue) }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: swallowKeyboardEvent,
            userInfo: Unmanaged.passUnretained(tapBox).toOpaque()
        ) else {
            needsPermission = true
            return
        }

        tapBox.tap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        needsPermission = false
        isLocked = true
    }

    private func unlock() {
        if let tap = tapBox.tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tapBox.tap = nil
        runLoopSource = nil
        isLocked = false
    }

    private static func isTrusted(prompt: Bool) -> Bool {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": prompt] as CFDictionary)
    }
}

/// `NX_SYSDEFINED`: carries media, volume and brightness keys.
private let systemDefinedEventType: UInt32 = 14

/// Lets the C callback reach the tap to re-enable it.
private final class TapBox {
    var tap: CFMachPort?
}

/// The event tap callback: drops keyboard events and lets everything else through.
private func swallowKeyboardEvent(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        // macOS switches slow taps off; keep the lock in force.
        if let userInfo, let tap = Unmanaged<TapBox>.fromOpaque(userInfo).takeUnretainedValue().tap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return Unmanaged.passUnretained(event)

    case .keyDown, .keyUp, .flagsChanged:
        return nil

    default:
        // System-defined events also carry mouse button state; only drop the
        // media and special keys (subtype 8, NX_SUBTYPE_AUX_CONTROL_BUTTONS).
        if type.rawValue == systemDefinedEventType,
           NSEvent(cgEvent: event)?.subtype.rawValue == 8 {
            return nil
        }
        return Unmanaged.passUnretained(event)
    }
}
