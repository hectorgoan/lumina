import Charts
import SwiftUI

extension Utility {
    /// Gauges for CPU, memory, temperature and fan, with per-core load.
    static let systemStatus = Utility(
        id: "systemStatus",
        name: "System",
        symbol: "gauge.with.dots.needle.50percent",
        size: .full,
        content: { AnyView(SystemGaugesWidget(monitor: .shared)) }
    )

    /// The same readings as rows with exact values. Hidden by default.
    static let systemList = Utility(
        id: "systemList",
        name: "System List",
        symbol: "list.bullet.rectangle",
        size: .full,
        content: { AnyView(SystemListWidget(monitor: .shared)) },
        isHiddenByDefault: true
    )

    /// A compact take centered on CPU load and its recent history. Hidden by
    /// default.
    static let cpuFocus = Utility(
        id: "cpuFocus",
        name: "CPU Focus",
        symbol: "cpu",
        size: .full,
        content: { AnyView(CPUFocusWidget(monitor: .shared)) },
        isHiddenByDefault: true
    )
}

// MARK: - A · Gauges

/// Four rings read at a glance, with per-core load below.
struct SystemGaugesWidget: View {
    let monitor: SystemMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SystemHeader(monitor: monitor)

            HStack {
                ReadingRing(fraction: monitor.cpu, text: Format.percent(monitor.cpu), label: "CPU", tint: .cpu)
                Spacer()
                ReadingRing(fraction: monitor.memory, text: Format.percent(monitor.memory), label: "Memory", tint: .memory)
                Spacer()
                ReadingRing(
                    fraction: Format.temperatureFraction(monitor.temperature),
                    text: Format.shortTemperature(monitor.temperature),
                    label: "Temp",
                    tint: .temperature
                )
                if let fan = monitor.fan {
                    Spacer()
                    ReadingRing(fraction: fan.fraction, text: Format.fan(fan), label: "Fan", tint: .fan)
                }
            }
            .padding(.horizontal, 4)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                SectionLabel("Cores")
                CoreBars(cores: monitor.cores)
            }
        }
        .monitoring(monitor)
    }
}

// MARK: - B · List

/// Control Center–style rows with exact values, and per-core load below.
struct SystemListWidget: View {
    let monitor: SystemMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SystemHeader(monitor: monitor)

            VStack(spacing: 9) {
                ReadingRow(symbol: "cpu", title: "CPU", value: Format.percent(monitor.cpu), fraction: monitor.cpu, tint: .cpu)
                ReadingRow(symbol: "memorychip", title: "Memory", value: Format.percent(monitor.memory), fraction: monitor.memory, tint: .memory)
                ReadingRow(
                    symbol: "thermometer.medium",
                    title: "Temperature",
                    value: Format.longTemperature(monitor.temperature),
                    fraction: Format.temperatureFraction(monitor.temperature),
                    tint: .temperature
                )
                if let fan = monitor.fan {
                    ReadingRow(symbol: "fan", title: "Fan", value: Format.rpm(fan), fraction: fan.fraction, tint: .fan)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                SectionLabel("Cores")
                CoreBars(cores: monitor.cores)
            }
        }
        .monitoring(monitor)
    }
}

// MARK: - C · CPU Focus

/// A compact take: a large CPU figure with its history graph and the other
/// readings as pills.
struct CPUFocusWidget: View {
    let monitor: SystemMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    SectionLabel("CPU")
                    Text(Format.percent(monitor.cpu))
                        .font(.system(size: 32, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.smooth, value: monitor.cpu)
                }
                .frame(width: 84, alignment: .leading)

                CPUHistoryChart(history: monitor.cpuHistory)
                    .frame(height: 48)
            }

            HStack(spacing: 6) {
                ReadingPill(symbol: "memorychip", value: Format.percent(monitor.memory), tint: .memory)
                ReadingPill(symbol: "thermometer.medium", value: Format.longTemperature(monitor.temperature), tint: .temperature)
                if let fan = monitor.fan {
                    ReadingPill(symbol: "fan", value: Format.fan(fan), tint: .fan)
                }
            }
        }
        .monitoring(monitor)
    }
}

// MARK: - Shared pieces

private extension Color {
    static let cpu = Color.blue
    static let memory = Color.green
    static let temperature = Color.orange
    static let fan = Color.teal
}

private enum Format {
    static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    static func fan(_ fan: SystemMonitor.Fan) -> String {
        fan.rpm < 1 ? "Off" : percent(fan.fraction)
    }

    static func rpm(_ fan: SystemMonitor.Fan) -> String {
        fan.rpm < 1 ? "Off" : "\(Int(fan.rpm).formatted()) rpm"
    }

    private static var usesFahrenheit: Bool {
        Locale.current.measurementSystem == .us
    }

    private static func degrees(_ celsius: Double) -> Int {
        Int((usesFahrenheit ? celsius * 9 / 5 + 32 : celsius).rounded())
    }

    static func shortTemperature(_ celsius: Double?) -> String {
        celsius.map { "\(degrees($0))°" } ?? "—"
    }

    static func longTemperature(_ celsius: Double?) -> String {
        celsius.map { "\(degrees($0)) °\(usesFahrenheit ? "F" : "C")" } ?? "—"
    }

    /// Temperature on a 0–100 °C scale, for rings and bars.
    static func temperatureFraction(_ celsius: Double?) -> Double {
        min(1, max(0, (celsius ?? 0) / 100))
    }
}

private extension View {
    /// Keeps the monitor sampling while this widget is on screen.
    func monitoring(_ monitor: SystemMonitor) -> some View {
        onAppear { monitor.attach() }
            .onDisappear { monitor.detach() }
    }
}

private struct SystemHeader: View {
    let monitor: SystemMonitor

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "gauge.with.dots.needle.50percent")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Circle().fill(.tint))
            VStack(alignment: .leading, spacing: 1) {
                Text("System")
                    .font(.system(size: 13, weight: .semibold))
                Text("\(monitor.machineName) · \(monitor.chipName)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct SectionLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
    }
}

private struct ReadingRing: View {
    let fraction: Double
    let text: String
    let label: String
    let tint: Color

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                Circle().stroke(Color.panelTrack, lineWidth: 5)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(tint.gradient, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.smooth(duration: 0.6), value: fraction)
                Text(text)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.smooth, value: text)
            }
            .frame(width: 46, height: 46)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(text)
    }
}

private struct ReadingRow: View {
    let symbol: String
    let title: String
    let value: String
    let fraction: Double
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 16)
            Text(title)
                .font(.system(size: 12))
                .frame(width: 78, alignment: .leading)
            Capsule()
                .fill(Color.panelTrack)
                .frame(height: 5)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule()
                            .fill(tint.gradient)
                            .frame(width: proxy.size.width * fraction)
                    }
                }
                .animation(.smooth(duration: 0.6), value: fraction)
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 62, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }
}

private struct ReadingPill: View {
    let symbol: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity)
        .background(Color.panelControl, in: Capsule())
    }
}

/// Per-core load as bars, with efficiency and performance cores grouped.
private struct CoreBars: View {
    let cores: [SystemMonitor.Core]

    var body: some View {
        let efficiency = cores.filter(\.isEfficiency)
        let performance = cores.filter { !$0.isEfficiency }

        HStack(alignment: .top, spacing: 12) {
            if !efficiency.isEmpty {
                group("Efficiency", efficiency)
                    .frame(width: CGFloat(efficiency.count) * 26)
            }
            group(efficiency.isEmpty ? "All Cores" : "Performance", performance)
        }
    }

    private func group(_ label: String, _ cores: [SystemMonitor.Core]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Array(cores.enumerated()), id: \.offset) { _, core in
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color.panelTrack)
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color.cpu.gradient)
                            .frame(height: max(3, 26 * core.load))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 26)
                    .animation(.smooth(duration: 0.6), value: core.load)
                }
            }
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.tertiary)
        }
    }
}

/// The last minute of CPU load, filling in from the right.
private struct CPUHistoryChart: View {
    let history: [Double]

    var body: some View {
        let offset = SystemMonitor.historyLength - history.count
        Chart {
            ForEach(Array(history.enumerated()), id: \.offset) { index, value in
                AreaMark(x: .value("Time", offset + index), y: .value("CPU", value))
                    .foregroundStyle(Color.cpu.opacity(0.25).gradient)
                    .interpolationMethod(.catmullRom)
                LineMark(x: .value("Time", offset + index), y: .value("CPU", value))
                    .foregroundStyle(Color.cpu)
                    .interpolationMethod(.catmullRom)
            }
        }
        .chartXScale(domain: 0...(SystemMonitor.historyLength - 1))
        .chartYScale(domain: 0...1)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
    }
}
