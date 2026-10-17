import SwiftUI

/// Takes the Library's place beside a settings or add page in edit mode:
/// the tile being configured, as it will look in the panel, updating as
/// it changes. The Library comes back with the grid, so nothing can be
/// added to a grid that isn't showing.
struct UtilityPreview: View {
    @Environment(UtilityStore.self) private var store
    private let monitor = BatteryMonitor.shared

    /// The room the tile gets inside the sidebar.
    private static let tileArea = CGSize(width: 186, height: 160)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preview")
                .font(.system(size: 15, weight: .semibold))
            Text("As it will look in the panel.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            VStack(spacing: 10) {
                if let subject {
                    let scale = min(1, Self.tileArea.width / subject.width)
                    ScaledLayout(scale: scale) {
                        ModuleTile(isEditing: false, isLifted: false) {
                            subject.content
                        } badges: {
                            EmptyView()
                        }
                        .frame(width: subject.width)
                        .scaleEffect(scale, anchor: .topLeading)
                    }
                    .id(subject.id)
                    .transition(.opacity)
                    // A preview, not a second copy to use.
                    .allowsHitTesting(false)
                    .frame(maxHeight: Self.tileArea.height)
                }
                Text(subject?.caption ?? "Choose a city to see its clock.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            // The same height whatever it shows, so the sidebar (and the
            // panel) never resize while it updates.
            .frame(maxWidth: .infinity, minHeight: 200, maxHeight: 200)
            .background(Color.panelTrack.opacity(0.5), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.top, 4)
            .animation(.snappy(duration: 0.25), value: subject?.id)

            Spacer(minLength: 0)

            Text("The Library comes back when you go back.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    // MARK: - What to preview

    private struct Subject {
        /// Changes when the tile does, so it can crossfade.
        let id: String
        let width: CGFloat
        let caption: String
        let content: AnyView
    }

    private var subject: Subject? {
        let metrics = TileGridMetrics(width: 296, spacing: 10)

        if store.isMoreSettingsOpen {
            return Subject(
                id: "more-\(store.moreStyle.rawValue)",
                width: Self.tileArea.width,
                caption: "\(store.moreStyle.title) · \(store.moreStyle.summary)",
                content: AnyView(MoreStyleThumbnail(style: store.moreStyle, scale: 2).frame(maxWidth: .infinity))
            )
        }

        if store.isAddingBatteryWidget {
            let widget = store.newBatteryWidget
            let size = widget.size
            return Subject(
                id: "batteries-\(size.rawValue)",
                width: metrics.width(forSpan: size.tileSize.span),
                caption: "\(size.title) · \(size.summary)",
                content: AnyView(BatteryWidgetContent(size: size, devices: widget.shownDevices(from: monitor.devices), name: widget.title))
            )
        }

        if store.isAddingWorldClock {
            guard let city = store.previewCityCode.flatMap(WorldClockCity.city(withCode:)) else { return nil }
            return Subject(
                id: "clock-\(city.code)",
                width: metrics.width(forSpan: Utility.Size.half.span),
                caption: "\(city.name), \(city.country) · Half width",
                content: AnyView(WorldClockCard(city: city))
            )
        }

        if let utility = store.settingsUtility {
            var caption = utility.size.title
            if let widget = store.batteryWidget(withID: utility.id) {
                caption = "\(widget.size.title) · \(widget.size.summary)"
            }
            return Subject(
                id: "\(utility.id)-\(utility.size.span)",
                width: metrics.width(forSpan: utility.size.span),
                caption: caption,
                content: utility.content()
            )
        }

        return nil
    }
}

/// Lays its view out at full size but takes up `scale` times the room,
/// for a view drawn with a matching `scaleEffect(_:anchor: .topLeading)`.
/// A scale effect alone doesn't change the room a view takes.
struct ScaledLayout: Layout {
    let scale: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let view = subviews.first else { return .zero }
        let size = view.sizeThatFits(.unspecified)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: .unspecified)
    }
}
