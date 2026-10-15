import SwiftUI

/// Owns the ordered list of utilities, which ones are hidden, the world
/// clocks the user added, and the panel's edit state.
@MainActor
@Observable
final class UtilityStore {
    private static let orderKey = "utilityOrder"
    private static let hiddenKey = "hiddenUtilities"
    private static let worldClocksKey = "worldClocks"

    /// Every utility in display order. Hidden utilities always come after
    /// the visible ones.
    private(set) var utilities: [Utility] {
        didSet { defaults.set(utilities.map(\.id), forKey: Self.orderKey) }
    }

    private(set) var hiddenIDs: Set<String> {
        didSet { defaults.set(Array(hiddenIDs), forKey: Self.hiddenKey) }
    }

    private(set) var worldClocks: [WorldClock] {
        didSet { defaults.set(try? JSONEncoder().encode(worldClocks), forKey: Self.worldClocksKey) }
    }

    var isEditing = false {
        didSet {
            if !isEditing {
                settingsUtilityID = nil
                isAddingWorldClock = false
            }
        }
    }

    /// The utility whose settings page is open, if any.
    var settingsUtilityID: String?

    /// Whether the world clock city picker is open.
    var isAddingWorldClock = false

    @ObservationIgnored private let defaults: UserDefaults

    init(catalog: [Utility] = Utility.catalog, defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // Restore the saved order, dropping utilities that no longer exist and
        // appending newly added ones at the end. Newly added utilities that
        // are hidden by default start out hidden.
        let clocks = defaults.data(forKey: Self.worldClocksKey)
            .flatMap { try? JSONDecoder().decode([WorldClock].self, from: $0) } ?? []
        worldClocks = clocks
        let all = catalog + clocks.compactMap(Utility.worldClock)

        let savedOrder = defaults.stringArray(forKey: Self.orderKey) ?? []
        let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        let restored = savedOrder.compactMap { byID[$0] }
        let added = all.filter { !savedOrder.contains($0.id) }

        let savedHidden = Set(defaults.stringArray(forKey: Self.hiddenKey) ?? []).intersection(byID.keys)
        let hidden = savedHidden.union(added.filter(\.isHiddenByDefault).map(\.id))
        hiddenIDs = hidden
        utilities = Self.partitioned(restored + added, hidden: hidden)

        // Save right away, so utilities hidden by default stay as the user
        // leaves them on later launches.
        defaults.set(utilities.map(\.id), forKey: Self.orderKey)
        defaults.set(Array(hidden), forKey: Self.hiddenKey)
    }

    /// The utilities shown outside edit mode.
    var visibleUtilities: [Utility] {
        utilities.filter { !hiddenIDs.contains($0.id) }
    }

    var settingsUtility: Utility? {
        utilities.first { $0.id == settingsUtilityID }
    }

    func isHidden(_ utility: Utility) -> Bool {
        hiddenIDs.contains(utility.id)
    }

    /// Applies a new order, keeping hidden utilities after the visible ones.
    func reorder(_ newOrder: [Utility]) {
        let ordered = Self.partitioned(newOrder, hidden: hiddenIDs)
        guard ordered.map(\.id) != utilities.map(\.id) else { return }
        utilities = ordered
    }

    /// Hiding moves a utility to the very bottom; showing it again places it
    /// right after the other visible ones.
    func toggleVisibility(of utility: Utility) {
        var others = utilities.filter { $0.id != utility.id }
        if hiddenIDs.contains(utility.id) {
            hiddenIDs.remove(utility.id)
            let insertionIndex = others.firstIndex { hiddenIDs.contains($0.id) } ?? others.endIndex
            others.insert(utility, at: insertionIndex)
        } else {
            hiddenIDs.insert(utility.id)
            others.append(utility)
        }
        utilities = others
    }

    // MARK: - World clocks

    /// Adds a clock for the city after the visible utilities and closes the
    /// picker.
    func addWorldClock(for city: WorldClockCity) {
        let clock = WorldClock(id: "worldClock-\(UUID().uuidString)", cityCode: city.code)
        guard let utility = Utility.worldClock(clock) else { return }
        worldClocks.append(clock)
        var updated = utilities
        let insertionIndex = updated.firstIndex { hiddenIDs.contains($0.id) } ?? updated.endIndex
        updated.insert(utility, at: insertionIndex)
        utilities = updated
        isAddingWorldClock = false
    }

    func worldClock(withID id: String) -> WorldClock? {
        worldClocks.first { $0.id == id }
    }

    func setMenuBarDisplay(_ display: WorldClock.MenuBarDisplay, forClockWithID id: String) {
        guard let index = worldClocks.firstIndex(where: { $0.id == id }) else { return }
        worldClocks[index].menuBar = display
    }

    /// Removes a utility the user added, such as a world clock.
    func remove(_ utility: Utility) {
        guard utility.isRemovable else { return }
        worldClocks.removeAll { $0.id == utility.id }
        hiddenIDs.remove(utility.id)
        utilities.removeAll { $0.id == utility.id }
    }

    private static func partitioned(_ utilities: [Utility], hidden: Set<String>) -> [Utility] {
        utilities.filter { !hidden.contains($0.id) } + utilities.filter { hidden.contains($0.id) }
    }
}
