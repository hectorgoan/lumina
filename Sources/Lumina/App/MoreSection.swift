import SwiftUI

/// What the panel's grid holds: utilities, plus the More section's header
/// and, in edit mode while the section is empty, a hint to drop tiles in.
enum PanelGridItem: Identifiable {
    case utility(Utility)
    case moreHeader
    case moreHint

    var id: String {
        switch self {
        case .utility(let utility): utility.id
        case .moreHeader: "lumina.more.header"
        case .moreHint: "lumina.more.hint"
        }
    }

    var span: Int {
        if case .utility(let utility) = self { return utility.size.span }
        return TileGridMetrics.columns
    }

    var utility: Utility? {
        if case .utility(let utility) = self { return utility }
        return nil
    }
}

extension UtilityStore {
    /// The grid's items. Outside edit mode: the utilities on show, then the
    /// section's header and, while it's open, its utilities (or, for Pages,
    /// one page or the other). In edit mode the section is always open.
    var panelGridItems: [PanelGridItem] {
        let main = mainUtilities.map(PanelGridItem.utility)
        let more = moreUtilities.map(PanelGridItem.utility)
        if isLibraryExpanded {
            return main + [.moreHeader] + (more.isEmpty ? [.moreHint] : more)
        }
        guard !more.isEmpty else { return main }
        if moreStyle == .pages { return isMoreOpen ? more : main }
        return main + [.moreHeader] + (isMoreOpen ? more : [])
    }

    /// Applies an order from the edit grid.
    func applyPanelGridOrder(_ items: [PanelGridItem]) {
        guard let header = items.firstIndex(where: { $0.id == PanelGridItem.moreHeader.id }) else { return }
        reorder(
            main: items[..<header].compactMap(\.utility),
            more: items[(header + 1)...].compactMap(\.utility)
        )
    }
}

// MARK: - Outside edit mode

/// The section's header outside edit mode: a row (Row) or a stack of cards
/// (Stack) while closed; a title with Show Less while open as a stack.
struct MoreHeader: View {
    @Environment(UtilityStore.self) private var store

    var body: some View {
        Group {
            switch store.moreStyle {
            case .row, .pages: row
            case .stack: store.isMoreOpen ? AnyView(stackTitle) : AnyView(stack)
            }
        }
        .moreSectionMenu(store: store)
    }

    private var row: some View {
        Button(action: store.toggleMore) {
            HStack(spacing: 8) {
                Text(store.moreTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                icons(size: 18)
                    .opacity(store.isMoreOpen ? 0 : 1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(store.isMoreOpen ? 180 : 0))
            }
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(Capsule().fill(Color.panelSurface.opacity(0.6)))
            .contentShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .animation(.snappy(duration: 0.25), value: store.isMoreOpen)
        .help(store.isMoreOpen ? "Close \(store.moreTitle)" : "Open \(store.moreTitle)")
    }

    /// The tucked-away utilities as a stack of cards, like grouped
    /// notifications.
    private var stack: some View {
        Button(action: store.toggleMore) {
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.panelSurface.opacity(0.45))
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .offset(y: 12)
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.panelSurface.opacity(0.75))
                    .padding(.horizontal, 7)
                    .frame(height: 44)
                    .offset(y: 6)
                HStack(spacing: 8) {
                    icons(size: 24, overlap: true)
                    Text(store.moreUtilities.count == 1 ? "1 more" : "\(store.moreUtilities.count) more")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .frame(height: 44)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.panelSurface))
            }
            .frame(height: 58, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .help("Show \(store.moreTitle)")
        .opacity(store.isMoreFading ? 0 : 1)
    }

    private var stackTitle: some View {
        HStack {
            Text(store.moreTitle)
                .font(.system(size: 12, weight: .semibold))
            Spacer()
            Button("Show Less", action: store.toggleMore)
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tint)
        }
        .padding(.horizontal, 4)
        .frame(height: 22)
        .opacity(store.isMoreFading ? 0 : 1)
    }

    /// The section's utilities' symbols, up to four.
    private func icons(size: CGFloat, overlap: Bool = false) -> some View {
        HStack(spacing: overlap ? -6 : 4) {
            ForEach(store.moreUtilities.prefix(4), id: \.id) { utility in
                Image(systemName: utility.symbol)
                    .font(.system(size: size * 0.45, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: size, height: size)
                    .background(Circle().fill(Color.panelControl))
                    .overlay {
                        if overlap { Circle().strokeBorder(Color.panelSurface, lineWidth: 2) }
                    }
            }
        }
    }
}

/// The Pages style's dots, under the grid.
struct MorePageDots: View {
    @Environment(UtilityStore.self) private var store

    var body: some View {
        HStack(spacing: 6) {
            ForEach([false, true], id: \.self) { isMore in
                let isCurrent = store.isMoreOpen == isMore
                Button { store.showMorePage(isMore) } label: {
                    Circle()
                        .fill(Color.primary.opacity(isCurrent ? 0.85 : 0.3))
                        .frame(width: 7, height: 7)
                        .padding(4)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(isMore ? store.moreTitle : "Utilities")
            }
        }
        .frame(maxWidth: .infinity)
        .moreSectionMenu(store: store)
    }
}

extension View {
    /// Right-click on the section: open or close it, remember that, or go
    /// to its settings.
    func moreSectionMenu(store: UtilityStore) -> some View {
        contextMenu {
            Button(store.isMoreOpen ? "Close \(store.moreTitle)" : "Open \(store.moreTitle)") {
                if store.moreStyle == .pages { store.showMorePage(!store.isMoreOpen) } else { store.toggleMore() }
            }
            Toggle("Remember Open or Closed", isOn: Binding(
                get: { store.remembersMoreOpen },
                set: { store.remembersMoreOpen = $0 }
            ))
            Divider()
            Button("\(store.moreTitle) Section Settings…") { store.openMoreSettings() }
        }
    }
}

// MARK: - Edit mode

/// The section's header in edit mode: its name, a gear badge for its
/// settings, and what it's for.
struct MoreEditHeader: View {
    @Environment(UtilityStore.self) private var store

    var body: some View {
        HStack(spacing: 8) {
            Text(store.moreTitle)
                .font(.system(size: 12, weight: .semibold))
            Text("Shown when opened")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            EditBadge(symbol: "gearshape.fill", help: "\(store.moreTitle) Section Settings") {
                store.openMoreSettings()
            }
        }
        .padding(.horizontal, 4)
        .frame(height: 24)
    }
}

/// Fills the empty section in edit mode.
struct MoreDropHint: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(.tint, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            .frame(height: 50)
            .overlay {
                Text("Drag utilities here to tuck them away")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tint)
            }
    }
}

/// Collects the frames of the section's parts in edit mode, to outline it.
struct MoreSectionBounds: PreferenceKey {
    static let defaultValue: [Anchor<CGRect>] = []
    static func reduce(value: inout [Anchor<CGRect>], nextValue: () -> [Anchor<CGRect>]) {
        value += nextValue()
    }
}

// MARK: - Settings

/// The section's settings: its style, its name, and whether it remembers
/// being open.
struct MoreSettingsPage: View {
    @Environment(UtilityStore.self) private var store

    var body: some View {
        @Bindable var store = store

        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Button {
                    store.swapPage { store.isMoreSettingsOpen = false }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .help("Back to Utilities")
                .keyboardShortcut(.cancelAction)

                Text("\(store.moreTitle) Section")
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)

                Spacer()
            }

            ModuleTile(isEditing: false, isLifted: false) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Style")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        ForEach(MoreStyle.allCases, id: \.self) { style in
                            let isSelected = store.moreStyle == style
                            Button { store.moreStyle = style } label: {
                                VStack(spacing: 6) {
                                    MoreStyleThumbnail(style: style, isSelected: isSelected)
                                    Text(style.title)
                                        .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                                        .foregroundStyle(isSelected ? .primary : .secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PressableButtonStyle())
                            .accessibilityLabel(style.title)
                            .accessibilityAddTraits(isSelected ? .isSelected : [])
                        }
                    }
                    .animation(.snappy(duration: 0.2), value: store.moreStyle)

                    // The same height whichever style, so the page never
                    // resizes.
                    Text(store.moreStyle.summary)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(2, reservesSpace: true)

                    Divider()

                    HStack {
                        Text("Name")
                            .font(.system(size: 13))
                        Spacer()
                        TextField("More", text: $store.moreName)
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.small)
                            .frame(width: 120)
                    }

                    Toggle("Remember Open or Closed", isOn: $store.remembersMoreOpen)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .font(.system(size: 13))
                    Text("Off: the section starts closed each time you open the panel.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } badges: {
                EmptyView()
            }
        }
    }
}

/// A small drawing of a style, for the settings and the preview.
struct MoreStyleThumbnail: View {
    let style: MoreStyle
    var isSelected = false
    var scale: CGFloat = 1

    var body: some View {
        VStack(spacing: 3 * scale) {
            ForEach(0..<2, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 3 * scale).fill(Color.primary.opacity(0.22)).frame(height: 10 * scale)
            }
            switch style {
            case .row:
                Capsule().fill(Color.primary.opacity(0.4)).frame(height: 6 * scale)
            case .pages:
                HStack(spacing: 3 * scale) {
                    Circle().fill(Color.primary.opacity(0.9)).frame(width: 4 * scale)
                    Circle().fill(Color.primary.opacity(0.35)).frame(width: 4 * scale)
                }
                .frame(height: 6 * scale)
            case .stack:
                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: 3 * scale).fill(Color.primary.opacity(0.18))
                        .frame(height: 8 * scale).padding(.horizontal, 4 * scale).offset(y: 3 * scale)
                    RoundedRectangle(cornerRadius: 3 * scale).fill(Color.primary.opacity(0.4)).frame(height: 8 * scale)
                }
                .frame(height: 11 * scale, alignment: .top)
            }
        }
        .padding(7 * scale)
        .frame(width: 72 * scale, height: 50 * scale)
        .background(RoundedRectangle(cornerRadius: 8 * scale, style: .continuous).fill(Color.panelTrack))
        .overlay {
            RoundedRectangle(cornerRadius: 10 * scale, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2.5)
                .padding(-3)
        }
    }
}
