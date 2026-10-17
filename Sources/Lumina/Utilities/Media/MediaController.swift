import AppKit
import Observation

/// What's playing, as macOS reports it.
struct NowPlaying: Equatable, Sendable {
    var title: String
    var artist: String
    var album: String
    /// Seconds; nil for live streams and apps that don't say.
    var duration: Double?
    /// Seconds played at `timestamp`.
    var elapsed: Double
    var timestamp: Date
    var rate: Double
    var isPlaying: Bool
    var pid: pid_t

    /// Seconds played by `date`, moving on from the last report.
    func elapsed(at date: Date) -> Double {
        var seconds = elapsed
        if isPlaying { seconds += date.timeIntervalSince(timestamp) * (rate > 0 ? rate : 1) }
        return min(max(0, seconds), duration ?? .infinity)
    }

    /// "Artist · Album", or whichever there is.
    var subtitle: String {
        [artist, album].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// Follows what's playing on the Mac (any app: Music, Spotify, a browser…)
/// and sends it play, pause, skip and seek commands.
///
/// macOS has no public API for this, and since macOS 15.4 the private
/// MediaRemote framework only answers processes Apple entitles. The
/// system's Perl is one, so Lumina runs it with a small helper library
/// (Helpers/MediaRemoteHelper.m, bundled as MediaRemoteHelper.dylib) that
/// streams what's playing as JSON lines and takes commands on stdin. If a
/// macOS update closes that door, the widget says so instead of breaking.
@MainActor
@Observable
final class MediaController {
    static let shared = MediaController()

    enum Status { case idle, running, unavailable }

    private(set) var status: Status = .idle
    private(set) var nowPlaying: NowPlaying?
    private(set) var artwork: NSImage?
    /// Changes with each new artwork, so views can blend one into the next.
    private(set) var artworkID = 0
    /// The app playing it.
    private(set) var app: NSRunningApplication?

    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var input: FileHandle?
    @ObservationIgnored private var restarts = 0
    /// Between tracks, apps briefly report no artwork (or nothing at all)
    /// before the next one. Clearing waits a moment, so the old cover
    /// blends straight into the new one instead of flashing the app's
    /// icon or "Not Playing".
    @ObservationIgnored private var artworkClearing: Task<Void, Never>?
    @ObservationIgnored private var nowPlayingClearing: Task<Void, Never>?
    private static let clearingDelay: Duration = .seconds(1.5)

    private static let script = """
        use DynaLoader;
        my $lib = DynaLoader::dl_load_file($ARGV[0], 0) or die DynaLoader::dl_error();
        my $run = DynaLoader::dl_find_symbol($lib, "lumina_media_run") or die DynaLoader::dl_error();
        DynaLoader::dl_install_xsub("main::run", $run);
        run();
        """

    private init() {}

    /// Starts following what's playing; called when a media widget shows.
    func start() {
        guard process == nil, status != .unavailable else { return }
        guard let helper = Bundle.main.url(forResource: "MediaRemoteHelper", withExtension: "dylib") else {
            status = .unavailable
            return
        }
        // A write to a helper that just quit must not take Lumina down.
        signal(SIGPIPE, SIG_IGN)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = ["-e", Self.script, helper.path]
        let output = Pipe()
        let commands = Pipe()
        process.standardOutput = output
        process.standardInput = commands
        process.standardError = FileHandle.nullDevice

        let lines = LineSplitter()
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            for line in lines.append(data) {
                guard let message = MediaMessage(line) else { continue }
                // In order, on the main thread.
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { MediaController.shared.apply(message) }
                }
            }
        }
        process.terminationHandler = { finished in
            let code = finished.terminationStatus
            DispatchQueue.main.async {
                MainActor.assumeIsolated { MediaController.shared.helperExited(code: code) }
            }
        }

        do {
            try process.run()
        } catch {
            status = .unavailable
            return
        }
        self.process = process
        input = commands.fileHandleForWriting
        status = .running
    }

    // MARK: - Commands

    func togglePlayPause() {
        guard var playing = nowPlaying else { return }
        send("toggle")
        // Right away, rather than after the app reports back.
        playing.elapsed = playing.elapsed(at: .now)
        playing.timestamp = .now
        playing.isPlaying.toggle()
        nowPlaying = playing
    }

    func next() { send("next") }

    func previous() { send("previous") }

    func seek(to seconds: Double) {
        guard var playing = nowPlaying else { return }
        send("seek \(seconds)")
        playing.elapsed = seconds
        playing.timestamp = .now
        nowPlaying = playing
    }

    /// Brings the app that's playing to the front.
    func showApp() {
        app?.activate()
    }

    private func send(_ command: String) {
        try? input?.write(contentsOf: Data((command + "\n").utf8))
    }

    // MARK: - Helper output

    private func apply(_ message: MediaMessage) {
        if message.isError {
            status = .unavailable
            return
        }
        restarts = 0

        if let playing = message.nowPlaying {
            nowPlayingClearing?.cancel()
            nowPlayingClearing = nil
            nowPlaying = playing
            if app?.processIdentifier != playing.pid {
                app = playing.pid > 0 ? NSRunningApplication(processIdentifier: playing.pid) : nil
            }
        } else if nowPlaying != nil, nowPlayingClearing == nil {
            nowPlayingClearing = Task {
                try? await Task.sleep(for: Self.clearingDelay)
                guard !Task.isCancelled else { return }
                nowPlaying = nil
                app = nil
                nowPlayingClearing = nil
            }
        }

        switch message.artwork {
        case .unchanged:
            break
        case .changed(let data):
            artworkClearing?.cancel()
            artworkClearing = nil
            artwork = NSImage(data: data)
            artworkID += 1
        case .cleared:
            guard artwork != nil else { break }
            artworkClearing?.cancel()
            artworkClearing = Task {
                try? await Task.sleep(for: Self.clearingDelay)
                guard !Task.isCancelled else { return }
                artwork = nil
                artworkID += 1
                artworkClearing = nil
            }
        }
    }

    private func helperExited(code: Int32) {
        process = nil
        input = nil
        guard status != .unavailable else { return }
        // 1: MediaRemote isn't there. Otherwise try again a few times.
        if code == 1 || restarts >= 3 {
            status = .unavailable
            return
        }
        restarts += 1
        status = .idle
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            MainActor.assumeIsolated { MediaController.shared.start() }
        }
    }
}

/// One line from the helper.
private struct MediaMessage: Sendable {
    enum Artwork: Sendable {
        case unchanged, cleared
        case changed(Data)
    }

    var isError = false
    var nowPlaying: NowPlaying?
    var artwork: Artwork = .unchanged

    init?(_ line: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return nil }
        if object["error"] != nil {
            isError = true
            return
        }
        let title = object["title"] as? String ?? ""
        let pid = (object["pid"] as? NSNumber)?.int32Value ?? 0
        if !title.isEmpty || pid > 0 {
            let duration = (object["duration"] as? NSNumber)?.doubleValue
            let rate = (object["rate"] as? NSNumber)?.doubleValue ?? 0
            nowPlaying = NowPlaying(
                title: title,
                artist: object["artist"] as? String ?? "",
                album: object["album"] as? String ?? "",
                duration: duration.flatMap { $0 > 0 ? $0 : nil },
                elapsed: (object["elapsed"] as? NSNumber)?.doubleValue ?? 0,
                timestamp: (object["timestamp"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) } ?? .now,
                rate: rate,
                isPlaying: (object["playing"] as? NSNumber)?.boolValue ?? (rate > 0),
                pid: pid
            )
        }
        if let value = object["artwork"] {
            if let base64 = value as? String, let data = Data(base64Encoded: base64) {
                artwork = .changed(data)
            } else {
                artwork = .cleared
            }
        }
    }
}

/// Splits a byte stream into lines. Only touched from the pipe's handler,
/// which runs one call at a time.
private final class LineSplitter: @unchecked Sendable {
    private var buffer = Data()

    func append(_ data: Data) -> [Data] {
        buffer.append(data)
        var lines: [Data] = []
        while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            lines.append(buffer[buffer.startIndex..<newline])
            buffer.removeSubrange(buffer.startIndex...newline)
        }
        return lines
    }
}
