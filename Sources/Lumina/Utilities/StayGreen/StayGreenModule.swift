import SwiftUI

extension Utility {
    static let stayGreen = Utility(
        id: "stayGreen",
        name: "Stay Green",
        symbol: "person.crop.circle.badge.checkmark",
        size: .half,
        content: { AnyView(StayGreenModule(controller: .shared)) }
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
            tint: .green,
            isOn: controller.isActive,
            action: controller.toggle
        )
        .help(controller.isActive ? "Chat apps will keep showing you as available." : "Keep showing as available in chat apps like Teams.")
    }
}
