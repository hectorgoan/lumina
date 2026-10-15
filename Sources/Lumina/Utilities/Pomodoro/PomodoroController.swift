import AppKit
import Observation
import UserNotifications

/// Runs the Pomodoro technique: four 25-minute focus sessions separated by
/// short breaks, followed by a long break, then the cycle starts again.
@MainActor
@Observable
final class PomodoroController {
    enum Phase {
        case focus, shortBreak, longBreak

        var duration: TimeInterval {
            switch self {
            case .focus: 25 * 60
            case .shortBreak: 5 * 60
            case .longBreak: 15 * 60
            }
        }

        var title: String {
            switch self {
            case .focus: "Focus"
            case .shortBreak: "Short Break"
            case .longBreak: "Long Break"
            }
        }
    }

    static let shared = PomodoroController()

    /// Focus sessions in a cycle before the long break.
    static let sessionsPerCycle = 4

    private(set) var phase: Phase = .focus
    /// Focus sessions finished in the current cycle.
    private(set) var completedSessions = 0
    private(set) var remaining: TimeInterval = Phase.focus.duration
    private(set) var isRunning = false

    @ObservationIgnored private var endDate: Date?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var hasRequestedNotifications = false

    private init() {}

    /// Whether a session is under way, running or paused.
    var isInProgress: Bool {
        isRunning || remaining < phase.duration || completedSessions > 0 || phase != .focus
    }

    /// How much of the current step has elapsed, from 0 to 1.
    var progress: Double {
        1 - remaining / phase.duration
    }

    /// The remaining time as `mm:ss`.
    var formattedRemaining: String {
        let seconds = Int(remaining.rounded(.up))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    func toggle() {
        isRunning ? pause() : start()
    }

    func start() {
        guard !isRunning else { return }
        requestNotificationsIfNeeded()
        isRunning = true
        endDate = .now.addingTimeInterval(remaining)
        ticker = Task { await tick() }
    }

    func pause() {
        guard isRunning, let endDate else { return }
        ticker?.cancel()
        ticker = nil
        remaining = max(0, endDate.timeIntervalSinceNow)
        self.endDate = nil
        isRunning = false
    }

    /// Moves on to the next step, keeping the timer running or paused.
    func skip() {
        advance()
    }

    /// Stops the timer and starts over from the first focus session.
    func reset() {
        pause()
        phase = .focus
        completedSessions = 0
        remaining = phase.duration
    }

    // MARK: - Timing

    private func tick() async {
        while !Task.isCancelled, let endDate {
            let left = endDate.timeIntervalSinceNow
            if left <= 0 {
                announceEnd(of: phase)
                advance()
                continue
            }
            remaining = left
            // Wake on the next whole second so the display stays in step.
            let untilNextSecond = left.truncatingRemainder(dividingBy: 1)
            try? await Task.sleep(for: .seconds(untilNextSecond > 0.01 ? untilNextSecond : 1))
        }
    }

    private func advance() {
        switch phase {
        case .focus:
            completedSessions += 1
            phase = completedSessions >= Self.sessionsPerCycle ? .longBreak : .shortBreak
        case .shortBreak:
            phase = .focus
        case .longBreak:
            completedSessions = 0
            phase = .focus
        }
        remaining = phase.duration
        if isRunning {
            endDate = .now.addingTimeInterval(remaining)
        }
    }

    // MARK: - Alerts

    private func requestNotificationsIfNeeded() {
        guard !hasRequestedNotifications else { return }
        hasRequestedNotifications = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
    }

    private func announceEnd(of finished: Phase) {
        NSSound(named: "Glass")?.play()

        let content = UNMutableNotificationContent()
        switch finished {
        case .focus:
            let isLast = completedSessions + 1 >= Self.sessionsPerCycle
            content.title = "Focus session complete"
            content.body = isLast
                ? "Great work. Take a \(Int(Phase.longBreak.duration / 60))-minute break."
                : "Take a \(Int(Phase.shortBreak.duration / 60))-minute break."
        case .shortBreak, .longBreak:
            content.title = "Break’s over"
            content.body = "Time to focus for \(Int(Phase.focus.duration / 60)) minutes."
        }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
