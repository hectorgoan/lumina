import SwiftUI

/// The rounded platter every utility sits on, mirroring Control Center modules.
struct ModuleTile<Content: View>: View {
    var isEditing: Bool
    var isLifted: Bool
    @ViewBuilder var content: Content

    private let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)

    var body: some View {
        content
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .allowsHitTesting(!isEditing)
            .background(.fill.quaternary, in: shape)
            .overlay {
                shape.strokeBorder(.separator.opacity(isEditing ? 1 : 0.4), lineWidth: 0.5)
            }
            .overlay(alignment: .topTrailing) {
                if isEditing {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 19)
                        .padding(.trailing, 16)
                        .transition(.opacity.combined(with: .scale(scale: 0.6)))
                }
            }
            .scaleEffect(isLifted ? 1.03 : 1)
            .shadow(color: .black.opacity(isLifted ? 0.22 : 0), radius: 14, y: 8)
            .animation(.snappy(duration: 0.2), value: isLifted)
    }
}

/// A circular toggle in the style of Control Center: filled with its tint
/// (the accent color by default) when on, a translucent fill when off.
struct ModuleToggleButton: View {
    let symbol: String
    var tint: Color = .accentColor
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isOn ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .frame(width: 30, height: 30)
                .background {
                    Circle().fill(isOn ? AnyShapeStyle(tint) : AnyShapeStyle(.fill.secondary))
                }
                .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .animation(.snappy(duration: 0.2), value: isOn)
    }
}

/// The layout for a half-width utility: a toggle with a title and status.
struct CompactToggleModule: View {
    let title: String
    let status: String
    let symbol: String
    var tint: Color = .accentColor
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ModuleToggleButton(symbol: symbol, tint: tint, isOn: isOn, action: action)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(status)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .contentTransition(.interpolate)
            }
            .lineLimit(1)

            Spacer(minLength: 0)
        }
        .animation(.snappy(duration: 0.25), value: isOn)
    }
}

/// Subtle press feedback for custom-drawn controls.
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}
