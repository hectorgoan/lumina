import SwiftUI
import UserNotifications

@main
struct LuminaApp: App {
    // Held directly: the app struct is created once for the process lifetime.
    private let store = UtilityStore()
    private let notificationPresenter = NotificationPresenter()

    init() {
        UNUserNotificationCenter.current().delegate = notificationPresenter
        // Start the updater at launch so its daily checks run even if the
        // panel is never opened.
        _ = UpdateController.shared
    }

    var body: some Scene {
        MenuBarExtra {
            PanelView()
                .environment(store)
        } label: {
            MenuBarLabel(pomodoro: .shared, caffeine: .shared, stayGreen: .shared)
        }
        .menuBarExtraStyle(.window)
    }
}

/// The menu bar icon with its status badges, followed by the Pomodoro
/// countdown while one is under way.
private struct MenuBarLabel: View {
    let pomodoro: PomodoroController
    let caffeine: CaffeineController
    let stayGreen: StayGreenController

    var body: some View {
        Image(nsImage: Self.render(
            status: MenuBarStatus(isCaffeinated: caffeine.isActive, isStayingGreen: stayGreen.isActive),
            time: pomodoro.isInProgress ? pomodoro.formattedRemaining : nil
        ))
    }

    /// The menu bar shows only the first image or text of a label, so the
    /// badged icon and the time are drawn together into one template image.
    /// It's always drawn this way so the icon keeps the same size and position
    /// whatever its state.
    private static func render(status: MenuBarStatus, time: String?) -> NSImage {
        let content = HStack(spacing: 5) {
            MenuBarIconView(status: status)
            if let time {
                Text(time)
                    .font(.system(size: 13, weight: .medium))
                    .monospacedDigit()
            }
        }
        .foregroundStyle(.black)
        .frame(height: 18)

        let renderer = ImageRenderer(content: content)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = renderer.nsImage ?? NSImage()
        image.isTemplate = true
        image.accessibilityDescription = accessibilityDescription(for: status, time: time)
        return image
    }

    private static func accessibilityDescription(for status: MenuBarStatus, time: String?) -> String {
        var parts = ["Lumina"]
        if status.isCaffeinated { parts.append("Caffeine on") }
        if status.isStayingGreen { parts.append("Stay Green on") }
        if let time { parts.append("Pomodoro \(time)") }
        return parts.joined(separator: ", ")
    }
}

/// Shows Lumina's notifications even while its panel is open.
private final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }
}
