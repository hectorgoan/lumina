import SwiftUI

/// A world clock's settings: whether and how it appears in the menu bar.
struct WorldClockSettings: View {
    @Environment(UtilityStore.self) private var store
    let clockID: String
    let city: WorldClockCity

    var body: some View {
        let display = store.worldClock(withID: clockID)?.menuBar ?? .off

        VStack(alignment: .leading, spacing: 10) {
            Text("Menu Bar")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            MenuBarPreview(city: city, display: display)

            Picker("Menu Bar", selection: Binding(
                get: { display },
                set: { newValue in
                    withAnimation(.snappy) { store.setMenuBarDisplay(newValue, forClockWithID: clockID) }
                }
            )) {
                Text("Off").tag(WorldClock.MenuBarDisplay.off)
                Text("Time").tag(WorldClock.MenuBarDisplay.time)
                Text("Code & Time").tag(WorldClock.MenuBarDisplay.codeAndTime)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }
}

/// A slice of the menu bar showing how the clock will look there.
private struct MenuBarPreview: View {
    let city: WorldClockCity
    let display: WorldClock.MenuBarDisplay

    var body: some View {
        TimelineView(.everyMinute) { context in
            let moment = WorldClockMoment(city: city, date: context.date)

            VStack(spacing: 6) {
                HStack(spacing: 10) {
                    Spacer(minLength: 0)
                    if display != .off {
                        HStack(spacing: 4) {
                            Text(city.flag)
                                .font(.system(size: 11))
                            if display == .codeAndTime {
                                // Matches the outlined tag in the menu bar.
                                Text(city.code)
                                    .font(.system(size: 8, weight: .semibold))
                                    .tracking(0.3)
                                    .padding(.horizontal, 3)
                                    .padding(.vertical, 1)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 3)
                                            .strokeBorder(.primary, lineWidth: 0.8)
                                    }
                            }
                            Text([moment.time, moment.period].compactMap { $0 }.joined(separator: " "))
                                .monospacedDigit()
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .trailing)))
                    }
                    Image(systemName: "rays")
                        .font(.system(size: 13, weight: .medium))
                    Text(context.date, format: .dateTime.weekday(.abbreviated).hour().minute())
                }
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(Color.panelControl, in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                Text(display == .off ? "Not shown in the menu bar" : "Shown in the menu bar")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
            }
        }
        .accessibilityHidden(true)
    }
}
