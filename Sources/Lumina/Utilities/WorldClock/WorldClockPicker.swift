import SwiftUI

/// Picks a city for a new world clock, in place of the grid.
struct WorldClockPicker: View {
    @Environment(UtilityStore.self) private var store
    @StateObject private var search = PickerSearch()
    @FocusState private var isSearchFocused: Bool

    /// Rows shown at once; more specific searches narrow the list.
    private static let maximumResults = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button(action: close) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .help("Back to Utilities")
                .keyboardShortcut(.cancelAction)

                Text("Add World Clock")
                    .font(.system(size: 15, weight: .semibold))

                Spacer()
            }

            searchField

            VStack(alignment: .leading, spacing: 2) {
                if search.query.isEmpty {
                    Text("Suggested")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 8)
                        .padding(.bottom, 2)
                }

                if results.isEmpty {
                    Text("No Cities Found")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 60)
                } else {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, city in
                        Button { add(city) } label: {
                            CityRow(city: city, isSelected: index == search.selection)
                        }
                        .buttonStyle(.plain)
                        .onHover { if $0 { search.selection = index } }
                    }
                }
            }
            .padding(6)
            .background(Color.panelSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .onAppear { isSearchFocused = true }
        .onChange(of: search.query) { search.selection = 0 }
        // Edit mode's sidebar previews the highlighted city.
        .onChange(of: highlightedCode, initial: true) { _, code in store.previewCityCode = code }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Search Cities", text: $search.query)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($isSearchFocused)
                .onSubmit { results.indices.contains(search.selection) ? add(results[search.selection]) : () }
                .onKeyPress(.downArrow) { moveSelection(by: 1) }
                .onKeyPress(.upArrow) { moveSelection(by: -1) }
            if !search.query.isEmpty {
                Button {
                    search.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Clear")
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(Color.panelTrack, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var results: [WorldClockCity] {
        guard search.query.isEmpty else {
            return Array(WorldClockCity.search(search.query).prefix(Self.maximumResults))
        }
        // Suggest popular cities the user doesn't have a clock for yet.
        let added = Set(store.worldClocks.map(\.cityCode))
        return WorldClockCity.suggestedCodes
            .filter { !added.contains($0) }
            .compactMap(WorldClockCity.city(withCode:))
            .prefix(Self.maximumResults / 2)
            .map { $0 }
    }

    private var highlightedCode: String? {
        results.indices.contains(search.selection) ? results[search.selection].code : nil
    }

    private func moveSelection(by step: Int) -> KeyPress.Result {
        guard !results.isEmpty else { return .ignored }
        search.selection = min(max(search.selection + step, 0), results.count - 1)
        return .handled
    }

    private func add(_ city: WorldClockCity) {
        store.swapPage(adding: { store.addWorldClock(for: city) })
    }

    private func close() {
        store.swapPage { store.isAddingWorldClock = false }
    }
}

/// The picker's search text and highlighted row.
private final class PickerSearch: ObservableObject {
    @Published var query = ""
    @Published var selection = 0
}

/// A city in the picker: flag, name, country and code, and its current time.
private struct CityRow: View {
    let city: WorldClockCity
    let isSelected: Bool

    var body: some View {
        TimelineView(.everyMinute) { context in
            let moment = WorldClockMoment(city: city, date: context.date)

            HStack(spacing: 9) {
                Text(city.flag)
                    .font(.system(size: 16))
                VStack(alignment: .leading, spacing: 0) {
                    Text(city.name)
                        .font(.system(size: 12, weight: .medium))
                    Text("\(city.country) · \(city.code)")
                        .font(.system(size: 10))
                        .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.secondary))
                }
                .lineLimit(1)
                Spacer(minLength: 4)
                Text([moment.time, moment.period].compactMap { $0 }.joined(separator: " "))
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
            }
            .foregroundStyle(isSelected ? .white : .primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
