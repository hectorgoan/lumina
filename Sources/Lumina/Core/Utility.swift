import SwiftUI

/// A single focus utility shown as a module in the Lumina panel.
///
/// To add a new utility, create its module view and register it in
/// `Utility.catalog`. Its position is managed by `UtilityStore`.
struct Utility: Identifiable {
    /// Stable identifier, persisted to remember the user's ordering.
    let id: String
    let name: String
    let symbol: String
    let content: @MainActor () -> AnyView
}

@MainActor
extension Utility {
    /// Every utility Lumina ships, in its default order.
    static let catalog: [Utility] = [
        .appearance,
    ]
}
