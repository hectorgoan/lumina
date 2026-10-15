import SwiftUI

extension Utility {
    static let pomodoro = Utility(
        id: "pomodoro",
        name: "Pomodoro",
        symbol: "timer",
        size: .full,
        content: { AnyView(PomodoroModule(controller: .shared)) }
    )
}

/// A Pomodoro timer with focus sessions, short breaks and long breaks.
struct PomodoroModule: View {
    let controller: PomodoroController

    private var tint: Color { controller.phase.tint }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ModuleToggleButton(
                    symbol: controller.isRunning ? "pause.fill" : "play.fill",
                    tint: tint,
                    isOn: controller.isRunning,
                    action: controller.toggle
                )
                .help(controller.isRunning ? "Pause" : "Start")

                VStack(alignment: .leading, spacing: 1) {
                    Text("Pomodoro")
                        .font(.system(size: 13, weight: .semibold))
                    Text(statusText)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .contentTransition(.interpolate)
                }

                Spacer(minLength: 0)

                SessionDots(
                    completed: controller.completedSessions,
                    total: PomodoroController.sessionsPerCycle,
                    isFocusing: controller.phase == .focus && controller.isInProgress,
                    tint: PomodoroController.Phase.focus.tint
                )
            }

            HStack(alignment: .lastTextBaseline) {
                Text(controller.formattedRemaining)
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                    .foregroundStyle(controller.isRunning ? .primary : .secondary)

                Spacer()

                HStack(spacing: 6) {
                    circleButton("arrow.counterclockwise", help: "Reset", action: controller.reset)
                        .disabled(!controller.isInProgress)
                    circleButton("forward.end.fill", help: "Skip to \(nextStepTitle)", action: controller.skip)
                }
            }

            ProgressBar(progress: controller.progress, tint: tint, isRunning: controller.isRunning)
                // A new step starts a fresh bar rather than animating back.
                .id(controller.phase)
        }
        .animation(.snappy(duration: 0.25), value: controller.phase)
        .animation(.snappy(duration: 0.25), value: controller.isRunning)
        .animation(.snappy(duration: 0.3), value: controller.formattedRemaining)
    }

    private var statusText: String {
        guard controller.isInProgress else { return "Ready to focus" }
        let title = controller.phase.title
        let status = controller.isRunning ? title : "\(title) · Paused"
        guard controller.phase == .focus else { return status }
        return "\(status) · \(controller.completedSessions + 1) of \(PomodoroController.sessionsPerCycle)"
    }

    private var nextStepTitle: String {
        switch controller.phase {
        case .focus:
            controller.completedSessions + 1 >= PomodoroController.sessionsPerCycle ? "Long Break" : "Short Break"
        case .shortBreak, .longBreak:
            "Focus"
        }
    }

    private func circleButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 14, height: 14)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .help(help)
    }
}

extension PomodoroController.Phase {
    var tint: Color {
        switch self {
        case .focus: .red
        case .shortBreak: .luminaGreen
        case .longBreak: .teal
        }
    }
}

/// One dot per focus session in the cycle.
private struct SessionDots: View {
    let completed: Int
    let total: Int
    let isFocusing: Bool
    let tint: Color

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<total, id: \.self) { index in
                Circle()
                    .fill(index < completed ? AnyShapeStyle(tint) : AnyShapeStyle(.fill.secondary))
                    .overlay {
                        if isFocusing && index == completed {
                            Circle().strokeBorder(tint, lineWidth: 1.5)
                        }
                    }
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(completed) of \(total) focus sessions complete")
    }
}

/// A slim capsule that fills as the current step elapses.
private struct ProgressBar: View {
    let progress: Double
    let tint: Color
    let isRunning: Bool

    var body: some View {
        Capsule()
            .fill(.fill.secondary)
            .frame(height: 6)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(tint.gradient)
                        .frame(width: max(6, proxy.size.width * progress))
                        .opacity(progress > 0 ? 1 : 0)
                }
            }
            .animation(isRunning ? .linear(duration: 1) : .snappy, value: progress)
            .accessibilityElement()
            .accessibilityValue("\(Int(progress * 100)) percent")
    }
}
