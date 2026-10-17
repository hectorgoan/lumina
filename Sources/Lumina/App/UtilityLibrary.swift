import SwiftUI

/// The sidebar shown beside the panel in edit mode: hidden utilities to
/// bring back, and new widgets to add. Click + or drag one into the panel.
/// The well at the bottom previews the row under the pointer.
struct UtilityLibrary: View {
    @Environment(UtilityStore.self) private var store
    @StateObject private var search = LibrarySearch()
    @StateObject private var hover = LibraryHover()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Library")
                .font(.system(size: 15, weight: .semibold))

            searchField

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    section("Hidden")
                    if hidden.isEmpty {
                        Text(search.query.isEmpty ? "Everything is in the panel." : "No matches.")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .padding(.vertical, 6)
                    }
                    ForEach(hidden, id: \.id) { utility in
                        LibraryRow(
                            symbol: utility.symbol, title: utility.name, detail: utility.size.title,
                            isPreviewed: hover.item == .utility(utility.id)
                        ) {
                            store.showTile(utility)
                        }
                        .onHover { hover.point(at: .utility(utility.id), $0) }
                        .draggable(LibraryDrag.utility(utility.id))
                    }

                    if !newItems.isEmpty {
                        section("Add New").padding(.top, 8)
                    }
                    ForEach(newItems, id: \.self) { item in
                        LibraryRow(
                            symbol: item.symbol, title: item.title, detail: item.detail,
                            isPreviewed: hover.item == .new(item)
                        ) {
                            open(item)
                        }
                        .onHover { hover.point(at: .new(item), $0) }
                        .draggable(LibraryDrag.new(item))
                    }
                }
                // Room for the highlight around a row, which runs past
                // the titles' edge.
                .padding(.horizontal, 6)
            }
            .scrollIndicators(.never)
            .padding(.horizontal, -6)

            Spacer(minLength: 0)

            LibraryPreviewWell(item: previewed)
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Search", text: $search.query)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
            if !search.query.isEmpty {
                Button {
                    search.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Clear")
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 26)
        .background(Color.panelTrack, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func section(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.bottom, 2)
    }

    /// The row the well shows: the last one pointed at, while it's still
    /// in the Library.
    private var previewed: LibraryItem? {
        switch hover.item {
        case .utility(let id) where hidden.contains(where: { $0.id == id }):
            hover.item
        case .new(let item) where newItems.contains(item):
            hover.item
        default:
            nil
        }
    }

    private var hidden: [Utility] {
        store.hiddenUtilities.filter { matches($0.name) }
    }

    private var newItems: [LibraryDrag.NewItem] {
        LibraryDrag.NewItem.allCases.filter { matches($0.title) }
    }

    private func matches(_ name: String) -> Bool {
        search.query.isEmpty || name.localizedStandardContains(search.query)
    }

    private func open(_ item: LibraryDrag.NewItem) {
        LibraryDrag.open(item, in: store)
    }
}

/// What the library hands to the panel when a row is dragged.
enum LibraryDrag {
    enum NewItem: String, CaseIterable {
        case worldClock, batteries

        var title: String {
            switch self {
            case .worldClock: "World Clock"
            case .batteries: "Batteries"
            }
        }

        var detail: String {
            switch self {
            case .worldClock: "Half width · choose a city"
            case .batteries: "Four sizes"
            }
        }

        var symbol: String {
            switch self {
            case .worldClock: "clock"
            case .batteries: "battery.75percent"
            }
        }
    }

    private static let utilityPrefix = "lumina-utility:"
    private static let newPrefix = "lumina-new:"

    static func utility(_ id: String) -> String { utilityPrefix + id }
    static func new(_ item: NewItem) -> String { newPrefix + item.rawValue }

    /// Acts on a drop onto the panel; returns whether it was one of ours.
    @MainActor
    static func handle(_ payload: String, in store: UtilityStore) -> Bool {
        if payload.hasPrefix(utilityPrefix) {
            let id = String(payload.dropFirst(utilityPrefix.count))
            guard let utility = store.hiddenUtilities.first(where: { $0.id == id }) else { return false }
            store.showTile(utility)
            return true
        }
        if payload.hasPrefix(newPrefix), let item = NewItem(rawValue: String(payload.dropFirst(newPrefix.count))) {
            open(item, in: store)
            return true
        }
        return false
    }

    /// Opens the add page for a new widget.
    @MainActor
    static func open(_ item: NewItem, in store: UtilityStore) {
        store.swapPage {
            switch item {
            case .worldClock: store.isAddingWorldClock = true
            case .batteries: store.isAddingBatteryWidget = true
            }
        }
    }
}

/// A row of the Library.
enum LibraryItem: Equatable {
    case utility(String)
    case new(LibraryDrag.NewItem)
}

/// The row under the pointer. Leaving a row clears it after a beat, so
/// moving across the gap to the next row doesn't flash the well empty.
@MainActor
private final class LibraryHover: ObservableObject {
    @Published var item: LibraryItem?
    private var clearing: Task<Void, Never>?

    func point(at row: LibraryItem, _ isInside: Bool) {
        if isInside {
            clearing?.cancel()
            item = row
        } else if item == row {
            clearing?.cancel()
            clearing = Task {
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled, item == row else { return }
                item = nil
            }
        }
    }
}

/// The bottom of the Library: the row under the pointer, as it will look in
/// the panel. Always the same size, so nothing resizes as it changes.
private struct LibraryPreviewWell: View {
    @Environment(UtilityStore.self) private var store
    let item: LibraryItem?
    @StateObject private var heights = PreviewHeights()

    /// The room the tile gets.
    private static let tileArea = CGSize(width: 186, height: 104)

    var body: some View {
        VStack(spacing: 8) {
            if let preview {
                let height = heights.values[preview.id]
                let scale = min(1, Self.tileArea.width / preview.width, height.map { Self.tileArea.height / $0 } ?? 1)
                ScaledLayout(scale: scale) {
                    ModuleTile(isEditing: false, isLifted: false) {
                        preview.content
                    } badges: {
                        EmptyView()
                    }
                    .frame(width: preview.width)
                    .onGeometryChange(for: CGFloat.self, of: \.size.height) { height in
                        if heights.values[preview.id] != height { heights.values[preview.id] = height }
                    }
                    .scaleEffect(scale, anchor: .topLeading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // A preview, not a second copy to use.
                .allowsHitTesting(false)
                .id(preview.id)
                .transition(.opacity)

                VStack(spacing: 1) {
                    Text(preview.caption)
                        .font(.system(size: 10, weight: .medium))
                    Text("Click + or drag it into the panel")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .lineLimit(1)
            } else {
                Spacer(minLength: 0)
                Image(systemName: "hand.point.up.left")
                    .font(.system(size: 18))
                    .foregroundStyle(.tertiary)
                Text("Point at a utility to preview it.\nClick + or drag it into the panel.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                Spacer(minLength: 0)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 160, maxHeight: 160)
        .background(Color.panelTrack.opacity(0.5), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .animation(.snappy(duration: 0.2), value: preview?.id)
    }

    private struct Preview {
        let id: String
        let width: CGFloat
        let caption: String
        let content: AnyView
    }

    private var preview: Preview? {
        let metrics = TileGridMetrics(width: 296, spacing: 10)
        switch item {
        case .utility(let id):
            guard let utility = store.utilities.first(where: { $0.id == id }) else { return nil }
            return Preview(
                id: id,
                width: metrics.width(forSpan: utility.size.span),
                caption: "\(utility.name) · \(utility.size.title)",
                content: utility.content()
            )
        case .new(.worldClock):
            guard let city = WorldClockCity.city(withCode: "TYO") ?? WorldClockCity.all.first else { return nil }
            return Preview(
                id: "new.worldClock",
                width: metrics.width(forSpan: Utility.Size.half.span),
                caption: "World Clock · Half width",
                content: AnyView(WorldClockCard(city: city))
            )
        case .new(.batteries):
            let widget = BatteryWidget(id: "preview", size: .large)
            return Preview(
                id: "new.batteries",
                width: metrics.width(forSpan: widget.size.tileSize.span),
                caption: "Batteries · Four sizes",
                content: AnyView(BatteryWidgetContent(size: .large, devices: widget.shownDevices(from: BatteryMonitor.shared.devices)))
            )
        case nil:
            return nil
        }
    }
}

/// Each previewed tile's height at full size, to fit it in the well.
private final class PreviewHeights: ObservableObject {
    @Published var values: [String: CGFloat] = [:]
}

/// A library entry: icon, name and size, with a green + to add it.
private struct LibraryRow: View {
    let symbol: String
    let title: String
    let detail: String
    /// Shown in the well: highlighted, so it's clear which row that is.
    var isPreviewed = false
    let add: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 26, height: 26)
                .background(Color.panelTrack, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Button(action: add) {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(.green))
            }
            .buttonStyle(PressableButtonStyle())
            .help("Add \(title)")
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.panelTrack.opacity(isPreviewed ? 0.7 : 0))
        )
        .padding(.horizontal, -6)
        .contentShape(Rectangle())
        .animation(.snappy(duration: 0.15), value: isPreviewed)
    }
}

/// The library's search text.
private final class LibrarySearch: ObservableObject {
    @Published var query = ""
}

/// Whether something from the library is being dragged over the panel.
final class LibraryDropTarget: ObservableObject {
    @Published var isTargeted = false
}
