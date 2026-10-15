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
        CompactToggleModule(
            title: "Caffeine",
            status: controller.isActive ? "On" : "Off",
            symbol: controller.isActive ? "cup.and.saucer.fill" : "cup.and.saucer",
            isOn: controller.isActive,
            action: controller.toggle
        )
        .help(controller.isActive ? "Your Mac and its display won’t go to sleep." : "Keep your Mac and its display awake.")
    }
}
