import SwiftUI

extension Utility {
    static let keyboardLock = Utility(
        id: "keyboardLock",
        name: "Keyboard Lock",
        symbol: "keyboard",
        size: .half,
        content: { AnyView(KeyboardLockModule(controller: .shared)) }
    )
}

/// Blocks keyboard input while the keyboard is being cleaned.
struct KeyboardLockModule: View {
    let controller: KeyboardLockController

    var body: some View {
        CompactToggleModule(
            title: "Keyboard",
            status: status,
            symbol: controller.isLocked ? "lock.fill" : "keyboard",
            tint: .orange,
            isOn: controller.isLocked,
            action: controller.toggle
        )
        .help(help)
    }

    private var status: String {
        if controller.isLocked { return "Locked" }
        if controller.needsPermission { return "Needs Access" }
        return "Unlocked"
    }

    private var help: String {
        if controller.isLocked { return "Keyboard input is blocked. Click to unlock." }
        if controller.needsPermission {
            return "Allow Lumina in System Settings › Privacy & Security › Accessibility, then click again."
        }
        return "Block the keyboard so you can clean it."
    }
}
