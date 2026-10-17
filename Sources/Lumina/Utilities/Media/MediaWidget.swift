import SwiftUI

/// A media widget the user added: its size and look.
struct MediaWidget: Codable, Hashable {
    enum Size: String, Codable, CaseIterable, Identifiable {
        case small, medium, large

        var id: Self { self }

        var title: String {
            switch self {
            case .small: "Small"
            case .medium: "Medium"
            case .large: "Large"
            }
        }

        var tileSize: Utility.Size {
            switch self {
            case .small: .quarter
            case .medium: .half
            case .large: .full
            }
        }

        var summary: String {
            switch self {
            case .small: "Album art · Quarter width"
            case .medium: "Art, title and controls · Half width"
            case .large: "Everything, with progress · Full width"
            }
        }
    }

    /// The utility ID.
    var id: String
    var size: Size
    /// The album art, blurred, behind the controls; the art edge to edge
    /// on Small.
    var showsArtBackground = false
    /// Elapsed and remaining time on Large, where it can be dragged to seek.
    var showsProgress = true
    /// Small's buttons. Chosen when a Small one is added; nil until then
    /// (and for widgets from before the choice, which play and pause).
    var smallControls: SmallControls?

    enum SmallControls: String, Codable, CaseIterable {
        /// A click anywhere plays or pauses.
        case playPause
        /// The left half plays or pauses, the right half skips.
        case playPauseNext

        var title: String {
            switch self {
            case .playPause: "Play/Pause"
            case .playPauseNext: "Play/Pause & Next"
            }
        }
    }
}

extension Utility {
    static func mediaWidget(_ widget: MediaWidget) -> Utility {
        Utility(
            id: widget.id,
            name: "Media",
            symbol: "music.note",
            size: widget.size.tileSize,
            content: { AnyView(MediaWidgetView(widgetID: widget.id)) },
            settings: { AnyView(MediaWidgetSettings(widgetID: widget.id)) },
            isRemovable: true
        )
    }
}

/// What a media widget shows: what's playing, its art and its app.
struct MediaDisplay {
    let nowPlaying: NowPlaying
    let artwork: NSImage?
    /// Changes with each new artwork, so the art can blend into the next.
    var artworkID = 0
    let appName: String
    let appIcon: NSImage?

    @MainActor
    static func live(_ controller: MediaController) -> MediaDisplay? {
        guard let playing = controller.nowPlaying else { return nil }
        return MediaDisplay(
            nowPlaying: playing,
            artwork: controller.artwork,
            artworkID: controller.artworkID,
            appName: controller.app?.localizedName ?? "",
            appIcon: controller.app?.icon
        )
    }

    /// For previews while nothing is playing: made-up music with drawn art.
    @MainActor
    static let sample = MediaDisplay(
        nowPlaying: NowPlaying(
            title: "Midnight Drive", artist: "Neon Coast", album: "Afterglow",
            duration: 221, elapsed: 84, timestamp: .now, rate: 0, isPlaying: true, pid: 0
        ),
        artwork: sampleArtwork(),
        appName: "Music",
        appIcon: NSWorkspace.shared.icon(forFile: "/System/Applications/Music.app")
    )

    private static func sampleArtwork() -> NSImage {
        NSImage(size: NSSize(width: 300, height: 300), flipped: false) { rect in
            NSGradient(colors: [
                NSColor(red: 0.95, green: 0.35, blue: 0.45, alpha: 1),
                NSColor(red: 0.35, green: 0.2, blue: 0.75, alpha: 1),
            ])?.draw(in: rect, angle: -45)
            let configuration = NSImage.SymbolConfiguration(pointSize: 110, weight: .regular)
                .applying(.init(paletteColors: [.white.withAlphaComponent(0.85)]))
            if let symbol = NSImage(systemSymbolName: "moon.stars.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(configuration) {
                let size = symbol.size
                symbol.draw(in: NSRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height))
            }
            return true
        }
    }
}

/// A media widget in the grid, following what's playing. Going from
/// something playing to nothing (or back) changes its height, so it fades
/// out, resizes and fades back in rather than jumping.
struct MediaWidgetView: View {
    @Environment(UtilityStore.self) private var store
    let widgetID: String
    private let controller = MediaController.shared
    @StateObject private var presence = SwapStage<Bool>()
    @StateObject private var last = LastDisplay()

    var body: some View {
        if let widget = store.mediaWidget(withID: widgetID) {
            let live = MediaDisplay.live(controller)
            MediaWidgetContent(
                widget: widget,
                // While it fades out, what was playing stays on show.
                display: presence.value == true ? (live ?? last.display) : nil,
                isUnavailable: controller.status == .unavailable,
                controller: controller
            )
            .fadesWithoutColorShift()
            .opacity(presence.isVisible ? 1 : 0)
            .onAppear { controller.start() }
            .onChange(of: controller.nowPlaying, initial: true) { _, playing in
                if playing != nil { last.display = .live(controller) }
                presence.set(playing != nil)
            }
        }
    }
}

/// The last thing shown playing. Not published: it's only read while the
/// widget fades out.
@MainActor
private final class LastDisplay: ObservableObject {
    var display: MediaDisplay?
}

/// A media widget's layout for a size. Small is the album art edge to
/// edge; Medium and Large have one layout each, with the art, blurred,
/// behind it when the widget asks for it. Without a controller it's a
/// picture (previews): nothing in it responds.
struct MediaWidgetContent: View {
    let widget: MediaWidget
    let display: MediaDisplay?
    var isUnavailable = false
    var controller: MediaController? = nil

    @Environment(\.colorScheme) private var colorScheme
    /// Large's progress row, which comes and goes with the app's duration.
    @StateObject private var progress = RevealStage()
    @StateObject private var lastDuration = LastDuration()

    private static let tileShape = RoundedRectangle(cornerRadius: 20, style: .continuous)
    /// How long artwork takes to blend into the next.
    static let artworkBlend = Animation.easeInOut(duration: 0.5)

    /// Whether the art fills the tile: always on Small, as chosen otherwise.
    private var showsBackdrop: Bool {
        widget.size == .small || widget.showsArtBackground
    }

    var body: some View {
        if let display {
            playing(display)
                .environment(\.colorScheme, showsBackdrop ? .dark : colorScheme)
                .background {
                    if showsBackdrop {
                        MediaBackdrop(display: display, isBlurred: widget.size != .small)
                            .clipShape(Self.tileShape)
                            // Out to the tile's edges, past its padding.
                            .padding(-12)
                    }
                }
        } else {
            empty
        }
    }

    @ViewBuilder private func playing(_ display: MediaDisplay) -> some View {
        switch widget.size {
        case .small: small(display)
        case .medium: medium(display)
        case .large: large(display)
        }
    }

    // MARK: - Sizes

    /// The art edge to edge (drawn by the backdrop): a click plays or
    /// pauses, as the glyph in the middle says.
    @ViewBuilder private func small(_ display: MediaDisplay) -> some View {
        if widget.smallControls == .playPauseNext {
            smallHalves(display)
        } else {
            smallSingle(display)
        }
    }

    private func smallSingle(_ display: MediaDisplay) -> some View {
        Button { controller?.togglePlayPause() } label: {
            ZStack {
                Color.clear
                Image(systemName: display.nowPlaying.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 3)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .overlay(alignment: .bottomTrailing) { appBadge(display, size: 16).offset(x: 6, y: 6) }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .animation(.snappy(duration: 0.2), value: display.nowPlaying.isPlaying)
        .help(display.nowPlaying.isPlaying ? "Pause \(display.nowPlaying.title)" : "Play \(display.nowPlaying.title)")
        .accessibilityLabel(display.nowPlaying.title)
    }

    /// Two halves: the left plays or pauses, the right skips, with a
    /// hairline between, each half the size of the tile's half.
    private func smallHalves(_ display: MediaDisplay) -> some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .overlay {
                HStack(spacing: 0) {
                    Button { controller?.togglePlayPause() } label: {
                        smallGlyph(display.nowPlaying.isPlaying ? "pause.fill" : "play.fill", size: 14)
                    }
                    .buttonStyle(PressableButtonStyle())
                    .help(display.nowPlaying.isPlaying ? "Pause" : "Play")
                    .accessibilityLabel(display.nowPlaying.isPlaying ? "Pause" : "Play")

                    Rectangle()
                        .fill(.white.opacity(0.35))
                        .frame(width: 0.5)
                        .padding(.vertical, 18)

                    Button { controller?.next() } label: {
                        smallGlyph("forward.fill", size: 12)
                    }
                    .buttonStyle(PressableButtonStyle())
                    .help("Next")
                    .accessibilityLabel("Next")
                }
                .background(Color.black.opacity(0.16))
                .clipShape(Self.tileShape)
                .overlay(alignment: .topTrailing) { appBadge(display, size: 14).padding(5) }
                // The halves reach the tile's edges, past its padding.
                .padding(-12)
            }
            .animation(.snappy(duration: 0.2), value: display.nowPlaying.isPlaying)
    }

    private func smallGlyph(_ symbol: String, size: CGFloat) -> some View {
        Image(systemName: symbol)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.5), radius: 3)
            .contentTransition(.symbolEffect(.replace))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
    }

    private func medium(_ display: MediaDisplay) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                artButton(display, size: 40)
                    .overlay(alignment: .bottomTrailing) { appBadge(display, size: 14).offset(x: 4, y: 4) }
                VStack(alignment: .leading, spacing: 1) {
                    Text(display.nowPlaying.title)
                        .font(.system(size: 12, weight: .semibold))
                    Text(display.nowPlaying.artist.isEmpty ? display.appName : display.nowPlaying.artist)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                .contentTransition(.opacity)
                Spacer(minLength: 0)
            }
            HStack {
                Spacer(minLength: 0)
                controls(display, size: 11)
                Spacer(minLength: 0)
            }
        }
        .animation(Self.artworkBlend, value: display.nowPlaying.title)
    }

    private func large(_ display: MediaDisplay) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                artButton(display, size: 64)
                VStack(alignment: .leading, spacing: 3) {
                    appLabel(display)
                    Text(display.nowPlaying.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    if !display.nowPlaying.subtitle.isEmpty {
                        Text(display.nowPlaying.subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .contentTransition(.opacity)
                Spacer(minLength: 0)
            }
            VStack(spacing: 0) {
                // Not every app says how long it is: the row fades out
                // before its room closes, and back in once it opens.
                MediaProgress(nowPlaying: display.nowPlaying, duration: display.nowPlaying.duration ?? lastDuration.value) {
                    controller?.seek(to: $0)
                }
                .allowsHitTesting(controller != nil && display.nowPlaying.duration != nil)
                // The round button's own room already reads as a gap; this
                // evens out the space above and below the progress.
                .padding(.bottom, 4)
                .fadesWithoutColorShift()
                .opacity(progress.isVisible ? 1 : 0)
                .frame(height: progress.isShown ? nil : 0, alignment: .top)
                .clipped()

                HStack {
                    Spacer()
                    controls(display, size: 14, prominent: true)
                    Spacer()
                }
            }
        }
        .animation(Self.artworkBlend, value: display.nowPlaying.title)
        .onChange(of: display.nowPlaying.duration, initial: true) { _, duration in
            if let duration { lastDuration.value = duration }
        }
        .onChange(of: widget.showsProgress && display.nowPlaying.duration != nil, initial: true) { _, shows in
            progress.set(shows)
        }
    }

    // MARK: - Pieces

    /// The art; clicking it brings the app forward.
    private func artButton(_ display: MediaDisplay, size: CGFloat) -> some View {
        Button { controller?.showApp() } label: {
            MediaArt(display: display, size: size)
        }
        .buttonStyle(PressableButtonStyle())
        .help(display.appName.isEmpty ? "" : "Show \(display.appName)")
    }

    @ViewBuilder private func appBadge(_ display: MediaDisplay, size: CGFloat) -> some View {
        // Without art, the art is already the app's icon.
        if display.artwork != nil, let icon = display.appIcon {
            Image(nsImage: icon)
                .resizable()
                .frame(width: size, height: size)
                .shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)
                .help(display.appName)
        }
    }

    @ViewBuilder private func appLabel(_ display: MediaDisplay) -> some View {
        if !display.appName.isEmpty {
            HStack(spacing: 4) {
                if let icon = display.appIcon {
                    Image(nsImage: icon).resizable().frame(width: 13, height: 13)
                }
                Text(display.appName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func controls(_ display: MediaDisplay, size: CGFloat, prominent: Bool = false) -> some View {
        HStack(spacing: prominent ? 18 : 6) {
            controlButton("backward.fill", size: size, help: "Previous") { controller?.previous() }
            controlButton(display.nowPlaying.isPlaying ? "pause.fill" : "play.fill", size: size + 2, round: prominent,
                          help: display.nowPlaying.isPlaying ? "Pause" : "Play") { controller?.togglePlayPause() }
            controlButton("forward.fill", size: size, help: "Next") { controller?.next() }
        }
    }

    private func controlButton(_ symbol: String, size: CGFloat, round: Bool = false, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: round ? size * 2.4 : size * 1.9, height: round ? size * 2.4 : size * 1.9)
                .background(Circle().fill(round ? Color.panelTrack : .clear))
                .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .help(help)
        .accessibilityLabel(help)
    }

    // MARK: - Nothing playing

    @ViewBuilder private var empty: some View {
        let title = isUnavailable ? "Not Available" : "Not Playing"
        let detail = isUnavailable ? "Can’t read what’s playing on this Mac" : "Play something to control it here"
        switch widget.size {
        case .small:
            Image(systemName: isUnavailable ? "exclamationmark.triangle" : "music.note")
                .font(.system(size: 18))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .help("\(title): \(detail)")
        case .medium, .large:
            HStack(spacing: 10) {
                Image(systemName: isUnavailable ? "exclamationmark.triangle" : "music.note")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                    .frame(width: 40, height: 40)
                    .background(Color.panelTrack, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                    Text(detail)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
            }
        }
    }
}

/// The album art, or the app's icon when the app gives none. A new cover
/// blends into the old one.
struct MediaArt: View {
    let display: MediaDisplay
    let size: CGFloat

    var body: some View {
        ZStack {
            if let artwork = display.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .scaledToFill()
                    .id(display.artworkID)
                    .transition(.opacity)
            } else {
                ZStack {
                    Color.panelTrack
                    if let icon = display.appIcon {
                        Image(nsImage: icon).resizable().frame(width: size * 0.62, height: size * 0.62)
                    } else {
                        Image(systemName: "music.note").font(.system(size: size * 0.4)).foregroundStyle(.secondary)
                    }
                }
                .transition(.opacity)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.16, style: .continuous))
        .animation(MediaWidgetContent.artworkBlend, value: display.artworkID)
    }
}

/// The art behind a tile: itself on Small, a blurred, darkened wash of it
/// otherwise. Sized by the tile, not by the image, which fills it; a new
/// cover blends into the old one.
private struct MediaBackdrop: View {
    let display: MediaDisplay
    let isBlurred: Bool

    var body: some View {
        Color.clear
            .overlay {
                ZStack {
                    if let image = display.artwork ?? display.appIcon {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                            .blur(radius: isBlurred ? 24 : 0)
                            .scaleEffect(isBlurred ? 1.3 : 1)
                            .id(display.artworkID)
                            .transition(.opacity)
                    }
                }
                .animation(MediaWidgetContent.artworkBlend, value: display.artworkID)
            }
            .overlay { Color.black.opacity(isBlurred ? 0.35 : 0.12) }
    }
}

/// How far along it is, with elapsed and remaining time. Drag to seek.
private struct MediaProgress: View {
    let nowPlaying: NowPlaying
    let duration: Double
    let seek: (Double) -> Void
    @StateObject private var scrub = Scrub()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = scrub.fraction.map { $0 * duration } ?? nowPlaying.elapsed(at: context.date)
            VStack(spacing: 3) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.18))
                        Capsule()
                            .fill(Color.primary.opacity(0.85))
                            .frame(width: proxy.size.width * min(1, elapsed / duration))
                            // Glides from one second's position to the
                            // next, instead of stepping; follows the
                            // pointer exactly while dragging.
                            .animation(scrub.fraction == nil ? .linear(duration: 1) : nil, value: elapsed)
                    }
                    .frame(height: scrub.fraction == nil ? 4 : 6)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { scrub.fraction = min(max(0, $0.location.x / proxy.size.width), 1) }
                            .onEnded { _ in
                                if let fraction = scrub.fraction { seek(fraction * duration) }
                                scrub.fraction = nil
                            }
                    )
                }
                .frame(height: 10)
                .animation(.snappy(duration: 0.15), value: scrub.fraction == nil)
                HStack {
                    Text(Self.format(elapsed))
                    Spacer()
                    Text("-" + Self.format(max(0, duration - elapsed)))
                }
                .font(.system(size: 9, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            }
        }
    }

    private static func format(_ seconds: Double) -> String {
        let total = Int(seconds.rounded(.down))
        let hours = total / 3600, minutes = total / 60 % 60, secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }
}

/// The last duration shown, for the progress row while it fades out.
@MainActor
private final class LastDuration: ObservableObject {
    var value: Double = 1
}

private final class Scrub: ObservableObject {
    /// While dragging, where the pointer is along the bar.
    @Published var fraction: Double?
}
