import SwiftUI

/// A round ↻ button that scans again. Clicking it turns the arrow once,
/// quickly, as a reaction; it stays dimmed and disabled while the scan runs.
struct RefreshButton: View {
    let isWorking: Bool
    var help = "Scan Now"
    let action: () -> Void
    @StateObject private var taps = TapCount()

    var body: some View {
        Button {
            taps.count += 1
            action()
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 11, weight: .semibold))
                .symbolEffect(.rotate.clockwise, options: .speed(1.6), value: taps.count)
                .foregroundStyle(isWorking ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.panelTrack))
                .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(isWorking)
        .help(help)
        .accessibilityLabel(help)
    }
}

@MainActor
private final class TapCount: ObservableObject {
    @Published var count = 0
}
