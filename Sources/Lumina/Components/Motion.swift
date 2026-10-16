import SwiftUI

/// Lumina's animation curves, so motion feels the same everywhere.
///
/// The menu bar window resizes to fit its content, and animating that size
/// makes it redraw its glass every frame, which flickers. So changes that
/// resize the window happen instantly, and these curves animate the content
/// inside it.
enum Motion {
    /// Something arriving, like the library fading in.
    static let present = Animation.smooth(duration: 0.25)

    /// Something leaving: the same curve, a touch quicker.
    static let dismiss = Animation.smooth(duration: 0.2)

    /// The panel changing size around empty space, like making room for the
    /// library before it fades in.
    static let resize = Animation.smooth(duration: 0.25)
}

extension View {
    /// Keeps a view's colors steady while it fades.
    ///
    /// On the panel's glass, secondary text and symbols are vibrant: they
    /// blend with what's behind the window. A partly transparent view is
    /// drawn as a flattened layer, which can't blend, so a fading view
    /// switched rendering when it reached full opacity and its colors jumped.
    /// Drawing it flattened all the time keeps them the same throughout.
    /// Surfaces use the fixed `Color.panel…` fills for the same reason.
    func fadesWithoutColorShift() -> some View {
        compositingGroup()
    }
}
