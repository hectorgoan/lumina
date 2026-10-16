import SwiftUI

/// The states the menu bar icon reflects.
struct MenuBarStatus: Equatable {
    var isCaffeinated = false
    var isStayingGreen = false
    var stayGreenIndicator = StayGreenIndicator()

    /// Whether the icon has a green part right now, so it can't be drawn as
    /// a single-color template image.
    var showsGreen: Bool { isStayingGreen && stayGreenIndicator.isGreen }
}

/// The Lumina menu bar icon with its status badges.
///
/// - Caffeine fills the rays' empty center, turning them into a sun: awake.
/// - Stay Green shows the indicator chosen in its settings: a dot in place
///   of the bottom-right ray, a ring around the center, or green rays.
///
/// Everything stays inside its 22 × 18 point canvas, since the menu bar
/// crops the image to it.
struct MenuBarIconView: View {
    /// Which parts to draw. The menu bar draws the icon's own color and its
    /// green separately, so the first can follow the menu bar's appearance.
    enum Layer {
        case all, ink, green
    }

    let status: MenuBarStatus
    var foreground: Color = .black
    var layer: Layer = .all

    var body: some View {
        let indicator = status.isStayingGreen ? status.stayGreenIndicator : nil
        let shape = indicator?.shape ?? .none
        let isGreen = indicator?.isGreen ?? false

        ZStack {
            MenuBarRays(omitsBottomRight: shape == .dot)
                .fill(color(isGreen: shape == .rays))

            if status.isCaffeinated {
                // A smaller center leaves room for the halo.
                let size: CGFloat = shape == .halo ? 4.5 : 6
                Circle()
                    .fill(color(isGreen: false))
                    .frame(width: size, height: size)
            }

            switch shape {
            case .dot:
                // Where the bottom-right ray would be.
                Circle()
                    .fill(color(isGreen: isGreen))
                    .frame(width: 5.6, height: 5.6)
                    .offset(x: 6.8 * 0.7071, y: 6.8 * 0.7071)
            case .halo:
                Circle()
                    .strokeBorder(color(isGreen: isGreen), lineWidth: 1.3)
                    .frame(width: 9.5, height: 9.5)
            case .none, .rays:
                EmptyView()
            }
        }
        .frame(width: 22, height: 18)
    }

    private func color(isGreen: Bool) -> Color {
        switch layer {
        case .all: isGreen ? .luminaGreen : foreground
        case .ink: isGreen ? .clear : foreground
        case .green: isGreen ? .luminaGreen : .clear
        }
    }
}

/// The icon's eight rays, drawn rather than taken from the "rays" symbol so
/// one can make way for the Stay Green dot.
struct MenuBarRays: Shape {
    var omitsBottomRight = false

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let inner = 4.9, outer = 8.0
        var path = Path()
        // Index 1 is the ray pointing down and to the right (y grows down).
        for index in 0..<8 where !(omitsBottomRight && index == 1) {
            let angle = Double(index) * .pi / 4
            var ray = Path()
            ray.move(to: CGPoint(x: center.x + cos(angle) * inner, y: center.y + sin(angle) * inner))
            ray.addLine(to: CGPoint(x: center.x + cos(angle) * outer, y: center.y + sin(angle) * outer))
            path.addPath(ray.strokedPath(StrokeStyle(lineWidth: 1.55, lineCap: .round)))
        }
        return path
    }
}
