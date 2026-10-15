import SwiftUI

@main
struct LuminaApp: App {
    // Held directly: the app struct is created once for the process lifetime.
    private let store = UtilityStore()

    var body: some Scene {
        MenuBarExtra("Lumina", systemImage: "rays") {
            PanelView()
                .environment(store)
        }
        .menuBarExtraStyle(.window)
    }
}
