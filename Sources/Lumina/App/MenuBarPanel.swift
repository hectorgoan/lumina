import AppKit

/// Reaches the menu bar item SwiftUI's `MenuBarExtra` creates, which has
/// no public handle: to open the panel from elsewhere (a notification, the
/// Dumpster) and to accept apps dropped on the icon.
@MainActor
enum MenuBarPanel {
    static weak var store: UtilityStore?

    /// Kept alive here: a window only holds its delegate weakly.
    private static var dropReceiver: DropReceiver?

    /// Lumina's own item: the one without a title (world clocks show their
    /// time as a title), preferring the one whose image says "Lumina".
    static var button: NSStatusBarButton? {
        let buttons = NSApp.windows
            .filter { $0.className.contains("StatusBar") }
            .compactMap { statusButton(in: $0.contentView) }
        return buttons.first { $0.image?.accessibilityDescription?.hasPrefix("Lumina") == true }
            ?? buttons.first { $0.attributedTitle.length == 0 }
    }

    /// Opens the panel, unless it's open already.
    static func open() {
        guard store?.isPanelOpen != true else { return }
        button?.performClick(nil)
    }

    /// Lets apps be dropped on the menu bar icon to uninstall them. The item
    /// appears shortly after launch, so this retries for a few seconds.
    static func acceptDrops(attempt: Int = 0) {
        guard dropReceiver == nil else { return }
        guard let button, let window = button.window, window.delegate == nil else {
            if attempt < 10 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { acceptDrops(attempt: attempt + 1) }
            }
            return
        }
        let receiver = DropReceiver(button: button)
        window.registerForDraggedTypes([.fileURL])
        window.delegate = receiver
        dropReceiver = receiver
    }

    private static func statusButton(in view: NSView?) -> NSStatusBarButton? {
        guard let view else { return nil }
        if let button = view as? NSStatusBarButton { return button }
        for subview in view.subviews {
            if let button = statusButton(in: subview) { return button }
        }
        return nil
    }
}

/// Takes apps dropped on the menu bar item: a window passes drag messages
/// it doesn't handle itself to its delegate.
@MainActor
private final class DropReceiver: NSObject, NSWindowDelegate, NSDraggingDestination {
    private weak var button: NSStatusBarButton?

    init(button: NSStatusBarButton) {
        self.button = button
    }

    func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !apps(in: sender).isEmpty else { return [] }
        button?.highlight(true)
        return .delete
    }

    func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        apps(in: sender).isEmpty ? [] : .delete
    }

    func draggingExited(_ sender: NSDraggingInfo?) {
        button?.highlight(false)
    }

    func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = apps(in: sender)
        button?.highlight(false)
        let apps = urls.compactMap { AppCatalog.app(at: $0) }.filter { !AppCatalog.isProtected(bundleID: $0.bundleID) }
        if apps.isEmpty {
            NSSound.beep()
        } else {
            UninstallerController.shared.reviewFromOutside(apps)
        }
        return !urls.isEmpty
    }

    private func apps(in info: NSDraggingInfo) -> [URL] {
        let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return urls.filter { $0.pathExtension == "app" }
    }
}
