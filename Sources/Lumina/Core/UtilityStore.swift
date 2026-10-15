import SwiftUI

/// Owns the ordered list of utilities and the panel's edit state.
@MainActor
@Observable
final class UtilityStore {
    private static let orderKey = "utilityOrder"

    var utilities: [Utility] {
        didSet { defaults.set(utilities.map(\.id), forKey: Self.orderKey) }
    }

    var isEditing = false

    @ObservationIgnored private let defaults: UserDefaults

    init(catalog: [Utility] = Utility.catalog, defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // Restore the saved order, dropping utilities that no longer exist and
        // appending newly added ones at the end.
        let savedOrder = defaults.stringArray(forKey: Self.orderKey) ?? []
        let byID = Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0) })
        let restored = savedOrder.compactMap { byID[$0] }
        let added = catalog.filter { !savedOrder.contains($0.id) }
        utilities = restored + added
    }
}
