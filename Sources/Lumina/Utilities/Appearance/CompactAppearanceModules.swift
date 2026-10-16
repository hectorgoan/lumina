import SwiftUI

extension Utility {
    /// Just the two previews, at half width. Hidden by default.
    static let compactAppearance = Utility(
        id: "compactAppearance",
        name: "Compact Appearance",
        symbol: "circle.lefthalf.filled",
        size: .half,
        content: { AnyView(CompactAppearanceModule(controller: .shared)) },
        isHiddenByDefault: true
    )

    /// The Appearance header with the previews beside it, in one row.
    /// Hidden by default.
    static let appearanceRow = Utility(
        id: "appearanceRow",
        name: "Appearance Row",
        symbol: "circle.lefthalf.filled",
        size: .full,
        content: { AnyView(AppearanceRowModule(controller: .shared)) },
        isHiddenByDefault: true
    )
}

/// The Light and Dark previews side by side; click one to switch.
struct CompactAppearanceModule: View {
    let controller: AppearanceController

    var body: some View {
        HStack(spacing: 10) {
            ForEach(AppearanceController.Mode.allCases) { mode in
                PreviewButton(mode: mode, isSelected: controller.mode == mode) {
                    controller.set(mode)
                }
                .frame(height: 30)
            }
        }
        .padding(.horizontal, 3)
        .overlay(alignment: .topTrailing) {
            if controller.needsPermission || controller.failed {
                // No room for the full notice: a badge that explains on hover
                // and opens the Automation settings when it's about access.
                Button(action: controller.openAutomationSettings) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.white, .orange)
                }
                .buttonStyle(.plain)
                .offset(x: 8, y: -8)
                .help(controller.needsPermission
                    ? "Allow Lumina to control System Events to change the appearance. Click to open Settings."
                    : "The appearance couldn’t be changed.")
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.25), value: controller.mode)
        .animation(.snappy, value: controller.needsPermission)
    }
}

/// Today's Appearance header with small previews beside it, in one row.
struct AppearanceRowModule: View {
    let controller: AppearanceController

    var body: some View {
        HStack(spacing: 10) {
            ModuleToggleButton(
                symbol: "circle.lefthalf.filled",
                isOn: controller.mode == .dark,
                action: controller.toggle
            )

            VStack(alignment: .leading, spacing: 1) {
                Text("Appearance")
                    .font(.system(size: 13, weight: .semibold))
                if controller.needsPermission {
                    Button("Allow in Settings", action: controller.openAutomationSettings)
                        .buttonStyle(.link)
                        .font(.system(size: 11))
                        .help("Allow Lumina to control System Events to change the appearance.")
                } else {
                    Text(controller.mode.title)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .contentTransition(.interpolate)
                }
            }

            Spacer(minLength: 0)

            ForEach(AppearanceController.Mode.allCases) { mode in
                PreviewButton(mode: mode, isSelected: controller.mode == mode) {
                    controller.set(mode)
                }
                .frame(width: 46, height: 30)
            }
            .padding(.trailing, 3)
        }
        .animation(.snappy(duration: 0.25), value: controller.mode)
        .animation(.snappy, value: controller.needsPermission)
    }
}

/// A small, clickable preview with the selection ring.
private struct PreviewButton: View {
    let mode: AppearanceController.Mode
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            AppearancePreview(mode: mode)
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(.tint, lineWidth: 2)
                        .padding(-3)
                        .opacity(isSelected ? 1 : 0)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .help("\(mode.title) appearance")
        .accessibilityLabel("\(mode.title) appearance")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The same miniature desktop as the full module's thumbnails, drawn in
/// proportion so it reads at small sizes.
private struct AppearancePreview: View {
    let mode: AppearanceController.Mode

    private var isDark: Bool { mode == .dark }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)

        GeometryReader { proxy in
            let width = proxy.size.width, height = proxy.size.height

            ZStack(alignment: .topLeading) {
                LinearGradient(
                    colors: isDark
                        ? [Color(red: 0.10, green: 0.13, blue: 0.32), Color(red: 0.33, green: 0.18, blue: 0.45)]
                        : [Color(red: 0.42, green: 0.70, blue: 0.98), Color(red: 0.78, green: 0.86, blue: 1.00)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                // Menu bar
                Rectangle()
                    .fill(isDark ? Color.black.opacity(0.35) : Color.white.opacity(0.55))
                    .frame(height: height * 0.09)

                // Window
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(isDark ? Color(white: 0.20) : Color(white: 0.90))
                        .frame(width: width * 0.2)
                        .overlay(alignment: .topLeading) {
                            HStack(spacing: 1) {
                                Circle().fill(.red)
                                Circle().fill(.yellow)
                                Circle().fill(.green)
                            }
                            .frame(height: max(1.5, height * 0.06))
                            .padding(max(1.5, width * 0.03))
                        }
                    VStack(alignment: .leading, spacing: height * 0.06) {
                        Capsule().frame(width: width * 0.28, height: max(1.2, height * 0.06))
                        Capsule().frame(width: width * 0.2, height: max(1.2, height * 0.06))
                    }
                    .foregroundStyle(isDark ? Color(white: 0.38) : Color(white: 0.82))
                    .padding(width * 0.05)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(isDark ? Color(white: 0.13) : Color.white)
                }
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                .shadow(color: .black.opacity(0.25), radius: 1.5, y: 0.5)
                .frame(width: width * 0.72, height: height * 0.66)
                .offset(x: width * 0.14, y: height * 0.24)
            }
        }
        .clipShape(shape)
        .overlay { shape.strokeBorder(.black.opacity(0.12), lineWidth: 0.5) }
        // Static artwork: flatten its gradients and shadow into one layer.
        .drawingGroup()
    }
}
