import SwiftUI

/// Adds a battery widget: pick a size, a name and its devices, see it in
/// edit mode's preview beside the page, add it.
struct BatteryWidgetPicker: View {
    @Environment(UtilityStore.self) private var store

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
                selection: Binding(
                    get: { store.newBatteryWidget.size },
                    set: { store.newBatteryWidget = store.newBatteryWidget.resized(to: $0) }
                )
            )
            .accessibilityLabel("Size")

            HStack {
                Text("Name")
                    .font(.system(size: 13))
                Spacer()
                TextField("Optional", text: Binding(
                    get: { store.newBatteryWidget.name ?? "" },
                    set: { store.newBatteryWidget.name = $0 }
                ))
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .padding(.horizontal, 8)
                    .frame(width: 160, height: 24)
                    .background(Color.panelTrack, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }

            Divider()

            BatteryDeviceChooser(widget: store.newBatteryWidget, update: { store.newBatteryWidget = $0 })

            Button(action: add) {
                Text("Add Widget").frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
    }

    private func add() {
        store.swapPage(adding: {
            store.addBatteryWidget(store.newBatteryWidget)
        })
    }

    private func close() {
        let close = {
            store.isAddingBatteryWidget = false
            store.resetNewBatteryWidget()
        }
        store.swapPage(close)
    }
}
