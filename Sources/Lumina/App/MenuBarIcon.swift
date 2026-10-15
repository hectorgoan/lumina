import SwiftUI

/// The states the menu bar icon reflects.
struct MenuBarStatus: Equatable {
    var isCaffeinated = false
    var isStayingGreen = false
}

/// The Lumina menu bar icon with its status badges.
///
/// - Caffeine fills the rays' empty center, turning them into a sun: awake.
/// - Stay Green adds a presence dot in the bottom-right corner, like the one
///   chat apps use for "available".
///
/// It is drawn in a single color so it can be used as a template image.
struct MenuBarIconView: View {
    let status: MenuBarStatus
    var foreground: Color = .black

    var body: some View {
        ZStack {
            Image(systemName: "rays")
                .font(.system(size: 15, weight: .medium))

            if status.isCaffeinated {
                Circle()
                    .frame(width: 6, height: 6)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if status.isStayingGreen {
                // Cut a gap around the dot so it reads as a separate badge.
                Circle()
                    .frame(width: 9, height: 9)
                    .blendMode(.destinationOut)
                    .offset(x: 2.5, y: 2.5)
            }
        }
        .compositingGroup()
        .overlay(alignment: .bottomTrailing) {
            if status.isStayingGreen {
                Circle()
                    .frame(width: 6, height: 6)
                    .offset(x: 1, y: 1)
            }
        }
        .foregroundStyle(foreground)
        .frame(width: 20, height: 18)
    }
}
