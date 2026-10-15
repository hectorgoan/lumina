import SwiftUI

extension Utility {
    static let appearance = Utility(
        id: "appearance",
        name: "Appearance",
        symbol: "circle.lefthalf.filled",
        content: { AnyView(AppearanceModule(controller: .shared)) }
    )
}

/// Switches the system between Light and Dark appearance.
struct AppearanceModule: View {
    let controller: AppearanceController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ModuleToggleButton(
                    symbol: "circle.lefthalf.filled",
                    isOn: controller.mode == .dark,
                    action: controller.toggle
                )

                VStack(alignment: .leading, spacing: 1) {
                    Text("Appearance")
                        .font(.system(size: 13, weight: .semibold))
                    Text(controller.mode.title)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .contentTransition(.interpolate)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                ForEach(AppearanceController.Mode.allCases) { mode in
                    AppearanceOption(mode: mode, isSelected: controller.mode == mode) {
                        controller.set(mode)
                    }
                }
            }

            if controller.needsPermission {
                notice(
                    "Allow Lumina to control System Events to change the appearance.",
                    action: ("Open Settings", controller.openAutomationSettings)
                )
            } else if controller.failed {
                notice("The appearance couldn’t be changed.", action: nil)
            }
        }
        .animation(.snappy(duration: 0.25), value: controller.mode)
        .animation(.snappy, value: controller.needsPermission)
    }

    private func notice(_ message: String, action: (String, () -> Void)?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text(message)
                    .fixedSize(horizontal: false, vertical: true)
                if let action {
                    Button(action.0, action: action.1)
                        .buttonStyle(.link)
                }
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .transition(.opacity)
    }
}

/// A selectable thumbnail like the ones in System Settings › Appearance.
private struct AppearanceOption: View {
    let mode: AppearanceController.Mode
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                AppearanceThumbnail(mode: mode)
                    .overlay {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(.tint, lineWidth: 2.5)
                            .padding(-4)
                            .opacity(isSelected ? 1 : 0)
                    }
                    .padding(4)

                Text(mode.title)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel("\(mode.title) appearance")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A miniature desktop with a window, drawn in the given appearance.
private struct AppearanceThumbnail: View {
    let mode: AppearanceController.Mode

    private var isDark: Bool { mode == .dark }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)

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
                .frame(height: 5)

            // Window
            HStack(spacing: 0) {
                Rectangle()
                    .fill(isDark ? Color(white: 0.20) : Color(white: 0.90))
                    .frame(width: 18)
                    .overlay(alignment: .topLeading) {
                        HStack(spacing: 1.5) {
                            Circle().fill(.red)
                            Circle().fill(.yellow)
                            Circle().fill(.green)
                        }
                        .frame(height: 3)
                        .padding(3)
                    }
                VStack(alignment: .leading, spacing: 3) {
                    Capsule().frame(width: 26, height: 3)
                    Capsule().frame(width: 18, height: 3)
                    Capsule().frame(width: 22, height: 3)
                }
                .foregroundStyle(isDark ? Color(white: 0.38) : Color(white: 0.82))
                .padding(5)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(isDark ? Color(white: 0.13) : Color.white)
            }
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            .frame(width: 70, height: 36)
            .padding(.leading, 12)
            .padding(.top, 13)
        }
        .frame(height: 54)
        .frame(maxWidth: .infinity)
        .clipShape(shape)
        .overlay { shape.strokeBorder(.black.opacity(0.12), lineWidth: 0.5) }
    }
}
