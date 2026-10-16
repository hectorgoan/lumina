import AppKit
import SwiftUI

/// Translucent fills for the panel's surfaces.
///
/// SwiftUI's hierarchical fills (`.fill.quaternary` and friends) are vibrant
/// on the panel's glass: they blend with what's behind the window. Anything
/// fading is drawn without that blending, so those fills turned flat and
/// dark mid-animation, then snapped back. These fixed translucent colors
/// look the same whether or not a view is fading.
extension Color {
    /// Tiles and other large surfaces, like the library.
    static let panelSurface = adaptive(dark: 0.07, light: 0.045)

    /// Smaller controls on a surface, like pills and preview bars.
    static let panelControl = adaptive(dark: 0.11, light: 0.07)

    /// Tracks, wells and inactive controls, like gauge tracks, search fields
    /// and the off state of toggle buttons.
    static let panelTrack = adaptive(dark: 0.16, light: 0.10)

    /// White over dark appearances, black over light ones, at the given
    /// opacities.
    private static func adaptive(dark: CGFloat, light: CGFloat) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(white: 1, alpha: dark)
                : NSColor(white: 0, alpha: light)
        })
    }
}
