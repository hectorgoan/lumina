import Darwin
import Foundation
import IOKit
import Observation

/// Samples CPU, memory, temperature and fan readings for the system widgets.
///
/// Sampling runs every two seconds, only while at least one system widget is
/// on screen.
@MainActor
@Observable
final class SystemMonitor {
    struct Core {
        let load: Double
        let isEfficiency: Bool
    }

    struct Fan: Equatable {
        let rpm: Double
        /// Speed as a fraction of the fan's maximum.
        let fraction: Double
    }

    static let shared = SystemMonitor()

    /// Readings kept for the CPU history graph: one minute.
    static let historyLength = 30
    private static let interval: Duration = .seconds(2)

    /// Overall CPU load, from 0 to 1.
    private(set) var cpu: Double = 0
    private(set) var cores: [Core] = []
    /// Memory in use (app, wired and compressed), from 0 to 1.
    private(set) var memory: Double = 0
    /// Average CPU temperature in °C, if the Mac reports it.
    private(set) var temperature: Double?
    /// The busiest fan, or nil on Macs without fans.
    private(set) var fan: Fan?
    private(set) var cpuHistory: [Double] = []

    /// For example "MacBook Pro".
    let machineName = SystemMonitor.readMachineName()
    /// For example "M1 Pro".
    let chipName = SystemMonitor.readChipName()

    @ObservationIgnored private var viewers = 0
    @ObservationIgnored private var sampling: Task<Void, Never>?
    @ObservationIgnored private var previousTicks: [[UInt32]] = []
    @ObservationIgnored private let sensors = SensorReader()
    @ObservationIgnored private let efficiencyCoreCount = SystemMonitor.readEfficiencyCoreCount()

    private init() {
        // Placeholder cores, so layouts don't jump before the first reading.
        cores = (0..<ProcessInfo.processInfo.activeProcessorCount).map {
            Core(load: 0, isEfficiency: $0 < efficiencyCoreCount)
        }
    }

    /// Call when a widget appears; sampling runs while any are visible.
    func attach() {
        viewers += 1
        guard viewers == 1 else { return }
        sampling = Task {
            // CPU load is measured between two snapshots: take the first one
            // now so real readings show up after half a second.
            previousTicks = Self.readCoreTicks()
            try? await Task.sleep(for: .milliseconds(500))
            while !Task.isCancelled {
                await sample()
                try? await Task.sleep(for: Self.interval)
            }
        }
    }

    func detach() {
        viewers = max(0, viewers - 1)
        guard viewers == 0 else { return }
        sampling?.cancel()
        sampling = nil
    }

    private func sample() async {
        sampleCPU()
        // Readings are kept at the precision the widgets show, and only
        // assigned when that changes, so tiny fluctuations don't redraw them.
        let memory = (Self.readMemoryUsage() * 100).rounded() / 100
        if memory != self.memory { self.memory = memory }

        let reading = await sensors.read()
        let temperature = reading.temperature?.rounded()
        if temperature != self.temperature { self.temperature = temperature }
        let fan = reading.fan.map { Fan(rpm: ($0.rpm / 10).rounded() * 10, fraction: ($0.fraction * 100).rounded() / 100) }
        if fan != self.fan { self.fan = fan }
    }

    // MARK: - CPU

    private func sampleCPU() {
        let ticks = Self.readCoreTicks()
        defer { previousTicks = ticks }
        guard previousTicks.count == ticks.count, !ticks.isEmpty else { return }

        var busyTotal = 0.0, allTotal = 0.0
        cores = ticks.indices.map { index in
            let now = ticks[index], before = previousTicks[index]
            let delta = (0..<Int(CPU_STATE_MAX)).map { Double(now[$0] &- before[$0]) }
            let all = delta.reduce(0, +)
            let idle = delta[Int(CPU_STATE_IDLE)]
            busyTotal += all - idle
            allTotal += all
            return Core(load: all > 0 ? (all - idle) / all : 0, isEfficiency: index < efficiencyCoreCount)
        }
        cpu = allTotal > 0 ? busyTotal / allTotal : 0
        cpuHistory.append(cpu)
        if cpuHistory.count > Self.historyLength {
            cpuHistory.removeFirst(cpuHistory.count - Self.historyLength)
        }
    }

    /// Per-core tick counters (user, system, idle, nice) since boot.
    private static func readCoreTicks() -> [[UInt32]] {
        var coreCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &coreCount, &info, &infoCount) == KERN_SUCCESS,
              let info
        else { return [] }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride))
        }
        let states = Int(CPU_STATE_MAX)
        return (0..<Int(coreCount)).map { core in
            (0..<states).map { UInt32(bitPattern: info[core * states + $0]) }
        }
    }

    // MARK: - Memory

    private static func readMemoryUsage() -> Double {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        // Matches Activity Monitor's "Memory Used": app memory, wired and compressed.
        let appPages = UInt64(stats.internal_page_count) - UInt64(stats.purgeable_count)
        let usedPages = appPages + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)
        let used = Double(usedPages) * Double(sysctlInt("hw.pagesize"))
        return min(1, used / Double(ProcessInfo.processInfo.physicalMemory))
    }

    // MARK: - Machine

    private static func readEfficiencyCoreCount() -> Int {
        // On Apple silicon, perflevel1 is the efficiency cluster, numbered first.
        guard sysctlInt("hw.nperflevels") > 1 else { return 0 }
        return sysctlInt("hw.perflevel1.logicalcpu")
    }

    private static func readChipName() -> String {
        let brand = sysctlString("machdep.cpu.brand_string") ?? ""
        return brand.hasPrefix("Apple ") ? String(brand.dropFirst(6)) : brand
    }

    private static func readMachineName() -> String {
        // "MacBook Pro (14-inch, 2021)" → "MacBook Pro"
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/product")
        defer { IOObjectRelease(entry) }
        if entry != 0,
           let data = IORegistryEntryCreateCFProperty(entry, "product-name" as CFString, kCFAllocatorDefault, 0)?
               .takeRetainedValue() as? Data,
           let name = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .controlCharacters)
        {
            return name.components(separatedBy: " (").first ?? name
        }
        return Host.current().localizedName ?? "Mac"
    }

    /// Reads a 32- or 64-bit integer sysctl (the buffer fits either).
    private static func sysctlInt(_ name: String) -> Int {
        var value: Int64 = 0
        var size = MemoryLayout<Int64>.size
        return sysctlbyname(name, &value, &size, nil, 0) == 0 ? Int(value) : 0
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }.map(UInt8.init), as: UTF8.self)
    }
}

/// Reads the SMC off the main thread. Finding the temperature keys means
/// walking a few thousand SMC keys, so that's done once and remembered.
private actor SensorReader {
    private let smc = SMC()
    private var temperatureKeys: [String]?
    private var fanCount: Int?

    func read() -> (temperature: Double?, fan: SystemMonitor.Fan?) {
        guard let smc else { return (nil, nil) }

        if temperatureKeys == nil {
            // CPU die sensors: "Tp" (performance) and "Te" (efficiency) keys.
            temperatureKeys = smc.allKeys().filter { $0.hasPrefix("Tp") || $0.hasPrefix("Te") }
            fanCount = Int(smc.number("FNum") ?? 0)
        }

        let readings = (temperatureKeys ?? []).compactMap(smc.number).filter { $0 > 5 && $0 < 130 }
        let temperature = readings.isEmpty ? nil : readings.reduce(0, +) / Double(readings.count)

        let fans = (0..<(fanCount ?? 0)).compactMap { index -> SystemMonitor.Fan? in
            guard let rpm = smc.number("F\(index)Ac"),
                  let maximum = smc.number("F\(index)Mx"), maximum > 0
            else { return nil }
            return SystemMonitor.Fan(rpm: rpm, fraction: min(1, max(0, rpm / maximum)))
        }
        return (temperature, fans.max { $0.fraction < $1.fraction })
    }
}
