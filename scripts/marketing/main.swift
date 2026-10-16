import AppKit
import SwiftUI

// Renders Lumina's marketing images from the app's real views.
// Usage: render <repository-root>
//
// Writes docs/marketing/hero-{dark,light}.png, docs/marketing/x-overview.png
// and one card per feature in docs/marketing/features/, then rewrites the
// feature gallery in README.md. Features come from the app itself
// (`Utility.catalog` and the Library's "Add New" items), so a new utility
// gets a card on the next run. Give it a proper entry in `Feature.all`;
// until then it gets a plain card and the script prints a warning.

_ = NSApplication.shared
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let marketing = root.appendingPathComponent("docs/marketing")
let appIcon = NSImage(contentsOf: root.appendingPathComponent("docs/icon.png"))!

// MARK: - Demo data

/// The devices the battery widgets show, so renders don't depend on what's
/// connected to this Mac.
enum DemoDevice {
    static let keyboard = BatteryDevice(id: "keyboard", name: "Magic Keyboard", level: 0.45, isCharging: false, symbol: "keyboard")
    static let mouse = BatteryDevice(id: "mouse", name: "Magic Mouse", level: 0.90, isCharging: false, symbol: "magicmouse.fill")
    static let headphones = BatteryDevice(id: "headphones", name: "Headphones", level: 0.96, isCharging: false, symbol: "headphones")
    static let airPods = BatteryDevice(id: "airpods", name: "AirPods Pro", level: 1.0, isCharging: true, symbol: "airpods.pro")
    static let airPodsCase = BatteryDevice(id: "case", name: "AirPods Pro Case", level: 0.53, isCharging: false, symbol: "airpods.pro.chargingcase.wireless.fill")
    static let mac = BatteryDevice(id: "mac", name: "MacBook Pro", level: 0.79, isCharging: false, symbol: "laptopcomputer")
    static let trackpad = BatteryDevice(id: "trackpad", name: "Magic Trackpad", level: 0.18, isCharging: false, symbol: "rectangle.and.hand.point.up.left.fill")
}

/// A tile to put in a rendered panel.
enum Tile {
    case utility(String)
    case clock(String)
    case batteries(BatteryWidget.Size, [BatteryDevice])
}

/// Battery widget ID → the demo devices it shows.
@MainActor enum DemoBatteries {
    static var byWidget: [String: [BatteryDevice]] = [:]
}

/// A store showing exactly `tiles`, in order. Uses a throwaway defaults
/// suite, so renders don't depend on (or change) the saved layout.
@MainActor
func makeStore(_ tiles: [Tile]) -> UtilityStore {
    let store = UtilityStore(defaults: UserDefaults(suiteName: "lumina.render.\(UUID().uuidString)")!)
    let ids = tiles.compactMap { tile -> String? in
        switch tile {
        case .utility(let id):
            return id
        case .clock(let code):
            return store.addWorldClock(for: WorldClockCity.city(withCode: code)!)
        case .batteries(let size, let devices):
            let id = store.addBatteryWidget(size: size)
            DemoBatteries.byWidget[id] = devices
            return id
        }
    }
    for utility in store.visibleUtilities where !ids.contains(utility.id) {
        store.toggleVisibility(of: utility)
    }
    for utility in store.hiddenUtilities where ids.contains(utility.id) {
        store.toggleVisibility(of: utility)
    }
    let byID = Dictionary(uniqueKeysWithValues: store.utilities.map { ($0.id, $0) })
    store.reorder(ids.compactMap { byID[$0] })
    return store
}

/// The panel in the screenshot the hero is modeled on.
let heroTiles: [Tile] = [
    .utility("cpuFocus"),
    .utility("caffeine"),
    .utility("stayGreen"),
    .clock("MAD"),
    .batteries(.medium, [DemoDevice.keyboard, DemoDevice.mouse]),
    .batteries(.large, [DemoDevice.headphones, DemoDevice.airPods, DemoDevice.airPodsCase]),
    .utility("pomodoro"),
    .utility("appearance"),
    .utility("keyboardLock"),
    .utility("quitAll"),
]

// MARK: - Features

/// A feature with its own card in docs/marketing/features and the README.
struct Feature {
    let slug: String
    let name: String
    let symbol: String
    let tint: Color
    let headline: String
    let detail: String
    /// The catalog utilities this card covers.
    var utilityIDs: [String] = []
    /// The Library's "Add New" item this card covers.
    var newItem: LibraryDrag.NewItem? = nil
    /// What the card shows: the tiles, in a panel.
    var tiles: [Tile] = []
    /// Shows the menu bar above the tiles, with this state.
    var menuBar: MenuBarStatus? = nil
    /// Shows the tiles in edit mode, with the Library beside them.
    var isEditing = false
    /// Something to show beside the tiles, like a settings page.
    var accessory: Accessory? = nil

    enum Accessory { case keepOpen }

    @MainActor static let all: [Feature] = [
        Feature(
            slug: "caffeine", name: "Caffeine", symbol: "cup.and.saucer.fill", tint: .blue,
            headline: "Keep your Mac awake.",
            detail: "One click keeps the display on and the screen saver away, for a long render, a presentation or a download. The menu bar icon turns into a sun while it’s on.",
            utilityIDs: ["caffeine"],
            tiles: [.utility("caffeine")],
            menuBar: MenuBarStatus(isCaffeinated: true, isStayingGreen: false)
        ),
        Feature(
            slug: "stay-green", name: "Stay Green", symbol: "person.crop.circle.badge.checkmark", tint: .green,
            headline: "Always available.",
            detail: "Keeps you active in Slack, Teams and other chat apps by telling macOS you’re still there. No mouse jiggling, no extra permissions, and a green halo in the menu bar while it’s on.",
            utilityIDs: ["stayGreen"],
            tiles: [.utility("stayGreen")],
            menuBar: MenuBarStatus(isCaffeinated: false, isStayingGreen: true)
        ),
        Feature(
            slug: "pomodoro", name: "Pomodoro", symbol: "timer", tint: .red,
            headline: "Focus in rounds.",
            detail: "Focus sessions with short and long breaks, a progress bar, notifications and the countdown in your menu bar. Set each duration to suit how you work.",
            utilityIDs: ["pomodoro"],
            tiles: [.utility("pomodoro")]
        ),
        Feature(
            slug: "world-clocks", name: "World Clocks", symbol: "globe", tint: .orange,
            headline: "Every time zone you work with.",
            detail: "Add a clock for any of 458 cities and see its time and day at a glance. Pin one to the menu bar with its flag and city code.",
            newItem: .worldClock,
            tiles: [.clock("MAD"), .clock("NYC"), .clock("TYO"), .clock("SFO")],
            menuBar: MenuBarStatus(isCaffeinated: true, isStayingGreen: true)
        ),
        Feature(
            slug: "batteries", name: "Batteries", symbol: "battery.75percent", tint: .green,
            headline: "Every battery, one look.",
            detail: "Your Mac, AirPods, keyboard, mouse and more, in four sizes. Choose the devices to show, or let Lumina show the ones running lowest.",
            newItem: .batteries,
            tiles: [
                .batteries(.small, [DemoDevice.mac]),
                .batteries(.small, [DemoDevice.trackpad]),
                .batteries(.medium, [DemoDevice.keyboard, DemoDevice.mouse]),
                .batteries(.large, [DemoDevice.headphones, DemoDevice.airPods, DemoDevice.airPodsCase, DemoDevice.mac]),
            ]
        ),
        Feature(
            slug: "system", name: "System", symbol: "cpu", tint: .teal,
            headline: "Your Mac’s vitals.",
            detail: "CPU, memory, temperature and fans, in three layouts: gauges, a compact list or a live CPU graph.",
            utilityIDs: ["systemStatus", "systemList", "cpuFocus"],
            tiles: [.utility("systemStatus"), .utility("cpuFocus")]
        ),
        Feature(
            slug: "appearance", name: "Appearance", symbol: "circle.lefthalf.filled", tint: .indigo,
            headline: "Light or dark, instantly.",
            detail: "Switch your whole Mac between Light and Dark Mode. Pick the large previews, a compact pair of buttons or a single row.",
            utilityIDs: ["appearance", "compactAppearance", "appearanceRow"],
            tiles: [.utility("appearance"), .utility("compactAppearance"), .utility("appearanceRow")]
        ),
        Feature(
            slug: "keyboard-lock", name: "Keyboard Lock", symbol: "keyboard", tint: .orange,
            headline: "Clean your keyboard, not your document.",
            detail: "Blocks every key while you wipe the keyboard down. Click again to unlock.",
            utilityIDs: ["keyboardLock"],
            tiles: [.utility("keyboardLock")]
        ),
        Feature(
            slug: "quit-all", name: "Quit All", symbol: "command", tint: .pink,
            headline: "A fresh start, in one click.",
            detail: "Quits every open app except the ones you choose to keep. End the day, or clear the decks before deep work.",
            utilityIDs: ["quitAll"],
            tiles: [.utility("quitAll")],
            accessory: .keepOpen
        ),
        Feature(
            slug: "cleanup", name: "Cleanup", symbol: "sparkles", tint: .purple,
            headline: "Junk out, space back.",
            detail: "Finds app caches, Xcode build data, logs and the Trash, shows what each takes, and clears them in one click. Choose what gets cleaned in its settings.",
            utilityIDs: ["cleanup"],
            tiles: [.utility("cleanup")]
        ),
        Feature(
            slug: "customize", name: "Customize", symbol: "square.grid.2x2.fill", tint: .purple,
            headline: "Make it yours.",
            detail: "Drag tiles into any order, hide the ones you don’t need, and add world clocks and batteries from the Library.",
            tiles: [.utility("caffeine"), .utility("stayGreen"), .clock("MAD"), .batteries(.medium, [DemoDevice.keyboard, DemoDevice.mouse]), .utility("pomodoro")],
            isEditing: true
        ),
    ]

    /// Every card: the ones above, plus a plain card for anything in the app
    /// that none of them covers yet.
    @MainActor static var everything: [Feature] {
        var features = all
        let covered = Set(all.flatMap(\.utilityIDs))
        for utility in Utility.catalog where !covered.contains(utility.id) {
            print("warning: no marketing copy for utility \"\(utility.id)\"; add it to Feature.all in scripts/marketing/main.swift")
            features.append(Feature(
                slug: utility.id, name: utility.name, symbol: utility.symbol, tint: .accentColor,
                headline: utility.name, detail: "New in Lumina.",
                utilityIDs: [utility.id], tiles: [.utility(utility.id)]
            ))
        }
        let coveredNew = Set(all.compactMap(\.newItem))
        for item in LibraryDrag.NewItem.allCases where !coveredNew.contains(item) {
            print("warning: no marketing copy for Library item \"\(item.rawValue)\"; add it to Feature.all in scripts/marketing/main.swift")
            features.append(Feature(
                slug: item.rawValue, name: item.title, symbol: item.symbol, tint: .accentColor,
                headline: item.title, detail: item.detail, newItem: item
            ))
        }
        return features
    }
}

// MARK: - Scene pieces

struct Wallpaper: View {
    let dark: Bool

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width, h = proxy.size.height
            ZStack {
                LinearGradient(
                    colors: dark
                        ? [Color(red: 0.04, green: 0.05, blue: 0.16), Color(red: 0.10, green: 0.08, blue: 0.30), Color(red: 0.24, green: 0.10, blue: 0.36)]
                        : [Color(red: 0.70, green: 0.82, blue: 0.99), Color(red: 0.84, green: 0.84, blue: 0.99), Color(red: 0.99, green: 0.86, blue: 0.88)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                glow(dark ? Color(red: 0.10, green: 0.45, blue: 0.85) : Color(red: 0.45, green: 0.72, blue: 1.0), opacity: 0.55)
                    .frame(width: w * 0.95, height: h * 0.6)
                    .rotationEffect(.degrees(-16))
                    .offset(x: -w * 0.3, y: h * 0.42)
                glow(dark ? Color(red: 0.80, green: 0.30, blue: 0.60) : Color(red: 1.0, green: 0.66, blue: 0.74), opacity: 0.45)
                    .frame(width: w * 0.7, height: h * 0.55)
                    .rotationEffect(.degrees(20))
                    .offset(x: w * 0.38, y: h * 0.36)
                glow(dark ? Color(red: 0.40, green: 0.28, blue: 0.95) : Color(red: 0.72, green: 0.64, blue: 1.0), opacity: 0.5)
                    .frame(width: w * 0.8, height: h * 0.45)
                    .offset(x: w * 0.12, y: -h * 0.3)
            }
            .frame(width: w, height: h)
        }
    }

    private func glow(_ color: Color, opacity: Double) -> some View {
        Ellipse().fill(color.opacity(opacity)).blur(radius: 110)
    }
}

/// Marks where Lumina's menu bar item is, so the panel can hang below it.
struct LuminaItemAnchor: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

struct MenuBar: View {
    let dark: Bool
    var status = MenuBarStatus(isCaffeinated: true, isStayingGreen: true)
    var clocks = ["MAD"]
    var showsAppMenus = true

    var body: some View {
        let ink: Color = dark ? .white : .black
        HStack(spacing: 0) {
            if showsAppMenus {
                HStack(spacing: 20) {
                    Image(systemName: "applelogo").font(.system(size: 15, weight: .medium))
                    Text("Finder").font(.system(size: 13, weight: .bold))
                    ForEach(["File", "Edit", "View", "Go", "Window", "Help"], id: \.self) {
                        Text($0).font(.system(size: 13))
                    }
                }
            }
            if showsAppMenus { Spacer(minLength: 0) }
            HStack(spacing: 16) {
                // Lumina's item, highlighted because its panel is open.
                MenuBarIconView(status: status, foreground: ink)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(ink.opacity(0.18), in: Capsule())
                    .anchorPreference(key: LuminaItemAnchor.self, value: .bounds) { $0 }
                ForEach(clocks, id: \.self) { code in
                    MenuBarClock(city: WorldClockCity.city(withCode: code)!, ink: ink)
                }
                Image(systemName: "wifi").font(.system(size: 14, weight: .medium))
                if showsAppMenus {
                    Image(systemName: "battery.75percent").font(.system(size: 15))
                    Image(systemName: "switch.2").font(.system(size: 13, weight: .medium))
                    Text(Date(), format: .dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
                        .font(.system(size: 13))
                } else {
                    Text(Date(), format: .dateTime.weekday(.abbreviated).hour().minute())
                        .font(.system(size: 13))
                }
            }
            .fixedSize()
        }
        .foregroundStyle(ink)
        .padding(.horizontal, 16)
        .frame(height: 32)
        .background(dark ? Color.black.opacity(0.12) : Color.white.opacity(0.2))
    }
}

/// A world clock pinned to the menu bar: flag, outlined city code, time.
struct MenuBarClock: View {
    let city: WorldClockCity
    let ink: Color

    var body: some View {
        HStack(spacing: 4) {
            Text(city.flag).font(.system(size: 11))
            Text(city.code)
                .font(.system(size: 9, weight: .semibold)).tracking(0.3)
                .padding(.horizontal, 3).padding(.vertical, 1)
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(ink, lineWidth: 0.8))
            Text(time).font(.system(size: 13)).monospacedDigit()
        }
    }

    private var time: String {
        let formatter = DateFormatter()
        formatter.timeZone = city.timeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: Date())
    }
}

/// A tile's content, with battery widgets showing their demo devices.
struct TileContent: View {
    let utility: Utility
    let store: UtilityStore

    var body: some View {
        if let widget = store.batteryWidget(withID: utility.id) {
            BatteryWidgetContent(size: widget.size, devices: DemoBatteries.byWidget[utility.id] ?? [])
        } else {
            utility.content()
        }
    }
}

/// The app's real tiles, laid out by the app's grid layout.
struct Tiles: View {
    let store: UtilityStore
    var isEditing = false

    var body: some View {
        let utilities = store.visibleUtilities
        let span = utilities.map(\.size.span).reduce(0, +)
        let metrics = TileGridMetrics(width: 296, spacing: 10)
        if span < 4 {
            // Less than a row: just those tiles, at their real widths.
            HStack(spacing: 10) {
                ForEach(utilities, id: \.id) { utility in
                    tile(utility).frame(width: metrics.width(forSpan: utility.size.span))
                }
            }
            .environment(store)
        } else {
            TileGridLayout(spacing: 10) {
                ForEach(utilities, id: \.id) { utility in
                    tile(utility).layoutValue(key: TileSpan.self, value: utility.size.span)
                }
            }
            .frame(width: 296)
            .environment(store)
        }
    }

    private func tile(_ utility: Utility) -> some View {
                ModuleTile(isEditing: isEditing, isLifted: false) {
                    TileContent(utility: utility, store: store)
                } badges: {
                    HStack(spacing: 4) {
                        if utility.settings != nil {
                            EditBadge(symbol: "gearshape.fill", help: "") {}
                        }
                        EditBadge(symbol: utility.isRemovable ? "minus" : "eye.fill", help: "") {}
                    }
                }
    }
}

/// Frosted glass: the wallpaper right behind it, blurred and tinted.
struct Glass<Content: View>: View {
    let dark: Bool
    let wallpaperSize: CGSize
    /// Where the glass sits on the wallpaper.
    let origin: CGPoint
    var cornerRadius: CGFloat = 26
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background {
                GeometryReader { _ in
                    Wallpaper(dark: dark)
                        .frame(width: wallpaperSize.width, height: wallpaperSize.height)
                        .offset(x: -origin.x, y: -origin.y)
                        .blur(radius: 40)
                }
                .overlay(shape.fill(dark ? Color(white: 0.11).opacity(0.72) : Color(white: 0.97).opacity(0.62)))
                .clipShape(shape)
            }
            .overlay { shape.strokeBorder(dark ? Color.white.opacity(0.16) : Color.white.opacity(0.7), lineWidth: 0.8) }
            .shadow(color: .black.opacity(dark ? 0.5 : 0.16), radius: 34, y: 20)
    }
}

/// The menu bar panel: tiles and footer on glass.
struct Panel: View {
    let store: UtilityStore
    let dark: Bool
    let wallpaperSize: CGSize
    let origin: CGPoint
    var isEditing = false
    var showsFooter = true
    var accessory: Feature.Accessory? = nil

    var body: some View {
        Glass(dark: dark, wallpaperSize: wallpaperSize, origin: origin) {
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 12) {
                    Tiles(store: store, isEditing: isEditing)
                    if showsFooter {
                        Footer(dark: dark, isEditing: isEditing).frame(width: 296)
                    }
                }
                if accessory == .keepOpen {
                    KeepOpenReplica().frame(width: 230)
                }
                if isEditing {
                    LibraryReplica(store: store)
                        .frame(width: 230)
                }
            }
            .padding(12)
        }
        .environment(\.colorScheme, dark ? .dark : .light)
    }
}

struct Footer: View {
    let dark: Bool
    var isEditing = false

    var body: some View {
        let fill = dark ? Color.white.opacity(0.12) : Color.white.opacity(0.7)
        let edge = dark ? Color.white.opacity(0.18) : Color.black.opacity(0.08)
        HStack(spacing: 8) {
            Text(isEditing ? "Done" : "Edit Utilities")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isEditing ? Color.white : Color.primary)
                .frame(maxWidth: .infinity, minHeight: 32)
                .background(isEditing ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(fill), in: Capsule())
                .overlay(Capsule().strokeBorder(edge, lineWidth: 0.6))
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .medium))
                .frame(width: 32, height: 32)
                .background(fill, in: Circle())
                .overlay(Circle().strokeBorder(edge, lineWidth: 0.6))
        }
    }
}

/// The edit-mode Library, drawn here because its search field (an AppKit
/// text field) doesn't render offscreen.
struct LibraryReplica: View {
    let store: UtilityStore

    var body: some View {
        let hidden = store.hiddenUtilities.prefix(4)
        VStack(alignment: .leading, spacing: 8) {
            Text("Library").font(.system(size: 15, weight: .semibold))
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .medium))
                Text("Search").font(.system(size: 12))
                Spacer()
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9)
            .frame(height: 26)
            .background(Color.panelTrack, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            section("Hidden")
            ForEach(Array(hidden), id: \.id) { row($0.symbol, $0.name, $0.size.title) }
            section("Add New").padding(.top, 8)
            ForEach(LibraryDrag.NewItem.allCases, id: \.self) { row($0.symbol, $0.title, $0.detail) }
            Spacer(minLength: 0)
            Text("Drag into the panel or click +")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.panelSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func section(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 4)
    }

    private func row(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 26, height: 26)
                .background(Color.panelControl, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text(detail).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 15))
                .foregroundStyle(.green)
        }
        .padding(.vertical, 4)
    }
}

/// Quit All's settings page, drawn here with sample apps rather than the
/// apps this Mac keeps open.
struct KeepOpenReplica: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Keep Open")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            VStack(spacing: 6) {
                ForEach(["Music", "Notes", "Calendar"], id: \.self) { name in
                    HStack(spacing: 8) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: "/System/Applications/\(name).app"))
                            .resizable()
                            .frame(width: 20, height: 20)
                        Text(name).font(.system(size: 13))
                        Spacer()
                        Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                    }
                }
            }
            Divider()
            Text("Finder and Lumina are never quit.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(Color.panelSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// Wraps its subviews onto as many rows as they need.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: subviews, width: proposal.width ?? .infinity)
        let height = rows.map { $0.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0 }.reduce(0, +)
            + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(for: subviews, width: bounds.width) {
            var x = bounds.minX
            let height = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            for subview in row {
                let size = subview.sizeThatFits(.unspecified)
                subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
                x += size.width + spacing
            }
            y += height + spacing
        }
    }

    private func rows(for subviews: Subviews, width: CGFloat) -> [[LayoutSubview]] {
        var rows: [[LayoutSubview]] = [[]]
        var x: CGFloat = 0
        for subview in subviews {
            let w = subview.sizeThatFits(.unspecified).width
            if x + w > width, !rows[rows.count - 1].isEmpty {
                rows.append([])
                x = 0
            }
            rows[rows.count - 1].append(subview)
            x += w + spacing
        }
        return rows
    }
}

/// A feature's symbol on a tinted rounded square, like a Settings icon.
struct FeatureIcon: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.48, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                LinearGradient(colors: [tint.mix(with: .white, by: 0.15), tint.mix(with: .black, by: 0.12)], startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            )
    }
}

/// Lumina's icon and name, the signature on every image.
struct Brand: View {
    var size: CGFloat = 28

    var body: some View {
        HStack(spacing: size * 0.3) {
            Image(nsImage: appIcon).resizable().frame(width: size * 1.25, height: size * 1.25)
            Text("Lumina").font(.system(size: size * 0.62, weight: .semibold))
        }
    }
}

// MARK: - Compositions

/// The desktop with the panel open below Lumina's menu bar item, and the
/// pitch on the left.
struct Hero: View {
    let store: UtilityStore
    let dark: Bool
    let size: CGSize

    var body: some View {
        ZStack(alignment: .topLeading) {
            Wallpaper(dark: dark)
            VStack(spacing: 0) {
                MenuBar(dark: dark)
                Spacer()
            }
            pitch
                .frame(width: 560, alignment: .leading)
                .padding(.leading, 110)
                .frame(maxHeight: .infinity)
        }
        .overlayPreferenceValue(LuminaItemAnchor.self) { anchor in
            GeometryReader { proxy in
                if let anchor {
                    let item = proxy[anchor]
                    let origin = CGPoint(x: item.minX - 14, y: item.maxY + 9)
                    Panel(store: store, dark: dark, wallpaperSize: size, origin: origin)
                        .offset(x: origin.x, y: origin.y)
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .environment(\.colorScheme, dark ? .dark : .light)
    }

    private var pitch: some View {
        VStack(alignment: .leading, spacing: 22) {
            Image(nsImage: appIcon).resizable().frame(width: 112, height: 112)
                .padding(.leading, -12)
            Text("Lumina")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.bottom, -14)
            Text("Control Center\nfor your focus.")
                .font(.system(size: 64, weight: .bold))
                .tracking(-1)
                .lineHeight(.multiple(factor: 0.95))
                .padding(.bottom, 18)
            Text("The small tools you reach for all day, in one panel in your menu bar. Free, open source and made for macOS.")
                .font(.system(size: 21))
                .foregroundStyle(.secondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            FeaturePills(dark: dark)
                .padding(.top, 6)
        }
    }
}

/// A capsule per feature, so new ones show up in the hero too.
struct FeaturePills: View {
    let dark: Bool

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(Feature.everything, id: \.slug) { feature in
                HStack(spacing: 7) {
                    Image(systemName: feature.symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(feature.tint)
                    Text(feature.name).font(.system(size: 14, weight: .medium))
                }
                .padding(.horizontal, 13)
                .frame(height: 34)
                .background(dark ? Color.white.opacity(0.1) : Color.white.opacity(0.55), in: Capsule())
                .overlay(Capsule().strokeBorder(dark ? Color.white.opacity(0.14) : Color.white.opacity(0.8), lineWidth: 0.6))
            }
        }
    }
}

/// A 16:9 card: words on the left, the app on the right.
struct Card<Visual: View>: View {
    let dark: Bool
    @ViewBuilder var words: () -> AnyView
    @ViewBuilder var visual: Visual

    var body: some View {
        ZStack {
            Wallpaper(dark: dark)
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    words()
                    Spacer(minLength: 0)
                    Brand(size: 22).foregroundStyle(.secondary)
                }
                .frame(width: 330, alignment: .leading)
                .padding(.vertical, 44)
                .padding(.leading, 52)
                visual
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 24)
            }
        }
        .frame(width: cardSize.width, height: cardSize.height)
        .clipped()
        .environment(\.colorScheme, dark ? .dark : .light)
    }
}

let cardSize = CGSize(width: 800, height: 450)
/// The room a card's visual gets, right of the words.
let visualBox = CGSize(width: 350, height: 350)

struct FeatureCard: View {
    let feature: Feature
    let dark: Bool

    var body: some View {
        Card(dark: dark) {
            AnyView(VStack(alignment: .leading, spacing: 14) {
                Spacer(minLength: 0)
                FeatureIcon(symbol: feature.symbol, tint: feature.tint, size: 50)
                Text(feature.name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(feature.tint.mix(with: dark ? .white : .black, by: 0.2))
                    .padding(.top, 4)
                Text(feature.headline)
                    .font(.system(size: 38, weight: .bold))
                    .tracking(-0.5)
                    .lineHeight(.multiple(factor: 0.95))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 14)
                Text(feature.detail)
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            })
        } visual: {
            FeatureVisual(feature: feature, dark: dark)
        }
    }
}

/// A feature's tiles on glass, optionally under the menu bar, scaled to
/// fill the card's visual area.
struct FeatureVisual: View {
    let feature: Feature
    let dark: Bool

    var body: some View {
        let content: AnyView = {
            if feature.tiles.isEmpty {
                return AnyView(FeatureIcon(symbol: feature.symbol, tint: feature.tint, size: 150))
            }
            let store = makeStore(feature.tiles)
            // The glass's wallpaper offset: about where it lands on the card.
            let origin = CGPoint(x: 420, y: 60)
            let panel = Panel(
                store: store, dark: dark, wallpaperSize: cardSize, origin: origin,
                isEditing: feature.isEditing, showsFooter: feature.isEditing, accessory: feature.accessory
            )
            guard let status = feature.menuBar else { return AnyView(panel) }
            let clocks = feature.newItem == .worldClock ? ["MAD", "NYC"] : []
            return AnyView(VStack(alignment: .leading, spacing: 8) {
                MenuBar(dark: dark, status: status, clocks: clocks, showsAppMenus: false)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                panel
            })
        }()
        ScaledToFit(content: content, box: visualBox, maxScale: 1.8)
            .environment(\.colorScheme, dark ? .dark : .light)
    }
}

/// Scales a view to fit a box. `scaleEffect` doesn't change a view's layout
/// size, so this measures the view first and sets the scaled frame.
struct ScaledToFit: View {
    let content: AnyView
    let box: CGSize
    let maxScale: CGFloat

    var body: some View {
        let natural = NSHostingView(rootView: content.fixedSize()).fittingSize
        let scale = min(maxScale, box.width / natural.width, box.height / natural.height)
        content
            .fixedSize()
            .scaleEffect(scale)
            .frame(width: natural.width * scale, height: natural.height * scale)
    }
}

/// The social overview: the pitch, and the panel hanging off the menu bar,
/// running past the bottom edge.
struct Overview: View {
    let store: UtilityStore
    let dark: Bool

    var body: some View {
        Card(dark: dark) {
            AnyView(VStack(alignment: .leading, spacing: 14) {
                Spacer(minLength: 0)
                Image(nsImage: appIcon).resizable().frame(width: 76, height: 76).padding(.leading, -8)
                Text("Control Center\nfor your focus.")
                    .font(.system(size: 40, weight: .bold))
                    .tracking(-0.5)
                    .lineHeight(.multiple(factor: 0.95))
                    .padding(.bottom, 14)
                Text("Caffeine, Stay Green, Pomodoro, world clocks, batteries and more, in one panel in your menu bar.")
                    .font(.system(size: 17))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            })
        } visual: {
            // The panel runs past the card's bottom edge.
            Color.clear.overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 8) {
                    MenuBar(dark: dark, clocks: ["MAD"], showsAppMenus: false)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    Panel(store: store, dark: dark, wallpaperSize: cardSize, origin: CGPoint(x: 440, y: 60))
                }
                .fixedSize()
                .padding(.top, 40)
                .padding(.leading, 30)
            }
        }
    }
}

// MARK: - Rendering

@MainActor
func save<V: View>(_ view: V, _ url: URL, scale: CGFloat = 2) {
    let renderer = ImageRenderer(content: view)
    renderer.scale = scale
    // Some views make ImageRenderer switch to a 16-bit, wide-range image,
    // which comes out washed out as a PNG. Always flatten to 8-bit sRGB.
    guard let image = renderer.cgImage,
          let context = CGContext(
              data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          )
    else { print("failed \(url.lastPathComponent)"); return }
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    let rep = NSBitmapImageRep(cgImage: context.makeImage()!)
    let png = rep.representation(using: .png, properties: [:])!
    try! png.write(to: url)
    print("wrote \(url.path.replacingOccurrences(of: root.path + "/", with: "")) \(rep.pixelsWide)x\(rep.pixelsHigh)")
}

/// Shows the app in light or dark, the way the Appearance tile reads it
/// (from the app's appearance, not the system's, which stays as it is).
@MainActor
func useAppearance(dark: Bool) {
    NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    RunLoop.main.run(until: Date().addingTimeInterval(0.3))
}

/// Rewrites the README's feature gallery, between its markers.
@MainActor
func updateReadme(with features: [Feature]) {
    let readme = root.appendingPathComponent("README.md")
    guard var text = try? String(contentsOf: readme, encoding: .utf8),
          let start = text.range(of: "<!-- features:start -->"),
          let end = text.range(of: "<!-- features:end -->")
    else { print("warning: README.md has no feature gallery markers"); return }

    var rows = ["", "<table>"]
    for pair in stride(from: 0, to: features.count, by: 2) {
        rows.append("<tr>")
        for feature in features[pair..<min(pair + 2, features.count)] {
            rows.append("<td width=\"50%\"><img src=\"docs/marketing/features/\(feature.slug).png\" alt=\"\(feature.name): \(feature.headline)\"></td>")
        }
        rows.append("</tr>")
    }
    rows.append("</table>")
    rows.append("")
    text.replaceSubrange(start.upperBound..<end.lowerBound, with: rows.joined(separator: "\n"))
    try! text.write(to: readme, atomically: true, encoding: .utf8)
    print("updated README.md feature gallery")
}

MainActor.assumeIsolated {
    CaffeineController.shared.toggle()
    StayGreenController.shared.toggle()
    SystemMonitor.shared.attach()
    _ = AppearanceController.shared
}
// Let the monitors fill most of the CPU graph's one-minute history.
RunLoop.main.run(until: Date().addingTimeInterval(45))

MainActor.assumeIsolated {
    // Fixed results, like the battery widgets' sample devices: a real scan
    // depends on when this Mac was last cleaned.
    CleanupController.shared.showSampleResults(
        [.caches: 4_100_000_000, .developer: 2_300_000_000, .trash: 820_000_000, .logs: 6_000_000],
        availableCapacity: 221_200_000_000
    )

    let featuresDirectory = marketing.appendingPathComponent("features")
    try? FileManager.default.removeItem(at: featuresDirectory)
    try! FileManager.default.createDirectory(at: featuresDirectory, withIntermediateDirectories: true)

    let hero = CGSize(width: 1440, height: 900)
    for dark in [true, false] {
        useAppearance(dark: dark)
        save(Hero(store: makeStore(heroTiles), dark: dark, size: hero), marketing.appendingPathComponent("hero-\(dark ? "dark" : "light").png"))
    }

    useAppearance(dark: true)
    save(Overview(store: makeStore(heroTiles), dark: true), marketing.appendingPathComponent("x-overview.png"))

    let features = Feature.everything
    for feature in features {
        save(FeatureCard(feature: feature, dark: true), featuresDirectory.appendingPathComponent("\(feature.slug).png"))
    }
    updateReadme(with: features)

    CaffeineController.shared.toggle()
    StayGreenController.shared.toggle()
}
