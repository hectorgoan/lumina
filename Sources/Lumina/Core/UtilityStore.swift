import SwiftUI

/// Owns the ordered list of utilities, which ones are hidden, the world
/// clocks and battery widgets the user added, and the panel's edit state.
@MainActor
@Observable
final class UtilityStore {
    private static let orderKey = "utilityOrder"
    private static let hiddenKey = "hiddenUtilities"
    private static let worldClocksKey = "worldClocks"
    private static let batteryWidgetsKey = "batteryWidgets"

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

    private(set) var batteryWidgets: [BatteryWidget] {
        didSet { defaults.set(try? JSONEncoder().encode(batteryWidgets), forKey: Self.batteryWidgetsKey) }
    }

    /// Edit mode as far as layout goes: it widens the panel for the
    /// library, instantly.
    var isEditing = false {
        didSet {
            if !isEditing {
                settingsUtilityID = nil
                isAddingWorldClock = false
                isAddingBatteryWidget = false
                isLibraryPresented = false
                isLibraryExpanded = false
            }
        }
    }

    /// Whether the panel has made room for the library. It widens with
    /// animation before the library fades in, and narrows after it fades out.
    var isLibraryExpanded = false

    /// Whether the library and the edit controls are shown. It changes with
    /// animation just after the panel widens, and just before it narrows.
    var isLibraryPresented = false

    /// Whether tiles show their edit badges and can be dragged.
    var showsEditControls: Bool { isEditing && isLibraryPresented }

    /// The utility whose settings page is open, if any.
    var settingsUtilityID: String?

    /// Whether the world clock city picker is open.
    var isAddingWorldClock = false

    /// Whether the battery widget size picker is open.
    var isAddingBatteryWidget = false

    @ObservationIgnored private let defaults: UserDefaults

    init(catalog: [Utility] = Utility.catalog, defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // Restore the saved order, dropping utilities that no longer exist and
        // appending newly added ones at the end. Newly added utilities that
        // are hidden by default start out hidden.
        let clocks = defaults.data(forKey: Self.worldClocksKey)
            .flatMap { try? JSONDecoder().decode([WorldClock].self, from: $0) } ?? []
        worldClocks = clocks
        let batteries = defaults.data(forKey: Self.batteryWidgetsKey)
            .flatMap { try? JSONDecoder().decode([BatteryWidget].self, from: $0) } ?? []
        batteryWidgets = batteries
        let all = catalog + clocks.compactMap(Utility.worldClock) + batteries.map(Utility.batteryWidget)

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

    /// The utilities waiting in the library, in their saved order.
    var hiddenUtilities: [Utility] {
        utilities.filter { hiddenIDs.contains($0.id) }
    }

    /// Applies a new order of the visible utilities; hidden ones keep
    /// theirs, after the visible ones.
    func reorder(_ newVisibleOrder: [Utility]) {
        let ordered = newVisibleOrder.filter { !hiddenIDs.contains($0.id) } + hiddenUtilities
        guard ordered.map(\.id) != utilities.map(\.id) else { return }
        utilities = ordered
    }

    /// Brings a utility from the library back to the end of the panel.
    func show(_ utility: Utility) {
        guard hiddenIDs.contains(utility.id) else { return }
        toggleVisibility(of: utility)
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
        insertVisible(utility)
        isAddingWorldClock = false
    }

    func worldClock(withID id: String) -> WorldClock? {
        worldClocks.first { $0.id == id }
    }

    func setMenuBarDisplay(_ display: WorldClock.MenuBarDisplay, forClockWithID id: String) {
        guard let index = worldClocks.firstIndex(where: { $0.id == id }) else { return }
        worldClocks[index].menuBar = display
    }

    // MARK: - Battery widgets

    /// Adds a battery widget of the given size after the visible utilities
    /// and closes the picker.
    func addBatteryWidget(size: BatteryWidget.Size) {
        let widget = BatteryWidget(id: "batteries-\(UUID().uuidString)", size: size)
        batteryWidgets.append(widget)
        insertVisible(Utility.batteryWidget(widget))
        isAddingBatteryWidget = false
    }

    func batteryWidget(withID id: String) -> BatteryWidget? {
        batteryWidgets.first { $0.id == id }
    }

    /// Saves a widget's new configuration. Its utility is rebuilt in place,
    /// since a new size changes its width.
    func updateBatteryWidget(_ widget: BatteryWidget) {
        guard let index = batteryWidgets.firstIndex(where: { $0.id == widget.id }) else { return }
        batteryWidgets[index] = widget
        if let position = utilities.firstIndex(where: { $0.id == widget.id }) {
            utilities[position] = Utility.batteryWidget(widget)
        }
    }

    private func insertVisible(_ utility: Utility) {
        var updated = utilities
        let insertionIndex = updated.firstIndex { hiddenIDs.contains($0.id) } ?? updated.endIndex
        updated.insert(utility, at: insertionIndex)
        utilities = updated
    }

    /// Removes a utility the user added, such as a world clock.
    func remove(_ utility: Utility) {
        guard utility.isRemovable else { return }
        worldClocks.removeAll { $0.id == utility.id }
        batteryWidgets.removeAll { $0.id == utility.id }
        hiddenIDs.remove(utility.id)
        utilities.removeAll { $0.id == utility.id }
    }

    private static func partitioned(_ utilities: [Utility], hidden: Set<String>) -> [Utility] {
        utilities.filter { !hidden.contains($0.id) } + utilities.filter { hidden.contains($0.id) }
    }
}
