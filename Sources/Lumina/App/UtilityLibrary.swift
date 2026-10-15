import SwiftUI

/// The sidebar shown beside the panel in edit mode: hidden utilities to
/// bring back, and new widgets to add. Click + or drag one into the panel.
struct UtilityLibrary: View {
    @Environment(UtilityStore.self) private var store
    @StateObject private var search = LibrarySearch()

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
                        LibraryRow(symbol: utility.symbol, title: utility.name, detail: utility.size.title) {
                            withAnimation(.snappy) { store.show(utility) }
                        }
                        .draggable(LibraryDrag.utility(utility.id))
                    }

                    if !newItems.isEmpty {
                        section("Add New").padding(.top, 8)
                    }
                    ForEach(newItems, id: \.self) { item in
                        LibraryRow(symbol: item.symbol, title: item.title, detail: item.detail) {
                            withAnimation(.snappy) { open(item) }
                        }
                        .draggable(LibraryDrag.new(item))
                    }
                }
            }
            .scrollIndicators(.never)

            Spacer(minLength: 0)

            Text("Drag into the panel or click +")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
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
        .background(.fill.secondary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func section(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.bottom, 2)
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
        switch item {
        case .worldClock: store.isAddingWorldClock = true
        case .batteries: store.isAddingBatteryWidget = true
        }
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
            store.show(utility)
            return true
        }
        if payload.hasPrefix(newPrefix), let item = NewItem(rawValue: String(payload.dropFirst(newPrefix.count))) {
            switch item {
            case .worldClock: store.isAddingWorldClock = true
            case .batteries: store.isAddingBatteryWidget = true
            }
            return true
        }
        return false
    }
}

/// A library entry: icon, name and size, with a green + to add it.
private struct LibraryRow: View {
    let symbol: String
    let title: String
    let detail: String
    let add: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 26, height: 26)
                .background(.fill.secondary, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
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
        .contentShape(Rectangle())
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
