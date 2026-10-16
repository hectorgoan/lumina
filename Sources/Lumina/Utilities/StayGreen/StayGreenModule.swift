import SwiftUI

extension Utility {
    static let stayGreen = Utility(
        id: "stayGreen",
        name: "Stay Green",
        symbol: "person.crop.circle.badge.checkmark",
        size: .half,
        content: { AnyView(StayGreenModule(controller: .shared)) },
        settings: { AnyView(StayGreenSettings(controller: .shared)) }
    )
}

/// Keeps chat apps showing you as available while switched on.
struct StayGreenModule: View {
    let controller: StayGreenController

    var body: some View {
        CompactToggleModule(
            title: "Stay Green",
            status: controller.isActive ? "Available" : "Off",
            symbol: "person.crop.circle.badge.checkmark",
            tint: .luminaGreen,
            isOn: controller.isActive,
            action: controller.toggle
        )
        .help(controller.isActive ? "Chat apps will keep showing you as available." : "Keep showing as available in chat apps like Teams.")
    }
}

/// Stay Green's settings: how the menu bar icon shows it's on.
struct StayGreenSettings: View {
    @Bindable var controller: StayGreenController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            preview

            Text("Menu Bar Indicator")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 2)

            FullWidthSegmentedPicker(
                options: StayGreenIndicator.Shape.allCases.map { ($0.title, $0) },
                selection: $controller.indicator.shape
            )
            .accessibilityLabel("Menu Bar Indicator")

            Divider()

            Toggle("Show in Green", isOn: Binding(
                get: { controller.indicator.isGreen },
                set: { controller.indicator.prefersGreen = $0 }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .font(.system(size: 13))
            .disabled(controller.indicator.shape == .none || controller.indicator.shape == .rays)

            Text(caption)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The menu bar icon as it looks with Stay Green on.
    private var preview: some View {
        let status = MenuBarStatus(
            isCaffeinated: CaffeineController.shared.isActive,
            isStayingGreen: true,
            stayGreenIndicator: controller.indicator
        )
        return VStack(spacing: 8) {
            HStack(spacing: 14) {
                MenuBarIconView(status: status, foreground: .primary)
                    .scaleEffect(1.7)
                    .frame(width: 38, height: 30)
                Image(systemName: "wifi")
                    .font(.system(size: 15, weight: .medium))
                Text(Date(), format: .dateTime.hour().minute())
                    .font(.system(size: 14))
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(Color.panelTrack, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text("\(controller.indicator.title) · \(controller.indicator.summary)")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview: \(controller.indicator.summary)")
    }

    private var caption: String {
        switch controller.indicator.shape {
        case .none: "Lumina’s icon stays the same while Stay Green is on."
        case .rays: "Rays are always green, so they stand out from the icon."
        case .dot, .halo: "Green is the color chat apps use for available."
        }
    }
}
