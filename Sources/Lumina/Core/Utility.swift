import SwiftUI

/// A single focus utility shown as a module in the Lumina panel.
///
/// To add a new utility, create its module view and register it in
/// `Utility.catalog`. Its position is managed by `UtilityStore`.
struct Utility: Identifiable {
    /// How much of the panel's width a module takes.
    enum Size {
        case quarter, half, full

        /// The number of grid columns (out of four) the module spans.
        var span: Int {
            switch self {
            case .quarter: 1
            case .half: 2
            case .full: 4
            }
        }
    }

    /// Stable identifier, persisted to remember the user's ordering.
    let id: String
    let name: String
    let symbol: String
    let size: Size
    let content: @MainActor () -> AnyView
    /// The utility's settings page, if it has any.
    var settings: (@MainActor () -> AnyView)? = nil
    /// Whether the utility starts out hidden, for alternatives users can
    /// switch on in edit mode.
    var isHiddenByDefault = false
    /// Whether the user added this utility (like a world clock), so edit mode
    /// offers to remove it rather than hide it.
    var isRemovable = false
}

@MainActor
extension Utility {
    /// Every utility Lumina ships, in its default order.
    static let catalog: [Utility] = [
        .appearance,
        .caffeine,
        .stayGreen,
        .pomodoro,
        .keyboardLock,
        .quitAll,
        .systemStatus,
        .systemList,
        .cpuFocus,
    ]
}
