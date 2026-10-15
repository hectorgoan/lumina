import Foundation
import IOKit.ps
import Observation

/// A device with a battery: the Mac itself or an accessory such as AirPods,
/// a keyboard or a mouse.
struct BatteryDevice: Identifiable, Equatable {
    /// Stable across launches, so widgets can remember chosen devices.
    let id: String
    let name: String
    /// Charge, from 0 to 1.
    let level: Double
    let isCharging: Bool
    /// An SF Symbol for the kind of device.
    let symbol: String

    var isLow: Bool { level <= 0.2 }
}

/// Keeps a live list of every device macOS reports a battery level for.
///
/// The list comes from macOS's power sources, the same data as its own
/// Batteries widget: the Mac's battery through the public API, and
/// Bluetooth accessories through `IOPSCopyPowerSourcesByType`, which IOKit
/// exports but doesn't declare publicly (`pmset -g accps` uses it). Devices
/// come and go as they connect; the list refreshes whenever macOS reports a
/// change, and every minute.
@MainActor
@Observable
final class BatteryMonitor {
    static let shared = BatteryMonitor()

    private(set) var devices: [BatteryDevice] = []

    @ObservationIgnored private var poller: Task<Void, Never>?

    private init() {
        refresh()
        // macOS calls this whenever a power source changes.
        if let source = IOPSNotificationCreateRunLoopSource({ _ in
            Task { @MainActor in BatteryMonitor.shared.refresh() }
        }, nil)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        }
        // Accessory levels don't always trigger a notification.
        poller = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                self?.refresh()
            }
        }
    }

    func refresh() {
        let fresh = Self.readDevices()
        if fresh != devices { devices = fresh }
    }

    func device(withID id: String) -> BatteryDevice? {
        devices.first { $0.id == id }
    }

    // MARK: - Reading power sources

    private typealias CopyPowerSourcesByType = @convention(c) (Int32) -> Unmanaged<CFTypeRef>?

    /// The accessory power sources (`kIOPSSourceAll` in IOKit's private
    /// header, though it doesn't include the Mac's own battery).
    private static let accessorySourceTypes: Int32 = 4

    private static let copyPowerSourcesByType: CopyPowerSourcesByType? = {
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW),
              let symbol = dlsym(handle, "IOPSCopyPowerSourcesByType")
        else { return nil }
        return unsafeBitCast(symbol, to: CopyPowerSourcesByType.self)
    }()

    private static func readDevices() -> [BatteryDevice] {
        // The Mac's own battery comes from the public API, accessories from
        // the exported call; if that ever goes away, the Mac still shows.
        let blobs = [
            IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            copyPowerSourcesByType?(accessorySourceTypes)?.takeRetainedValue(),
        ].compactMap { $0 }

        var seen = Set<String>()
        let devices = blobs.flatMap { blob -> [BatteryDevice] in
            let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] ?? []
            return sources.compactMap { source -> BatteryDevice? in
                guard let info = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                      info[kIOPSIsPresentKey] as? Bool ?? true,
                      let current = info[kIOPSCurrentCapacityKey] as? Int,
                      let maximum = info[kIOPSMaxCapacityKey] as? Int, maximum > 0
                else { return nil }
                return device(from: info, level: min(1, Double(current) / Double(maximum)))
            }
        }
        .filter { seen.insert($0.id).inserted }
        // The Mac first, then accessories by name, so the list stays stable.
        return devices.sorted { lhs, rhs in
            if (lhs.id == internalID) != (rhs.id == internalID) { return lhs.id == internalID }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private static let internalID = "internal-battery"

    private static func device(from info: [String: Any], level: Double) -> BatteryDevice {
        let isCharging = info[kIOPSIsChargingKey] as? Bool ?? false

        if info[kIOPSTypeKey] as? String == kIOPSInternalBatteryType {
            return BatteryDevice(
                id: internalID,
                name: SystemMonitor.shared.machineName,
                level: level,
                isCharging: isCharging,
                symbol: "laptopcomputer"
            )
        }

        let name = info[kIOPSNameKey] as? String ?? "Accessory"
        let id = info["Accessory Identifier"] as? String ?? name
        let category = info["Accessory Category"] as? String ?? ""
        let productID = info[kIOPSProductIDKey] as? Int ?? 0
        let vendorID = info[kIOPSVendorIDKey] as? Int ?? 0
        return BatteryDevice(
            id: id,
            name: name,
            level: level,
            isCharging: isCharging,
            symbol: symbol(forCategory: category, productID: productID, isApple: vendorID == 76)
        )
    }

    private static func symbol(forCategory category: String, productID: Int, isApple: Bool) -> String {
        // Apple Bluetooth product IDs for AirPods models.
        let airPodsPro = [0x200E, 0x2014, 0x2024, 0x2027]
        let airPodsMax = [0x200A, 0x201F]

        switch category {
        case "Audio Battery Case":
            return airPodsPro.contains(productID) ? "airpods.pro.chargingcase.wireless.fill" : "airpods.chargingcase.fill"
        case "Headset", "Headphones":
            if airPodsMax.contains(productID) { return "airpods.max" }
            if airPodsPro.contains(productID) { return "airpods.pro" }
            return isApple ? "airpods" : "headphones"
        case "Keyboard":
            return "keyboard"
        case "Mouse":
            return isApple ? "magicmouse.fill" : "computermouse.fill"
        case "Trackpad":
            return "rectangle.and.hand.point.up.left.fill"
        case "Game Controller":
            return "gamecontroller.fill"
        case "Pencil":
            return "applepencil"
        default:
            return "battery.100percent"
        }
    }
}
