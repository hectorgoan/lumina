import Foundation
import IOKit

/// Reads sensors from the System Management Controller (SMC).
///
/// macOS has no public API for CPU temperature or fan speed, so this talks to
/// the AppleSMC driver directly, as tools like iStat Menus do. It works
/// outside the App Sandbox and needs no special permission.
final class SMC {
    private let connection: io_connect_t

    init?() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var connection: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == kIOReturnSuccess else { return nil }
        self.connection = connection
    }

    deinit {
        IOServiceClose(connection)
    }

    /// All the SMC's key names, such as "Tp01" or "F0Ac".
    func allKeys() -> [String] {
        let count = Int(number("#KEY") ?? 0)
        return (0..<count).compactMap { key(at: UInt32($0)) }
    }

    /// A key's value as a number, decoding the SMC's common data types.
    func number(_ key: String) -> Double? {
        guard let (type, bytes) = read(key) else { return nil }
        switch (type, bytes.count) {
        case ("flt ", 4):
            return Double(bytes.withUnsafeBytes { $0.loadUnaligned(as: Float.self) })
        case ("fpe2", 2):
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) / 4
        case ("sp78", 2):
            return Double(Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))) / 256
        case ("ui8 ", 1):
            return Double(bytes[0])
        case ("ui16", 2):
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        case ("ui32", 4):
            return Double(bytes.reduce(UInt32(0)) { $0 << 8 | UInt32($1) })
        default:
            return nil
        }
    }

    // MARK: - Driver calls

    private enum Command: UInt8 {
        case readKey = 5
        case keyAtIndex = 8
        case keyInfo = 9
    }

    private func read(_ key: String) -> (type: String, bytes: [UInt8])? {
        let code = Self.code(key)
        var request = Param()
        request.key = code
        request.command = Command.keyInfo.rawValue
        guard let info = call(&request)?.keyInfo else { return nil }

        request = Param()
        request.key = code
        request.keyInfo.dataSize = info.dataSize
        request.command = Command.readKey.rawValue
        guard let response = call(&request) else { return nil }
        let bytes = withUnsafeBytes(of: response.bytes) { Array($0.prefix(Int(info.dataSize))) }
        return (Self.name(info.dataType), bytes)
    }

    private func key(at index: UInt32) -> String? {
        var request = Param()
        request.command = Command.keyAtIndex.rawValue
        request.data32 = index
        return call(&request).map { Self.name($0.key) }
    }

    private func call(_ request: inout Param) -> Param? {
        var response = Param()
        var size = MemoryLayout<Param>.stride
        let result = IOConnectCallStructMethod(connection, 2, &request, MemoryLayout<Param>.stride, &response, &size)
        return result == kIOReturnSuccess && response.result == 0 ? response : nil
    }

    private static func code(_ name: String) -> UInt32 {
        name.utf8.reduce(0) { $0 << 8 | UInt32($1) }
    }

    private static func name(_ code: UInt32) -> String {
        String(bytes: [24, 16, 8, 0].map { UInt8((code >> $0) & 0xFF) }, encoding: .ascii) ?? ""
    }

    // MARK: - Driver structures (mirror the kernel's SMCKeyData_t, 80 bytes)

    private struct Version {
        var major: UInt8 = 0, minor: UInt8 = 0, build: UInt8 = 0, reserved: UInt8 = 0
        var release: UInt16 = 0
    }

    private struct PowerLimits {
        var version: UInt16 = 0, length: UInt16 = 0
        var cpuLimit: UInt32 = 0, gpuLimit: UInt32 = 0, memoryLimit: UInt32 = 0
    }

    private struct KeyInfo {
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }

    private struct Param {
        var key: UInt32 = 0
        var version = Version()
        var powerLimits = PowerLimits()
        var keyInfo = KeyInfo()
        var padding: UInt16 = 0
        var result: UInt8 = 0
        var status: UInt8 = 0
        var command: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: (UInt64, UInt64, UInt64, UInt64) = (0, 0, 0, 0)
    }
}
