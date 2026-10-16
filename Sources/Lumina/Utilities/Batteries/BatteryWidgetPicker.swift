import SwiftUI

/// Adds a battery widget: pick a size, see it with your devices, add it.
struct BatteryWidgetPicker: View {
    @Environment(UtilityStore.self) private var store
    @StateObject private var selection = SizeSelection()
    private let monitor = BatteryMonitor.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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

                Text("Add Batteries")
                    .font(.system(size: 15, weight: .semibold))

                Spacer()
            }

            // Short labels: the full names don't fit the panel's width.
            FullWidthSegmentedPicker(
                options: BatteryWidget.Size.allCases.map { ($0.shortTitle, $0) },
                // A closure rather than `set: selection.choose`: passing the
                // main-actor method directly crashes Swift 6.3's compiler
                // (used by the release workflow) while it generates code.
                selection: Binding(get: { selection.size }, set: { selection.choose($0) })
            )
            .accessibilityLabel("Size")

            preview

            Button(action: add) {
                Text("Add Widget").frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
    }

    /// The widget at its real width, with the devices it would show now.
    private var preview: some View {
        let size = selection.shownSize
        let devices = BatteryWidget(id: "preview", size: size).shownDevices(from: monitor.devices)

        return VStack(spacing: 8) {
            GeometryReader { proxy in
                let width = TileGridMetrics(width: proxy.size.width, spacing: 10).width(forSpan: size.tileSize.span)
                ModuleTile(isEditing: false, isLifted: false) {
                    BatteryWidgetContent(size: size, devices: devices)
                } badges: {
                    EmptyView()
                }
                .frame(width: width)
                .frame(maxWidth: .infinity)
            }
            .frame(height: previewHeight(for: size))

            Text("\(size.title) · \(size.summary)")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .opacity(selection.isPreviewVisible ? 1 : 0)
        .padding(10)
        .background(Color.panelSurface.opacity(0.5), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    /// Room for the widget, so the page doesn't jump between sizes.
    private func previewHeight(for size: BatteryWidget.Size) -> CGFloat {
        switch size {
        case .small, .medium: 74
        case .large: 80
        case .extraLarge: CGFloat(min(max(monitor.devices.count, 1), size.capacity)) * 31 + 24
        }
    }

    private func add() {
        store.swapPage(adding: { store.addBatteryWidget(size: selection.size) })
    }

    private func close() {
        store.swapPage { store.isAddingBatteryWidget = false }
    }
}

/// The size picked on the add page, and the one its preview shows.
@MainActor
private final class SizeSelection: ObservableObject {
    @Published var size: BatteryWidget.Size = .large
    /// Catches up with `size` after the preview fades out, so the page
    /// resizes while the preview is invisible, then the preview fades in.
    @Published private(set) var shownSize: BatteryWidget.Size = .large
    @Published private(set) var isPreviewVisible = true
    private var isSwitching = false

    func choose(_ newSize: BatteryWidget.Size) {
        size = newSize
        guard !isSwitching, newSize != shownSize else { return }
        isSwitching = true
        withAnimation(Motion.dismiss, completionCriteria: .removed) {
            isPreviewVisible = false
        } completion: {
            self.showLatestSize()
        }
    }

    private func showLatestSize() {
        withAnimation(Motion.resize, completionCriteria: .removed) {
            shownSize = size
        } completion: {
            withAnimation(Motion.present) { self.isPreviewVisible = true }
            self.isSwitching = false
            // A size picked while switching: catch up with it.
            if self.size != self.shownSize { self.choose(self.size) }
        }
    }
}
