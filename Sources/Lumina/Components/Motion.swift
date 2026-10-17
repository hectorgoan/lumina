import SwiftUI

/// Lumina's animation curves, so motion feels the same everywhere.
///
/// The menu bar window resizes to fit its content, and animating that size
/// makes it redraw its glass every frame, which flickers. So changes that
/// resize the window happen instantly, and these curves animate the content
/// inside it.
enum Motion {
    /// Something arriving, like the library fading in. A spring, which
    /// settles naturally; nothing waits for it to finish.
    static let present = Animation.smooth(duration: 0.25)

    // The next two hand off to the following step when they finish, so they
    // use fixed-length curves. A spring's tail keeps settling well past its
    // nominal duration, which left the panel sitting empty between steps.

    /// Something leaving.
    static let dismiss = Animation.easeInOut(duration: dismissDuration)
    static let dismissDuration: TimeInterval = 0.16

    /// The panel changing size around empty space, like making room for the
    /// library before it fades in.
    static let resize = Animation.easeInOut(duration: resizeDuration)
    static let resizeDuration: TimeInterval = 0.22

    /// Runs one animated step of a transition, then `completion` once
    /// SwiftUI reports the step done, or once its curve has run if it
    /// doesn't (something animating endlessly nearby can keep it from ever
    /// reporting).
    @MainActor
    static func step(_ animation: Animation, lasting duration: TimeInterval, _ change: () -> Void, completion: @escaping @MainActor () -> Void) {
        let once = StepCompletion(completion)
        withAnimation(animation, completionCriteria: .removed, change) { once.run() }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(duration + 0.05))
            once.run()
        }
    }

    /// Shows or hides something whose arrival or departure resizes the
    /// panel, in the panel's steps: it fades out before its room closes,
    /// and its room opens before it fades in. `isShown` sets its room,
    /// `isVisible` its opacity.
    @MainActor
    static func stage(_ show: Bool, isShown: @escaping @MainActor (Bool) -> Void, isVisible: @escaping @MainActor (Bool) -> Void) {
        if show {
            step(resize, lasting: resizeDuration, { isShown(true) }) {
                withAnimation(present) { isVisible(true) }
            }
        } else {
            step(dismiss, lasting: dismissDuration, { isVisible(false) }) {
                withAnimation(resize) { isShown(false) }
            }
        }
    }
}

/// Something that comes and goes in a tile and changes its height (and so
/// the panel's), staged as `Motion.stage` describes. The first value is
/// applied as is.
@MainActor
final class RevealStage: ObservableObject {
    /// Whether it takes up room.
    @Published private(set) var isShown = false
    /// Whether it can be seen.
    @Published private(set) var isVisible = false
    private var target: Bool?

    func set(_ show: Bool) {
        guard let target else {
            target = show
            isShown = show
            isVisible = show
            return
        }
        guard show != target else { return }
        self.target = show
        Motion.stage(show) { [weak self] shown in
            guard let self, self.target == show else { return }
            self.isShown = shown
        } isVisible: { [weak self] visible in
            guard let self, self.target == show else { return }
            self.isVisible = visible
        }
    }
}

/// Swaps one thing for another of a different height, in the panel's
/// steps: the old fades out, the room changes, the new fades in. The
/// first value is applied as is.
@MainActor
final class SwapStage<Value: Equatable>: ObservableObject {
    /// What's laid out now.
    @Published private(set) var value: Value?
    /// Whether it can be seen.
    @Published private(set) var isVisible = true
    private var target: Value?

    func set(_ newValue: Value) {
        guard value != nil else {
            value = newValue
            target = newValue
            return
        }
        guard newValue != target else { return }
        target = newValue
        Motion.step(Motion.dismiss, lasting: Motion.dismissDuration, { isVisible = false }) {
            Motion.step(Motion.resize, lasting: Motion.resizeDuration, { self.value = self.target }) {
                withAnimation(Motion.present) { self.isVisible = true }
            }
        }
    }
}

/// Runs a step's completion only once, whichever signal comes first.
@MainActor
private final class StepCompletion {
    private var action: (@MainActor () -> Void)?

    init(_ action: @escaping @MainActor () -> Void) {
        self.action = action
    }

    func run() {
        let action = action
        self.action = nil
        action?()
    }
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
