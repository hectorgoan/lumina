import AppKit
import ApplicationServices

/// Opens the panel from elsewhere (the Dumpster, a notification). SwiftUI's
/// `MenuBarExtra` has no way to open it, and on macOS 26 the system owns
/// menu bar items and delivers their clicks, so neither calling the item's
/// button nor sending it events works. What does is a real click: this
/// finds Lumina's item through the accessibility API and clicks it, then
/// puts the pointer back. That needs the Accessibility permission (which
/// Keyboard Lock uses too).
@MainActor
enum MenuBarPanel {
    static weak var store: UtilityStore?

    /// Whether Lumina may click its own menu bar item.
    static var canOpen: Bool { AXIsProcessTrusted() }

    /// Opens the panel unless it's open already. Returns whether it did.
    @discardableResult
    static func open() -> Bool {
        guard store?.isPanelOpen != true else { return true }
        guard canOpen, let item = luminaItem() else { return false }
        return click(item)
    }

    /// Asks for the Accessibility permission, showing macOS's prompt.
    static func requestPermission() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Lumina's own menu bar item: titled "Lumina", unlike world clocks.
    private static func luminaItem() -> AXUIElement? {
        var extras: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(getpid()), kAXExtrasMenuBarAttribute as CFString, &extras) == .success,
              let extras, CFGetTypeID(extras) == AXUIElementGetTypeID()
        else { return nil }
        var children: CFTypeRef?
        AXUIElementCopyAttributeValue(extras as! AXUIElement, kAXChildrenAttribute as CFString, &children)
        return (children as? [AXUIElement] ?? []).first { element in
            var title: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &title)
            return (title as? String)?.hasPrefix("Lumina") == true
        }
    }

    /// Clicks the middle of an element with a real (posted) mouse click,
    /// then puts the pointer back where it was.
    private static func click(_ element: AXUIElement) -> Bool {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue
        else { return false }
        var position = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        let target = CGPoint(x: position.x + size.width / 2, y: position.y + size.height / 2)

        let original = CGEvent(source: nil)?.location ?? target
        let source = CGEventSource(stateID: .hidSystemState)
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: target, mouseButton: .left)?
                .post(tap: .cghidEventTap)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { CGWarpMouseCursorPosition(original) }
        return true
    }
}
