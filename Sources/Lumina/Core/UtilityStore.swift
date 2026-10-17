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
    private static let mediaWidgetsKey = "mediaWidgets"
    private static let moreKey = "more.utilities"
    private static let moreStyleKey = "more.style"
    private static let moreNameKey = "more.name"
    private static let moreRemembersKey = "more.remembersOpen"
    private static let moreOpenKey = "more.isOpen"

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

    private(set) var mediaWidgets: [MediaWidget] {
        didSet { defaults.set(try? JSONEncoder().encode(mediaWidgets), forKey: Self.mediaWidgetsKey) }
    }

    // MARK: More section

    /// Utilities tucked into the More section: set up and ready, but shown
    /// only when the section is open.
    private(set) var moreIDs: Set<String> {
        didSet { defaults.set(Array(moreIDs), forKey: Self.moreKey) }
    }

    var moreStyle: MoreStyle {
        didSet { defaults.set(moreStyle.rawValue, forKey: Self.moreStyleKey) }
    }

    /// The section's name; "More" unless the user renames it.
    var moreName: String {
        didSet { defaults.set(moreName, forKey: Self.moreNameKey) }
    }

    /// The section's name as shown: "More" when left empty.
    var moreTitle: String {
        let name = moreName.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "More" : name
    }

    /// Keeps the section open (or on its page) between openings of the
    /// panel; otherwise it starts closed each time.
    var remembersMoreOpen: Bool {
        didSet { defaults.set(remembersMoreOpen, forKey: Self.moreRemembersKey) }
    }

    var isMoreOpen: Bool {
        didSet { defaults.set(isMoreOpen, forKey: Self.moreOpenKey) }
    }

    /// The section's tiles are kept invisible while it opens or closes.
    var isMoreFading = false

    /// Whether the section's settings page is open.
    var isMoreSettingsOpen = false

    /// Edit mode as far as layout goes: it widens the panel for the
    /// library, instantly.
    var isEditing = false {
        didSet {
            if !isEditing {
                closeSubpages()
                isLibraryPresented = false
                isLibraryExpanded = false
            }
        }
    }

    /// Whether the panel has made room for the library. It widens with
    /// animation before the library fades in, and narrows after it fades out.
    var isLibraryExpanded = false

    /// Whether the current page is shown; it fades out while pages swap.
    var isPageVisible = true

    /// Tiles kept invisible while they're added to or removed from the grid.
    var fadingUtilityIDs: Set<String> = []

    /// A tile just added: the grid scrolls to it and it glows for a moment,
    /// so it doesn't get lost.
    var highlightedUtilityID: String?

    /// Whether a page or tile transition is under way.
    @ObservationIgnored var isTransitioning = false

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

    /// Whether the media widget add page is open.
    var isAddingMediaWidget = false

    /// The widget being set up on the media widget add page.
    var newMediaWidget = MediaWidget(id: "new", size: .large)

    /// The Uninstaller page shown in place of the grid, if any.
    var uninstallerPage: UninstallerPage?

    /// Whether the menu bar panel is open.
    var isPanelOpen = false

    /// The widget being set up on the battery widget add page: its size,
    /// name and devices.
    var newBatteryWidget = BatteryWidget(id: "new", size: .large)

    /// The city highlighted on the world clock add page.
    var previewCityCode: String?

    /// Whether a settings or add page is open, so edit mode's sidebar shows
    /// a preview instead of the Library.
    var isConfiguring: Bool {
        settingsUtilityID != nil || isAddingWorldClock || isAddingBatteryWidget || isAddingMediaWidget || isMoreSettingsOpen
    }

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
        let media = defaults.data(forKey: Self.mediaWidgetsKey)
            .flatMap { try? JSONDecoder().decode([MediaWidget].self, from: $0) } ?? []
        mediaWidgets = media
        let all = catalog + clocks.compactMap(Utility.worldClock) + batteries.map(Utility.batteryWidget)
            + media.map(Utility.mediaWidget)

        let savedOrder = defaults.stringArray(forKey: Self.orderKey) ?? []
        let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        let restored = savedOrder.compactMap { byID[$0] }
        let added = all.filter { !savedOrder.contains($0.id) }

        let savedHidden = Set(defaults.stringArray(forKey: Self.hiddenKey) ?? []).intersection(byID.keys)
        let hidden = savedHidden.union(added.filter(\.isHiddenByDefault).map(\.id))
        hiddenIDs = hidden
        utilities = Self.partitioned(restored + added, hidden: hidden)

        moreIDs = Set(defaults.stringArray(forKey: Self.moreKey) ?? []).intersection(byID.keys).subtracting(hidden)
        moreStyle = defaults.string(forKey: Self.moreStyleKey).flatMap(MoreStyle.init) ?? .row
        moreName = defaults.string(forKey: Self.moreNameKey) ?? "More"
        let remembers = defaults.bool(forKey: Self.moreRemembersKey)
        remembersMoreOpen = remembers
        isMoreOpen = remembers && defaults.bool(forKey: Self.moreOpenKey)

        // Save right away, so utilities hidden by default stay as the user
        // leaves them on later launches.
        defaults.set(utilities.map(\.id), forKey: Self.orderKey)
        defaults.set(Array(hidden), forKey: Self.hiddenKey)
    }

    /// Closes any settings or add page, back to the grid.
    func closeSubpages() {
        settingsUtilityID = nil
        isMoreSettingsOpen = false
        isAddingWorldClock = false
        isAddingBatteryWidget = false
        isAddingMediaWidget = false
    }

    /// The utilities shown outside edit mode.
    var visibleUtilities: [Utility] {
        utilities.filter { !hiddenIDs.contains($0.id) }
    }

    /// The visible utilities always on show.
    var mainUtilities: [Utility] {
        visibleUtilities.filter { !moreIDs.contains($0.id) }
    }

    /// The visible utilities in the More section.
    var moreUtilities: [Utility] {
        visibleUtilities.filter { moreIDs.contains($0.id) }
    }

    /// Applies the edit grid's order: the utilities before the section's
    /// header stay on show, the ones after it go into the section.
    func reorder(main: [Utility], more: [Utility]) {
        reorder(main + more)
        let ids = Set(more.map(\.id))
        if ids != moreIDs { moreIDs = ids }
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
            // Shown again from the Library, it comes back on show.
            moreIDs.remove(utility.id)
            others.append(utility)
        }
        utilities = others
    }

    // MARK: - World clocks

    /// Adds a clock for the city after the visible utilities and closes the
    /// picker.
    @discardableResult
    func addWorldClock(for city: WorldClockCity) -> String? {
        let clock = WorldClock(id: "worldClock-\(UUID().uuidString)", cityCode: city.code)
        guard let utility = Utility.worldClock(clock) else { return nil }
        worldClocks.append(clock)
        insertVisible(utility)
        isAddingWorldClock = false
        return utility.id
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
    @discardableResult
    func addBatteryWidget(size: BatteryWidget.Size) -> String {
        addBatteryWidget(BatteryWidget(id: "new", size: size))
    }

    /// Adds a battery widget set up like `draft` (the add page's) after the
    /// visible utilities, closes the picker and starts a fresh draft.
    @discardableResult
    func addBatteryWidget(_ draft: BatteryWidget) -> String {
        let widget = BatteryWidget(
            id: "batteries-\(UUID().uuidString)", size: draft.size, name: draft.title,
            choosesAutomatically: draft.choosesAutomatically, chosenDevices: draft.chosenDevices
        )
        resetNewBatteryWidget()
        batteryWidgets.append(widget)
        insertVisible(Utility.batteryWidget(widget))
        isAddingBatteryWidget = false
        return widget.id
    }

    /// Starts the add page over, keeping the size last picked.
    func resetNewBatteryWidget() {
        newBatteryWidget = BatteryWidget(id: "new", size: newBatteryWidget.size)
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

    // MARK: - Media widgets

    /// Adds a media widget set up like `draft` (the add page's) after the
    /// visible utilities, closes the add page and starts a fresh draft.
    @discardableResult
    func addMediaWidget(_ draft: MediaWidget) -> String {
        var widget = draft
        widget.id = "media-\(UUID().uuidString)"
        resetNewMediaWidget()
        mediaWidgets.append(widget)
        insertVisible(Utility.mediaWidget(widget))
        isAddingMediaWidget = false
        return widget.id
    }

    /// Starts the add page over, keeping the size and background last picked.
    func resetNewMediaWidget() {
        newMediaWidget.id = "new"
    }

    func mediaWidget(withID id: String) -> MediaWidget? {
        mediaWidgets.first { $0.id == id }
    }

    /// Saves a widget's new configuration, rebuilding its utility in place.
    func updateMediaWidget(_ widget: MediaWidget) {
        guard let index = mediaWidgets.firstIndex(where: { $0.id == widget.id }) else { return }
        mediaWidgets[index] = widget
        if let position = utilities.firstIndex(where: { $0.id == widget.id }) {
            utilities[position] = Utility.mediaWidget(widget)
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
        mediaWidgets.removeAll { $0.id == utility.id }
        hiddenIDs.remove(utility.id)
        moreIDs.remove(utility.id)
        utilities.removeAll { $0.id == utility.id }
    }

    private static func partitioned(_ utilities: [Utility], hidden: Set<String>) -> [Utility] {
        utilities.filter { !hidden.contains($0.id) } + utilities.filter { hidden.contains($0.id) }
    }
}

/// The Uninstaller's pages, shown in place of the grid.
enum UninstallerPage {
    case list, review, done
}

/// How the More section shows its utilities.
enum MoreStyle: String, CaseIterable {
    /// A row under the utilities, with their icons; opens below.
    case row
    /// A second page of tiles, with dots to switch.
    case pages
    /// A stack of cards that fans out.
    case stack

    var title: String {
        switch self {
        case .row: "Row"
        case .pages: "Pages"
        case .stack: "Stack"
        }
    }

    var summary: String {
        switch self {
        case .row: "A row under your utilities, with the icons of what’s inside."
        case .pages: "A second page of tiles. Click the dots to switch."
        case .stack: "A stack of cards that fans out when clicked."
        }
    }
}
