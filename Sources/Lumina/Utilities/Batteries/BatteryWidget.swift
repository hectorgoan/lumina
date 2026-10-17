import SwiftUI

/// A battery widget the user added, with its size and chosen devices.
struct BatteryWidget: Codable, Hashable {
    enum Size: String, Codable, CaseIterable, Identifiable {
        case small, medium, large, extraLarge

        var id: Self { self }

        var title: String {
            switch self {
            case .small: "Small"
            case .medium: "Medium"
            case .large: "Large"
            case .extraLarge: "Extra Large"
            }
        }

        var shortTitle: String {
            switch self {
            case .small: "S"
            case .medium: "M"
            case .large: "L"
            case .extraLarge: "XL"
            }
        }

        /// How many devices the widget shows.
        var capacity: Int {
            switch self {
            case .small: 1
            case .medium: 2
            case .large: 4
            case .extraLarge: 6
            }
        }

        var tileSize: Utility.Size {
            switch self {
            case .small: .quarter
            case .medium: .half
            case .large, .extraLarge: .full
            }
        }

        /// For example "Shows 4 devices · Full width".
        var summary: String {
            let width = switch tileSize {
            case .quarter: "Quarter width"
            case .half: "Half width"
            case .full: "Full width"
            }
            return "Shows \(capacity) \(capacity == 1 ? "device" : "devices") · \(width)"
        }
    }

    /// A device the user chose. Its name and icon are kept so it can still
    /// be listed while it's out of range.
    struct ChosenDevice: Codable, Hashable {
        let id: String
        let name: String
        let symbol: String
    }

    /// The utility ID.
    let id: String
    var size: Size
    /// The name the user gave it, like "Desk". Optional, so widgets saved
    /// before names existed still load.
    var name: String?
    /// Shows the devices with the lowest charge first instead of chosen ones.
    var choosesAutomatically = true
    /// The chosen devices, in the order they were chosen.
    var chosenDevices: [ChosenDevice] = []

    /// The name as shown, or nil when it has none.
    var title: String? {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The widget at another size, keeping only as many chosen devices as
    /// it shows.
    func resized(to newSize: Size) -> BatteryWidget {
        var resized = self
        resized.size = newSize
        resized.chosenDevices = Array(chosenDevices.prefix(newSize.capacity))
        return resized
    }

    /// The devices to show, out of those currently reporting a battery.
    func shownDevices(from devices: [BatteryDevice]) -> [BatteryDevice] {
        let shown = choosesAutomatically
            ? devices.sorted { $0.level < $1.level }
            : chosenDevices.compactMap { chosen in devices.first { $0.id == chosen.id } }
        return Array(shown.prefix(size.capacity))
    }
}

extension Utility {
    static func batteryWidget(_ widget: BatteryWidget) -> Utility {
        Utility(
            id: widget.id,
            name: widget.title ?? "Batteries",
            symbol: "battery.75percent",
            size: widget.size.tileSize,
            content: { AnyView(BatteryWidgetView(widgetID: widget.id)) },
            settings: { AnyView(BatteryWidgetSettings(widgetID: widget.id)) },
            isRemovable: true
        )
    }
}

/// A battery widget in the grid, kept current with its configuration and
/// the live device list.
struct BatteryWidgetView: View {
    @Environment(UtilityStore.self) private var store
    let widgetID: String

    var body: some View {
        if let widget = store.batteryWidget(withID: widgetID) {
            BatteryWidgetContent(size: widget.size, devices: widget.shownDevices(from: BatteryMonitor.shared.devices), name: widget.title)
        }
    }
}

/// The widget's layout for a size: rings for S, M and L, a list for XL,
/// with its name, if it has one, as a quiet caption above. S has no room
/// for it: there the name shows on hover.
struct BatteryWidgetContent: View {
    let size: BatteryWidget.Size
    let devices: [BatteryDevice]
    var name: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let name, size != .small {
                Text(name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            widget
        }
    }

    private var widget: some View {
        Group {
            if devices.isEmpty {
                VStack(spacing: 3) {
                    Image(systemName: "battery.0percent")
                        .font(.system(size: 15))
                    if size != .small {
                        Text("No Devices")
                            .font(.system(size: 11))
                    }
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 30)
            } else {
                switch size {
                case .small, .medium, .large:
                    rings
                case .extraLarge:
                    list
                }
            }
        }
    }

    private var rings: some View {
        let ringSize: CGFloat = size == .large ? 40 : 34
        return HStack(spacing: 0) {
            ForEach(Array(devices.enumerated()), id: \.element.id) { index, device in
                if index > 0 { Spacer(minLength: 4) }
                BatteryRingItem(device: device, ringSize: ringSize, widgetName: size == .small ? name : nil)
            }
        }
        .padding(.horizontal, devices.count > 1 ? 8 : 0)
        .frame(maxWidth: .infinity)
    }

    private var list: some View {
        VStack(spacing: 0) {
            ForEach(Array(devices.enumerated()), id: \.element.id) { index, device in
                if index > 0 {
                    Divider().padding(.leading, 30)
                }
                BatteryListRow(device: device)
            }
        }
    }
}

// MARK: - Pieces

/// A ring that fills with the device's charge, its icon in the middle.
struct BatteryRing: View {
    let device: BatteryDevice
    var size: CGFloat = 40

    private var color: Color { device.isLow ? .red : .green }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.panelTrack, lineWidth: size * 0.1)
            Circle()
                .trim(from: 0, to: device.level)
                .stroke(color.gradient, style: StrokeStyle(lineWidth: size * 0.1, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.smooth(duration: 0.6), value: device.level)
            Image(systemName: device.symbol)
                .font(.system(size: size * 0.36, weight: .medium))
        }
        .frame(width: size, height: size)
        .overlay(alignment: .topTrailing) {
            if device.isCharging {
                Image(systemName: "bolt.fill")
                    .font(.system(size: size * 0.2, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: size * 0.36, height: size * 0.36)
                    .background(Circle().fill(.green))
                    .overlay(Circle().strokeBorder(.background, lineWidth: 1.5))
                    .offset(x: size * 0.08, y: -size * 0.08)
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }
}

/// A ring with the charge below; the device's name shows on hover, after
/// the widget's when the widget has no room to show it.
private struct BatteryRingItem: View {
    let device: BatteryDevice
    let ringSize: CGFloat
    var widgetName: String?

    var body: some View {
        VStack(spacing: 4) {
            BatteryRing(device: device, size: ringSize)
            Text(BatteryFormat.percent(device))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .help(widgetName.map { "\($0) · \(device.name)" } ?? device.name)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(widgetName.map { "\($0), \(device.name)" } ?? device.name)
        .accessibilityValue(BatteryFormat.accessibilityValue(device))
    }
}

/// A row of the XL list, like macOS's own Batteries widget.
private struct BatteryListRow: View {
    let device: BatteryDevice

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: device.symbol)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 20)
            Text(device.name)
                .font(.system(size: 12))
                .lineLimit(1)
            Spacer(minLength: 6)
            Text(BatteryFormat.percent(device))
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
            BatteryGlyph(device: device)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(device.name)
        .accessibilityValue(BatteryFormat.accessibilityValue(device))
    }
}

/// A small battery outline filled to the device's charge.
private struct BatteryGlyph: View {
    let device: BatteryDevice

    var body: some View {
        HStack(spacing: 1) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(.secondary, lineWidth: 1)
                    .frame(width: 22, height: 11)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(device.isLow ? Color.red : Color.green)
                    .frame(width: max(2, 18 * device.level), height: 7)
                    .padding(.leading, 2)
                    .animation(.smooth(duration: 0.6), value: device.level)
                if device.isCharging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 22)
                }
            }
            RoundedRectangle(cornerRadius: 1)
                .fill(.secondary)
                .frame(width: 1.5, height: 4)
        }
    }
}

enum BatteryFormat {
    static func percent(_ device: BatteryDevice) -> String {
        "\(Int((device.level * 100).rounded()))%"
    }

    static func accessibilityValue(_ device: BatteryDevice) -> String {
        percent(device) + (device.isCharging ? ", charging" : "")
    }
}
