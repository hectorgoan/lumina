import SwiftUI

/// A media widget's settings: its background first (the choice that
/// changes its look the most; Small has none), then its size and progress.
struct MediaWidgetSettings: View {
    @Environment(UtilityStore.self) private var store
    let widgetID: String

    var body: some View {
        if let widget = store.mediaWidget(withID: widgetID) {
            MediaWidgetForm(widget: widget) { store.updateMediaWidget($0) }
        }
    }
}

/// The background, size and progress controls, shared by the settings and
/// the add page.
struct MediaWidgetForm: View {
    let widget: MediaWidget
    let update: (MediaWidget) -> Void
    /// The add page shows the size first, like Add Batteries.
    var sizeFirst = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if sizeFirst {
                size
                Divider()
                look
            } else {
                look
                Divider()
                size
            }

            if widget.size == .large {
                Divider()
                Toggle("Show Progress", isOn: Binding(
                    get: { widget.showsProgress },
                    set: { shows in
                        var updated = widget
                        updated.showsProgress = shows
                        update(updated)
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .font(.system(size: 13))
                Text("Elapsed and remaining time; drag it to jump.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Small is always the art edge to edge, so it picks its controls;
    /// Medium and Large pick their background. Each keeps the other's
    /// setting for when the size changes back.
    @ViewBuilder private var look: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(widget.size == .small ? "Controls" : "Background")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            if widget.size == .small {
                // On the add page nothing is picked until the user picks;
                // a widget from before the choice plays and pauses.
                MediaControlsChoice(selection: widget.smallControls ?? (sizeFirst ? nil : .playPause)) { controls in
                    var updated = widget
                    updated.smallControls = controls
                    update(updated)
                }
            } else {
                MediaBackgroundChoice(widget: widget, update: update)
            }
        }
    }

    private var size: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Size")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            FullWidthSegmentedPicker(
                options: MediaWidget.Size.allCases.map { ($0.title, $0) },
                selection: Binding(
                    get: { widget.size },
                    set: { newSize in
                        var updated = widget
                        updated.size = newSize
                        update(updated)
                    }
                )
            )
            .accessibilityLabel("Size")
        }
    }
}

/// Small's controls, as two sketches of it: one button, or two halves.
struct MediaControlsChoice: View {
    let selection: MediaWidget.SmallControls?
    let choose: (MediaWidget.SmallControls) -> Void
    private let controller = MediaController.shared

    var body: some View {
        HStack(spacing: 12) {
            ForEach(MediaWidget.SmallControls.allCases, id: \.self) { option in
                let isSelected = selection == option
                Button { choose(option) } label: {
                    VStack(spacing: 6) {
                        sketch(option)
                            .padding(8)
                            .frame(maxWidth: .infinity)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.panelTrack.opacity(0.5)))
                            .overlay {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2.5)
                                    .padding(-3)
                            }
                        Text(option.title)
                            .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? .primary : .secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel(option.title)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .animation(.snappy(duration: 0.2), value: selection)
    }

    private func sketch(_ option: MediaWidget.SmallControls) -> some View {
        ZStack {
            Color.clear.overlay {
                // The cover playing now, or plain colors, which don't
                // compete with the buttons like the sample's drawing would.
                if let artwork = controller.artwork {
                    Image(nsImage: artwork).resizable().scaledToFill()
                } else {
                    LinearGradient(
                        colors: [Color(red: 0.95, green: 0.35, blue: 0.45), Color(red: 0.35, green: 0.2, blue: 0.75)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                }
            }
            Color.black.opacity(0.25)
            HStack(spacing: 0) {
                Image(systemName: "pause.fill")
                    .font(.system(size: 11, weight: .bold))
                    .frame(maxWidth: .infinity)
                if option == .playPauseNext {
                    Rectangle().fill(.white.opacity(0.4)).frame(width: 0.5).padding(.vertical, 12)
                    Image(systemName: "forward.fill")
                        .font(.system(size: 9, weight: .bold))
                        .frame(maxWidth: .infinity)
                }
            }
            .foregroundStyle(.white)
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// Plain or Album Art, as two sketches of a tile at the widget's size: no
/// real controls in them, just what changes, the background. The real
/// tile shows in the preview beside the page.
struct MediaBackgroundChoice: View {
    let widget: MediaWidget
    let update: (MediaWidget) -> Void
    private let controller = MediaController.shared

    var body: some View {
        HStack(spacing: 12) {
            option(artBackground: false, title: "Plain")
            option(artBackground: true, title: "Album Art")
        }
        .animation(.snappy(duration: 0.2), value: widget.showsArtBackground)
    }

    private func option(artBackground: Bool, title: String) -> some View {
        let isSelected = widget.showsArtBackground == artBackground
        return Button {
            var updated = widget
            updated.showsArtBackground = artBackground
            update(updated)
        } label: {
            VStack(spacing: 6) {
                MediaBackgroundSketch(
                    isLarge: widget.size == .large,
                    artwork: artBackground ? (controller.artwork ?? MediaDisplay.sample.artwork) : nil,
                    cover: controller.artwork ?? MediaDisplay.sample.artwork
                )
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.panelTrack.opacity(0.5)))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2.5)
                        .padding(-3)
                }
                Text(title)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A drawing of a media tile: a cover, two lines and, on Large, a bar, on
/// grey or on a wash of the art.
private struct MediaBackgroundSketch: View {
    let isLarge: Bool
    /// The wash behind it; nil for Plain.
    let artwork: NSImage?
    let cover: NSImage?

    var body: some View {
        let coverSize: CGFloat = isLarge ? 22 : 16
        HStack(alignment: .top, spacing: 5) {
            Group {
                if let cover {
                    Image(nsImage: cover).resizable().scaledToFill()
                } else {
                    Color.secondary
                }
            }
            .frame(width: coverSize, height: coverSize)
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Capsule().fill(.white.opacity(0.75)).frame(width: 30, height: 4)
                Capsule().fill(.white.opacity(0.4)).frame(width: 20, height: 3)
            }
            Spacer(minLength: 0)
        }
        .padding(6)
        .frame(width: isLarge ? 104 : 70, height: isLarge ? 56 : 44, alignment: .topLeading)
        .overlay(alignment: .bottom) {
            if isLarge {
                Capsule().fill(.white.opacity(0.35)).frame(height: 3).padding(.horizontal, 6).padding(.bottom, 7)
            }
        }
        .background {
            Color.clear.overlay {
                if let artwork {
                    Image(nsImage: artwork).resizable().scaledToFill().blur(radius: 6).scaleEffect(1.3)
                    Color.black.opacity(0.3)
                } else {
                    Color(white: 0.26)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .environment(\.colorScheme, .dark)
    }
}
