import SwiftUI
import UserNotifications

@main
struct LuminaApp: App {
    // Held directly: the app struct is created once for the process lifetime.
    private let store = UtilityStore()
    private let notificationPresenter = NotificationPresenter()

    init() {
        UNUserNotificationCenter.current().delegate = notificationPresenter
    }

    var body: some Scene {
        MenuBarExtra {
            PanelView()
                .environment(store)
        } label: {
            MenuBarLabel(pomodoro: .shared)
        }
        .menuBarExtraStyle(.window)
    }
}

/// The menu bar icon, followed by the Pomodoro countdown while one is under way.
private struct MenuBarLabel: View {
    let pomodoro: PomodoroController

    var body: some View {
        if pomodoro.isInProgress {
            Image(nsImage: Self.render(time: pomodoro.formattedRemaining))
        } else {
            Image(systemName: "rays")
        }
    }

    /// The menu bar shows only the first image or text of a label, so the
    /// icon and the time are drawn together into one template image, centered
    /// on each other.
    private static func render(time: String) -> NSImage {
        let content = HStack(spacing: 4) {
            Image(systemName: "rays")
                .font(.system(size: 13, weight: .medium))
            Text(time)
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()
        }
        .foregroundStyle(.black)
        .frame(height: 18)

        let renderer = ImageRenderer(content: content)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = renderer.nsImage ?? NSImage()
        image.isTemplate = true
        return image
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
