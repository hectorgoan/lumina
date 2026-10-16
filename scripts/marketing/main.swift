import AppKit
import SwiftUI

// Renders Lumina's marketing images from the app's real views.
// Usage: render <output-directory>

_ = NSApplication.shared
let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1])

// MARK: - App state

@MainActor
func makeStore(includeAppearance: Bool) -> UtilityStore {
    // A throwaway defaults suite, so renders don't depend on saved layouts.
    let defaults = UserDefaults(suiteName: "lumina.render.\(UUID().uuidString)")!
    let store = UtilityStore(defaults: defaults)
    let madrid = store.addWorldClock(for: WorldClockCity.city(withCode: "MAD")!)!
    let newYork = store.addWorldClock(for: WorldClockCity.city(withCode: "NYC")!)!
    let batteries = store.addBatteryWidget(size: .large)

    var order = ["caffeine", "stayGreen", madrid, newYork, "pomodoro", batteries]
    if includeAppearance { order.insert("appearance", at: 0) }
    let byID = Dictionary(uniqueKeysWithValues: store.utilities.map { ($0.id, $0) })
    for utility in store.visibleUtilities where !order.contains(utility.id) {
        store.toggleVisibility(of: utility)
    }
    store.reorder(order.compactMap { byID[$0] })
    return store
}

MainActor.assumeIsolated {
    CaffeineController.shared.toggle()
    StayGreenController.shared.toggle()
    SystemMonitor.shared.attach()
}
// Let the monitors fill most of the CPU graph's one-minute history.
RunLoop.main.run(until: Date().addingTimeInterval(45))

// MARK: - Scene pieces

struct Wallpaper: View {
    let dark: Bool

    var body: some View {
        ZStack {
            LinearGradient(
                colors: dark
                    ? [Color(red: 0.05, green: 0.06, blue: 0.20), Color(red: 0.16, green: 0.10, blue: 0.40), Color(red: 0.36, green: 0.16, blue: 0.48)]
                    : [Color(red: 0.62, green: 0.78, blue: 0.98), Color(red: 0.80, green: 0.80, blue: 0.98), Color(red: 0.98, green: 0.82, blue: 0.86)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            GeometryReader { proxy in
                let w = proxy.size.width, h = proxy.size.height
                Ellipse()
                    .fill(dark ? Color(red: 0.12, green: 0.55, blue: 0.75).opacity(0.55) : Color(red: 0.45, green: 0.75, blue: 0.95).opacity(0.55))
                    .frame(width: w * 0.9, height: h * 0.55)
                    .rotationEffect(.degrees(-18))
                    .offset(x: -w * 0.25, y: h * 0.62)
                    .blur(radius: 90)
                Ellipse()
                    .fill(dark ? Color(red: 0.85, green: 0.35, blue: 0.55).opacity(0.45) : Color(red: 1.0, green: 0.65, blue: 0.70).opacity(0.5))
                    .frame(width: w * 0.7, height: h * 0.5)
                    .rotationEffect(.degrees(22))
                    .offset(x: w * 0.55, y: h * 0.55)
                    .blur(radius: 110)
                Ellipse()
                    .fill(dark ? Color(red: 0.35, green: 0.25, blue: 0.85).opacity(0.5) : Color(red: 0.70, green: 0.62, blue: 0.98).opacity(0.5))
                    .frame(width: w * 0.8, height: h * 0.45)
                    .offset(x: w * 0.1, y: -h * 0.12)
                    .blur(radius: 120)
            }
        }
    }
}

struct MenuBar: View {
    let dark: Bool
    var compact = false

    var body: some View {
        let ink: Color = dark ? .white : .black
        HStack(spacing: 0) {
            if !compact {
                HStack(spacing: 20) {
                    Image(systemName: "applelogo").font(.system(size: 15, weight: .medium))
                    Text("Finder").font(.system(size: 13, weight: .bold))
                    ForEach(["File", "Edit", "View", "Go", "Window", "Help"], id: \.self) {
                        Text($0).font(.system(size: 13))
                    }
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 16) {
                // A world clock pinned to the menu bar.
                HStack(spacing: 4) {
                    Text("🇪🇸").font(.system(size: 11))
                    Text("MAD")
                        .font(.system(size: 9, weight: .semibold)).tracking(0.3)
                        .padding(.horizontal, 3).padding(.vertical, 1)
                        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(ink, lineWidth: 0.8))
                    Text(time(in: "Europe/Madrid")).font(.system(size: 13)).monospacedDigit()
                }
                // Lumina's own item, highlighted because its panel is open.
                MenuBarIconView(status: MenuBarStatus(isCaffeinated: true, isStayingGreen: true), foreground: ink)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                .background(ink.opacity(0.18), in: Capsule())
                Image(systemName: "wifi").font(.system(size: 14, weight: .medium))
                Image(systemName: "battery.75percent").font(.system(size: 15))
                if !compact {
                    Image(systemName: "switch.2").font(.system(size: 13, weight: .medium))
                }
                if compact {
                    Text(Date(), format: .dateTime.weekday(.abbreviated).hour().minute())
                        .font(.system(size: 13))
                } else {
                    Text(Date(), format: .dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
                        .font(.system(size: 13))
                }
            }
            .fixedSize()
        }
        .foregroundStyle(ink)
        .padding(.horizontal, 16)
        .frame(height: 30)
        .background(dark ? Color.black.opacity(0.12) : Color.white.opacity(0.2))
    }

    private func time(in zone: String) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: zone)
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: Date())
    }
}

/// The panel: the app's real tiles, laid out by the app's grid layout, on a
/// frosted glass sheet like the menu bar window.
struct Panel: View {
    let store: UtilityStore
    let dark: Bool
    let wallpaperSize: CGSize
    let origin: CGPoint

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
        VStack(spacing: 12) {
            TileGridLayout(spacing: 10) {
                ForEach(MainActor.assumeIsolated { store.visibleUtilities }, id: \.id) { utility in
                    ModuleTile(isEditing: false, isLifted: false) {
                        utility.content()
                    } badges: {
                        EmptyView()
                    }
                    .layoutValue(key: TileSpan.self, value: utility.size.span)
                }
            }
            .frame(width: 296)

            HStack(spacing: 8) {
                Text("Edit Utilities")
                    .font(.system(size: 13, weight: .medium))
                    .frame(maxWidth: .infinity, minHeight: 32)
                    .background(glassFill, in: Capsule())
                    .overlay(Capsule().strokeBorder(glassEdge, lineWidth: 0.6))
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 32, height: 32)
                    .background(glassFill, in: Circle())
                    .overlay(Circle().strokeBorder(glassEdge, lineWidth: 0.6))
            }
            .frame(width: 296)
        }
        .padding(12)
        .environment(store)
        .background {
            // Frosted glass: the wallpaper right behind the panel, blurred and
            // tinted. Sized by the panel, lined up with the real wallpaper.
            GeometryReader { _ in
                Wallpaper(dark: dark)
                    .frame(width: wallpaperSize.width, height: wallpaperSize.height)
                    .offset(x: -origin.x, y: -origin.y)
                    .blur(radius: 30)
            }
            .overlay(shape.fill(dark ? Color(white: 0.08).opacity(0.55) : Color.white.opacity(0.5)))
            .clipShape(shape)
        }
        .overlay { shape.strokeBorder(glassEdge, lineWidth: 0.8) }
        .shadow(color: .black.opacity(dark ? 0.45 : 0.18), radius: 30, y: 18)
        .environment(\.colorScheme, dark ? .dark : .light)
    }

    private var glassFill: Color { dark ? Color.white.opacity(0.12) : Color.white.opacity(0.55) }
    private var glassEdge: Color { dark ? Color.white.opacity(0.22) : Color.black.opacity(0.08) }
}

// MARK: - Compositions

struct Desktop: View {
    let store: UtilityStore
    let dark: Bool
    let size: CGSize
    /// Puts the panel right under Lumina's menu bar icon.
    var panelTrailing: CGFloat = 116

    var body: some View {
        ZStack(alignment: .topLeading) {
            Wallpaper(dark: dark)
            VStack(spacing: 0) {
                MenuBar(dark: dark)
                Spacer()
            }
            Panel(store: store, dark: dark, wallpaperSize: size, origin: CGPoint(x: size.width - panelTrailing - 320, y: 40))
                .offset(x: size.width - panelTrailing - 320, y: 40)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .environment(\.colorScheme, dark ? .dark : .light)
    }
}

struct SocialCard<Visual: View>: View {
    let eyebrow: String
    let headline: String
    let detail: String
    let dark: Bool
    @ViewBuilder var visual: Visual

    var body: some View {
        ZStack {
            Wallpaper(dark: dark)
            HStack(spacing: 40) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        Image(nsImage: NSImage(contentsOfFile: "docs/icon.png")!)
                            .resizable()
                            .frame(width: 44, height: 44)
                        Text(eyebrow)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    Text(headline)
                        .font(.system(size: 46, weight: .bold))
                        .lineSpacing(-4)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(detail)
                        .font(.system(size: 19))
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: 360, alignment: .leading)
                visual
            }
            .padding(.horizontal, 56)
        }
        .frame(width: 800, height: 450)
        .clipped()
        .environment(\.colorScheme, dark ? .dark : .light)
    }
}

/// A slice of the desktop: a menu bar strip with the panel hanging below it.
struct PanelShowcase: View {
    let store: UtilityStore
    let dark: Bool
    let height: CGFloat

    var body: some View {
        // The menu bar strip and the panel scale together.
        VStack(alignment: .trailing, spacing: 8) {
            MenuBar(dark: dark, compact: true)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            Panel(store: store, dark: dark, wallpaperSize: CGSize(width: 800, height: 450), origin: CGPoint(x: 420, y: 40))
                .padding(.trailing, 70)
        }
        .frame(width: 400)
        // Scaling doesn't shrink a view's layout size, so set the scaled frame.
        .scaleEffect(height / 800, anchor: .topTrailing)
        .frame(width: 400 * height / 800, height: height, alignment: .topTrailing)
    }
}

struct TilesShowcase: View {
    let store: UtilityStore
    let dark: Bool
    let ids: [String]

    var body: some View {
        let utilities = MainActor.assumeIsolated { store.utilities.filter { ids.contains($0.id) } }
            .sorted { ids.firstIndex(of: $0.id)! < ids.firstIndex(of: $1.id)! }
        Panel(
            store: TilesStore.shared.store(for: store, showing: utilities),
            dark: dark,
            wallpaperSize: CGSize(width: 800, height: 450),
            origin: CGPoint(x: 420, y: 60)
        )
    }
}

/// Reorders a store so a panel shows only the given utilities.
@MainActor
final class TilesStore {
    static let shared = TilesStore()
    func store(for store: UtilityStore, showing utilities: [Utility]) -> UtilityStore {
        for utility in store.visibleUtilities where !utilities.contains(where: { $0.id == utility.id }) {
            store.toggleVisibility(of: utility)
        }
        for utility in store.hiddenUtilities where utilities.contains(where: { $0.id == utility.id }) {
            store.toggleVisibility(of: utility)
        }
        store.reorder(utilities)
        return store
    }
}

// MARK: - Rendering

@MainActor
func save<V: View>(_ view: V, _ name: String, scale: CGFloat = 2) {
    let renderer = ImageRenderer(content: view)
    renderer.scale = scale
    guard let image = renderer.nsImage,
          let rep = NSBitmapImageRep(data: image.tiffRepresentation!),
          let png = rep.representation(using: .png, properties: [:])
    else { print("failed \(name)"); return }
    try! png.write(to: outputDirectory.appendingPathComponent(name))
    print("wrote \(name) \(rep.pixelsWide)x\(rep.pixelsHigh)")
}

MainActor.assumeIsolated {
    try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    let hero = CGSize(width: 1440, height: 900)

    save(Desktop(store: makeStore(includeAppearance: true), dark: true, size: hero), "hero-dark.png")
    save(Desktop(store: makeStore(includeAppearance: false), dark: false, size: hero), "hero-light.png")

    let focusStore = makeStore(includeAppearance: true)
    save(SocialCard(
        eyebrow: "Lumina",
        headline: "Focus tools,\nright in your\nmenu bar.",
        detail: "Caffeine, Stay Green, Pomodoro, world clocks, batteries and more, in one panel that feels like Control Center.",
        dark: true
    ) {
        PanelShowcase(store: focusStore, dark: true, height: 400)
    }, "x-overview.png")

    let widgetStore = makeStore(includeAppearance: false)
    let clocks = widgetStore.worldClocks.map(\.id)
    let battery = widgetStore.batteryWidgets.map(\.id)
    save(SocialCard(
        eyebrow: "Lumina",
        headline: "Everything\nat a glance.",
        detail: "World clocks for every time zone you work with, every device’s battery, and your Mac’s vitals.",
        dark: true
    ) {
        TilesShowcase(store: widgetStore, dark: true, ids: ["cpuFocus"] + clocks + battery)
    }, "x-widgets.png")

    let flowStore = makeStore(includeAppearance: false)
    save(SocialCard(
        eyebrow: "Lumina",
        headline: "Stay in\nthe flow.",
        detail: "Pomodoro timers, Caffeine to keep your Mac awake, Stay Green for chat apps, and one-click Dark Mode.",
        dark: false
    ) {
        TilesShowcase(store: flowStore, dark: false, ids: ["pomodoro", "caffeine", "stayGreen", "keyboardLock", "compactAppearance"])
    }, "x-flow.png")
}
