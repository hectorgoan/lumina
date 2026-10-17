import SwiftUI

extension Utility {
    static let sleep = Utility(
        id: "sleep", name: "Sleep", symbol: "zzz", size: .half,
        content: { AnyView(SleepModule(layout: .half, controller: .shared)) }
    )
    static let compactSleep = Utility(
        id: "compactSleep", name: "Compact Sleep", symbol: "zzz", size: .quarter,
        content: { AnyView(SleepModule(layout: .quarter, controller: .shared)) },
        isHiddenByDefault: true
    )
    static let silence = Utility(
        id: "silence", name: "Silence", symbol: "speaker.zzz.fill", size: .half,
        content: { AnyView(SilenceModule(layout: .half, controller: .shared)) }
    )
    static let compactSilence = Utility(
        id: "compactSilence", name: "Compact Silence", symbol: "speaker.zzz.fill", size: .quarter,
        content: { AnyView(SilenceModule(layout: .quarter, controller: .shared)) },
        isHiddenByDefault: true
    )
    static let emptyTrash = Utility(
        id: "emptyTrash", name: "Empty Trash", symbol: "trash.fill", size: .half,
        content: { AnyView(EmptyTrashModule(layout: .half, controller: .shared)) }
    )
    static let compactEmptyTrash = Utility(
        id: "compactEmptyTrash", name: "Compact Empty Trash", symbol: "trash.fill", size: .quarter,
        content: { AnyView(EmptyTrashModule(layout: .quarter, controller: .shared)) },
        isHiddenByDefault: true
    )
}

/// The quick actions' glyphs: each says what a click does, unlike the
/// system's own icons for these settings.
enum QuickActionGlyph {
    case zzz, speakerZzz, trashSparkles
}

struct QuickActionGlyphView: View {
    let glyph: QuickActionGlyph

    var body: some View {
        switch glyph {
        case .zzz:
            Image(systemName: "zzz")
                .font(.system(size: 13, weight: .bold))
        case .speakerZzz:
            Image(systemName: "speaker.zzz.fill")
                .font(.system(size: 13, weight: .semibold))
        case .trashSparkles:
            // A trash can left sparkling: emptied.
            ZStack(alignment: .topTrailing) {
                Image(systemName: "trash.fill")
                    .font(.system(size: 13, weight: .semibold))
                Image(systemName: "sparkles")
                    .font(.system(size: 7, weight: .bold))
                    .offset(x: 5, y: -4)
            }
        }
    }
}

/// A quick action as a quarter tile (a round button with a short label) or
/// a half tile (the button with a name and a status), like Caffeine's.
struct QuickActionTile: View {
    enum Layout { case quarter, half }

    let layout: Layout
    let glyph: QuickActionGlyph
    let tint: Color
    /// On, or asking for a second click: the button fills with the tint.
    let isActive: Bool
    let title: String
    let label: String
    let status: String
    /// Tints the label and status, for "click again".
    var isAsking = false
    var isEnabled = true
    let help: String
    let action: () -> Void

    var body: some View {
        Group {
            switch layout {
            case .quarter:
                VStack(spacing: 4) {
                    button
                    Text(label)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(isAsking ? AnyShapeStyle(tint) : AnyShapeStyle(.secondary))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .contentTransition(.interpolate)
                }
                .frame(maxWidth: .infinity)
            case .half:
                HStack(spacing: 8) {
                    button
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(.system(size: 13, weight: .semibold))
                        Text(status)
                            .font(.system(size: 11))
                            .foregroundStyle(isAsking ? AnyShapeStyle(tint) : AnyShapeStyle(.secondary))
                            .contentTransition(.interpolate)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    Spacer(minLength: 0)
                }
            }
        }
        .animation(.snappy(duration: 0.25), value: isActive)
        .animation(.snappy(duration: 0.25), value: status)
        .help(help)
    }

    private var button: some View {
        Button(action: action) {
            QuickActionGlyphView(glyph: glyph)
                .foregroundStyle(isActive ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .frame(width: 30, height: 30)
                .background(Circle().fill(isActive ? AnyShapeStyle(tint) : AnyShapeStyle(Color.panelTrack)))
                .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
        .accessibilityLabel(title)
    }
}

// MARK: - Modules

struct SleepModule: View {
    let layout: QuickActionTile.Layout
    let controller: SleepController

    var body: some View {
        let asking = controller.confirmation.awaitsConfirmation
        QuickActionTile(
            layout: layout, glyph: .zzz, tint: .indigo, isActive: asking,
            title: "Sleep", label: asking ? "Sleep?" : "Sleep",
            status: asking ? "Click again" : "Now", isAsking: asking,
            help: asking ? "Click again to put your Mac to sleep" : "Put your Mac to sleep",
            action: controller.tap
        )
    }
}

struct SilenceModule: View {
    let layout: QuickActionTile.Layout
    let controller: SilenceController

    var body: some View {
        let on = controller.isSilenced
        QuickActionTile(
            layout: layout, glyph: .speakerZzz, tint: .pink, isActive: on,
            title: "Silence", label: on ? "Silenced" : "Silence",
            status: controller.isAvailable ? (on ? "All sounds off" : "Kill all sounds") : "Can’t mute this output",
            isEnabled: controller.isAvailable,
            help: on ? "Turn sound back on" : "Mute all sound from your Mac",
            action: controller.toggle
        )
    }
}

struct EmptyTrashModule: View {
    let layout: QuickActionTile.Layout
    let controller: EmptyTrashController

    var body: some View {
        let asking = controller.confirmation.awaitsConfirmation
        QuickActionTile(
            layout: layout, glyph: .trashSparkles, tint: .red, isActive: asking || controller.isEmptying,
            title: "Empty Trash", label: asking ? "Empty?" : "Empty",
            status: status, isAsking: asking || controller.failed,
            isEnabled: !controller.isEmptying && controller.trashBytes != 0,
            help: asking ? "Click again to remove everything in the Trash for good" : "Empty the Trash",
            action: controller.tap
        )
        .onAppear { controller.refresh() }
        // The panel's window stays alive between openings; look again
        // whenever it comes back.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            controller.refresh()
        }
    }

    private var status: String {
        if controller.isEmptying { return "Emptying…" }
        if controller.confirmation.awaitsConfirmation { return "Click again" }
        if controller.failed { return "Couldn’t empty it" }
        guard let bytes = controller.trashBytes else { return "Free the space" }
        return bytes == 0 ? "Already empty" : CleanupFormat.bytes(bytes)
    }
}
