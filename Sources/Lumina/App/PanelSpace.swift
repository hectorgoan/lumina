import AppKit
import SwiftUI

/// How much room the panel has on its screen, and how much of it goes to
/// things other than the utilities, measured as the panel lays out. The
/// grid scrolls once it would pass the bottom of the screen.
@MainActor
@Observable
final class PanelSpace {
    static let shared = PanelSpace()

    /// The panel's padding around its content.
    static let padding: CGFloat = 12
    /// Room left between the panel and the bottom of the screen.
    private static let bottomMargin: CGFloat = 16

    /// The height of the screen's visible area under the menu bar.
    private(set) var screenHeight: CGFloat = NSScreen.main?.visibleFrame.height ?? 800

    /// The footer's height, and the page dots' while they show.
    var footerHeight: CGFloat = 0
    var dotsHeight: CGFloat = 0
    /// What the grid page shows besides its tiles (the update banner, edit
    /// mode's hint).
    var gridChrome: CGFloat = 0

    @ObservationIgnored weak var window: NSWindow?

    private init() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { PanelSpace.shared.updateScreen() }
        }
    }

    /// The tallest the panel's content can be.
    var contentLimit: CGFloat {
        screenHeight - Self.bottomMargin - Self.padding * 2
    }

    /// The tallest the tiles can be before they scroll.
    var gridLimit: CGFloat {
        let dots = dotsHeight > 0 ? dotsHeight + 12 : 0
        return max(160, contentLimit - footerHeight - 12 - dots - gridChrome)
    }

    /// Reads the screen the panel is on.
    func updateScreen() {
        guard let screen = window?.screen ?? NSScreen.main else { return }
        let height = screen.visibleFrame.height
        if screenHeight != height { screenHeight = height }
    }
}

/// Hands the view's window to a closure once it has one.
struct WindowReader: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        WindowReaderView(onWindow: onWindow)
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class WindowReaderView: NSView {
        let onWindow: (NSWindow) -> Void

        init(onWindow: @escaping (NSWindow) -> Void) {
            self.onWindow = onWindow
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError() }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { onWindow(window) }
        }
    }
}
