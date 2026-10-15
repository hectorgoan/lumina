import SwiftUI

extension Utility {
    static let caffeine = Utility(
        id: "caffeine",
        name: "Caffeine",
        symbol: "cup.and.saucer.fill",
        size: .half,
        content: { AnyView(CaffeineModule(controller: .shared)) }
    )
}

/// Prevents the Mac from sleeping while switched on.
struct CaffeineModule: View {
    let controller: CaffeineController

    var body: some View {
        HStack(spacing: 10) {
            ModuleToggleButton(
                symbol: controller.isActive ? "cup.and.saucer.fill" : "cup.and.saucer",
                isOn: controller.isActive,
                action: controller.toggle
            )

            VStack(alignment: .leading, spacing: 1) {
                Text("Caffeine")
                    .font(.system(size: 13, weight: .semibold))
                Text(controller.isActive ? "On" : "Off")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .contentTransition(.interpolate)
            }
            .lineLimit(1)

            Spacer(minLength: 0)
        }
        .animation(.snappy(duration: 0.25), value: controller.isActive)
        .help(controller.isActive ? "Your Mac won’t go to sleep." : "Keep your Mac from going to sleep.")
    }
}
