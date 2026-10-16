import SwiftUI

/// Adds a battery widget: pick a size, see it with your devices in edit
/// mode's preview beside the page, add it.
struct BatteryWidgetPicker: View {
    @Environment(UtilityStore.self) private var store

    var body: some View {
        @Bindable var store = store

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
                selection: $store.newBatteryWidgetSize
            )
            .accessibilityLabel("Size")

            Text("Shows the devices with the lowest charge first. Choose devices in its settings after adding it.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: add) {
                Text("Add Widget").frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
    }

    private func add() {
        store.swapPage(adding: { store.addBatteryWidget(size: store.newBatteryWidgetSize) })
    }

    private func close() {
        store.swapPage { store.isAddingBatteryWidget = false }
    }
}
