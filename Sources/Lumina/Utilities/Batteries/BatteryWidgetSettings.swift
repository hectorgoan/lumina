import SwiftUI

/// A battery widget's settings: its name, its size, and which devices it
/// shows.
struct BatteryWidgetSettings: View {
    @Environment(UtilityStore.self) private var store
    let widgetID: String
    private let monitor = BatteryMonitor.shared

    var body: some View {
        if let widget = store.batteryWidget(withID: widgetID) {
            content(for: widget)
        }
    }

    private func content(for widget: BatteryWidget) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Name")
                    .font(.system(size: 13))
                Spacer()
                // Plain, on the panel's own fill, like the More section's.
                TextField("Batteries", text: Binding(
                    get: { widget.name ?? "" },
                    set: { name in
                        var updated = widget
                        updated.name = name
                        update(updated)
                    }
                ))
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(.horizontal, 8)
                .frame(width: 140, height: 24)
                .background(Color.panelTrack, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }

            Divider()

            Text("Size")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            FullWidthSegmentedPicker(
                options: BatteryWidget.Size.allCases.map { ($0.shortTitle, $0) },
                selection: Binding(
                    get: { widget.size },
                    set: { newSize in
                        var updated = widget
                        updated.size = newSize
                        // Keep only as many chosen devices as the new size shows.
                        updated.chosenDevices = Array(widget.chosenDevices.prefix(newSize.capacity))
                        update(updated)
                    }
                )
            )
            .accessibilityLabel("Size")

            Divider()

            Toggle("Choose Automatically", isOn: Binding(
                get: { widget.choosesAutomatically },
                set: { automatic in
                    var updated = widget
                    updated.choosesAutomatically = automatic
                    update(updated)
                }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .font(.system(size: 13))

            Text(caption(for: widget))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .contentTransition(.opacity)

            Divider()

            VStack(spacing: 0) {
                ForEach(rows(for: widget), id: \.id) { row in
                    deviceRow(row, in: widget)
                }
            }
        }
    }

    // MARK: - Device list

    /// A device to list: connected now, or chosen and out of range.
    private struct Row {
        let id: String
        let name: String
        let symbol: String
        let device: BatteryDevice?
    }

    private func rows(for widget: BatteryWidget) -> [Row] {
        let connected = monitor.devices.map { Row(id: $0.id, name: $0.name, symbol: $0.symbol, device: $0) }
        let connectedIDs = Set(connected.map(\.id))
        let away = widget.chosenDevices
            .filter { !connectedIDs.contains($0.id) }
            .map { Row(id: $0.id, name: $0.name, symbol: $0.symbol, device: nil) }
        return connected + away
    }

    private func deviceRow(_ row: Row, in widget: BatteryWidget) -> some View {
        let isChosen = widget.chosenDevices.contains { $0.id == row.id }
        let isFull = widget.chosenDevices.count >= widget.size.capacity
        let isEnabled = !widget.choosesAutomatically && (isChosen || !isFull)

        return Button {
            toggle(row, in: widget)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isChosen && !widget.choosesAutomatically ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(isChosen && !widget.choosesAutomatically ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                    .contentTransition(.symbolEffect(.replace))
                    .animation(.snappy(duration: 0.2), value: isChosen)
                Image(systemName: row.symbol)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 18)
                Text(row.name)
                    .font(.system(size: 12))
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text(row.device.map(BatteryFormat.percent) ?? "Not connected")
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled || isChosen ? 1 : 0.4)
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }

    private func caption(for widget: BatteryWidget) -> String {
        if widget.choosesAutomatically {
            return "Shows the devices with the lowest charge first."
        }
        let capacity = widget.size.capacity
        return "Choose up to \(capacity) \(capacity == 1 ? "device" : "devices") · \(widget.chosenDevices.count) chosen"
    }

    private func toggle(_ row: Row, in widget: BatteryWidget) {
        var updated = widget
        if let index = updated.chosenDevices.firstIndex(where: { $0.id == row.id }) {
            updated.chosenDevices.remove(at: index)
        } else if updated.chosenDevices.count < updated.size.capacity {
            updated.chosenDevices.append(.init(id: row.id, name: row.name, symbol: row.symbol))
        }
        update(updated)
    }

    private func update(_ widget: BatteryWidget) {
        store.updateBatteryWidget(widget)
    }
}
