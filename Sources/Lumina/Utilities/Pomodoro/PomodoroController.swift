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

        /// The default length, in minutes.
        var defaultMinutes: Int {
            switch self {
            case .focus: 25
            case .shortBreak: 5
            case .longBreak: 15
            }
        }

        /// The lengths the user can choose, in minutes.
        var minuteRange: ClosedRange<Int> {
            switch self {
            case .focus: 5...90
            case .shortBreak: 1...30
            case .longBreak: 5...60
            }
        }

        fileprivate var defaultsKey: String {
            switch self {
            case .focus: "pomodoro.focusMinutes"
            case .shortBreak: "pomodoro.shortBreakMinutes"
            case .longBreak: "pomodoro.longBreakMinutes"
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
    private(set) var remaining: TimeInterval = 0
    private(set) var isRunning = false
    /// The full length of the current step, fixed when the step starts.
    private(set) var currentDuration: TimeInterval = 0

    /// Step lengths in minutes, as chosen in settings.
    private(set) var minutes: [Phase: Int]

    @ObservationIgnored private var endDate: Date?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var hasRequestedNotifications = false
    @ObservationIgnored private let defaults = UserDefaults.standard

    private init() {
        var minutes: [Phase: Int] = [:]
        for phase in [Phase.focus, .shortBreak, .longBreak] {
            let saved = defaults.integer(forKey: phase.defaultsKey)
            minutes[phase] = phase.minuteRange.contains(saved) ? saved : phase.defaultMinutes
        }
        self.minutes = minutes
        currentDuration = duration(of: .focus)
        remaining = currentDuration
    }

    func duration(of phase: Phase) -> TimeInterval {
        TimeInterval(minutes[phase] ?? phase.defaultMinutes) * 60
    }

    func minutes(for phase: Phase) -> Int {
        minutes[phase] ?? phase.defaultMinutes
    }

    /// Changes a step's length. A step that hasn't started yet picks up the
    /// new length right away; one under way keeps its length until it ends.
    func setMinutes(_ value: Int, for phase: Phase) {
        let value = min(max(value, phase.minuteRange.lowerBound), phase.minuteRange.upperBound)
        guard value != minutes(for: phase) else { return }
        let isUntouched = phase == self.phase && !isRunning && remaining == currentDuration
        minutes[phase] = value
        defaults.set(value, forKey: phase.defaultsKey)
        if isUntouched {
            currentDuration = duration(of: phase)
            remaining = currentDuration
        }
    }

    func restoreDefaultDurations() {
        for phase in [Phase.focus, .shortBreak, .longBreak] {
            setMinutes(phase.defaultMinutes, for: phase)
        }
    }

    /// Whether a session is under way, running or paused.
    var isInProgress: Bool {
        isRunning || remaining < currentDuration || completedSessions > 0 || phase != .focus
    }

    /// How much of the current step has elapsed, from 0 to 1.
    var progress: Double {
        currentDuration > 0 ? 1 - remaining / currentDuration : 0
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
        currentDuration = duration(of: phase)
        remaining = currentDuration
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
        currentDuration = duration(of: phase)
        remaining = currentDuration
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
                ? "Great work. Take a \(minutes(for: .longBreak))-minute break."
                : "Take a \(minutes(for: .shortBreak))-minute break."
        case .shortBreak, .longBreak:
            content.title = "Break’s over"
            content.body = "Time to focus for \(minutes(for: .focus)) minutes."
        }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
