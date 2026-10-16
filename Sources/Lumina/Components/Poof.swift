import AppKit

/// The puff of smoke macOS shows when you drag an item off the Dock.
///
/// AppKit's `NSShowAnimationEffect` still plays it, but has been deprecated
/// since macOS 14 with no replacement for the animation. It's looked up at
/// runtime, so the build stays free of deprecation warnings and, if it's
/// ever removed, callers can fall back to a plain fade.
@MainActor
enum Poof {
    private typealias ShowAnimationEffect = @convention(c) (
        UInt, CGPoint, CGSize, AnyObject?, OpaquePointer?, UnsafeMutableRawPointer?
    ) -> Void

    /// `NSAnimationEffectPoof`.
    private static let poofEffect: UInt = 10

    private static let showAnimationEffect: ShowAnimationEffect? = {
        guard let handle = dlopen("/System/Library/Frameworks/AppKit.framework/AppKit", RTLD_NOW),
              let symbol = dlsym(handle, "NSShowAnimationEffect")
        else { return nil }
        return unsafeBitCast(symbol, to: ShowAnimationEffect.self)
    }()

    /// Plays the poof over a rectangle in a window's SwiftUI global
    /// coordinates (origin at the top left of its content). Returns false if
    /// it couldn't be played.
    @discardableResult
    static func show(over rect: CGRect, in window: NSWindow?) -> Bool {
        guard let showAnimationEffect, let window, let contentView = window.contentView else { return false }

        // SwiftUI measures from the top; AppKit windows from the bottom.
        let inWindow = NSPoint(x: rect.midX, y: contentView.frame.height - rect.midY)
        let onScreen = window.convertPoint(toScreen: inWindow)
        // About the size of the Dock's poof for an icon this big.
        let side = min(max(min(rect.width, rect.height) * 1.2, 72), 120)

        showAnimationEffect(poofEffect, onScreen, CGSize(width: side, height: side), nil, nil, nil)
        return true
    }
}
