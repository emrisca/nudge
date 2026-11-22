import Foundation
import IOKit

// MARK: - AppleSMC User-Client C-Compatible Structs (80-byte SMCKeyData_t)

public struct SMCKeyDataVers_t: Sendable {
    public var major: UInt8 = 0
    public var minor: UInt8 = 0
    public var build: UInt8 = 0
    public var reserved: UInt8 = 0
    public var release: UInt16 = 0

    public init() {}
}

public struct SMCKeyDataPLimitData_t: Sendable {
    public var version: UInt16 = 0
    public var length: UInt16 = 0
    public var cpuPLimit: UInt32 = 0
    public var gpuPLimit: UInt32 = 0
    public var memPLimit: UInt32 = 0

    public init() {}
}

public struct SMCKeyDataKeyInfo_t: Sendable {
    public var dataSize: UInt32 = 0
    public var dataType: UInt32 = 0
    public var dataAttributes: UInt8 = 0

    public init() {}
}

public typealias SMCBytes_t = (
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
)

public struct SMCKeyData_t: Sendable {
    public var key: UInt32 = 0
    public var vers: SMCKeyDataVers_t = SMCKeyDataVers_t()
    public var pLimitData: SMCKeyDataPLimitData_t = SMCKeyDataPLimitData_t()
    public var keyInfo: SMCKeyDataKeyInfo_t = SMCKeyDataKeyInfo_t()
    public var result: UInt8 = 0
    public var status: UInt8 = 0
    public var data8: UInt8 = 0
    public var data32: UInt32 = 0
    public var bytes: SMCBytes_t = (
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0
    )

    public init() {}
}

public struct SMCVal_t: Sendable, Equatable {
    public let key: String
    public let dataSize: UInt32
    public let dataType: String
    public let bytes: [UInt8]

    public init(key: String, dataSize: UInt32, dataType: String, bytes: [UInt8]) {
        self.key = key
        self.dataSize = dataSize
        self.dataType = dataType
        self.bytes = bytes
    }
}

// MARK: - AppleSMC Client

public final class SMCClient: @unchecked Sendable {
    public static let shared = SMCClient()

    /// Compile-time host architecture detection (Apple Silicon vs Intel).
    public static var currentArchitecture: ArchitectureType {
        #if arch(arm64)
        return .appleSilicon
        #else
        return .intel
        #endif
    }

    public let architecture: ArchitectureType

    // AppleSMC IOConnectCallStructMethod constants
    private static let kSMCHandleYPCEvent: UInt32 = 2
    private static let kSMCReadKey: UInt8 = 5
    private static let kSMCWriteKey: UInt8 = 6
    private static let kSMCGetKeyInfo: UInt8 = 9

    private var connect: io_connect_t = 0
    private let lock = NSLock()
    private let helperClient: HelperXPCClient

    // Tracked desired state for graceful fallback when unprivileged
    private var _desiredChargeLimit: Int = 80
    private var _desiredChargeInhibited: Bool = false
    private var _desiredForceDischarge: Bool = false
    private var _desiredMagSafeLED: MagSafeLEDState = .systemDefault

    // Key definitions covering Apple Silicon and Intel SMC registers
    public enum SMCKey: String, Sendable, CaseIterable {
        // Battery telemetry
        case batteryCurrentCapacity      = "BRSC" // Apple Silicon raw battery capacity / SoC
        case batteryRawPercentage        = "BRPX" // Raw percentage key
        case batteryTemperature          = "TB0T" // Battery temperature sensor (°C)

        // Apple Silicon charge & adapter control
        case chargeLimitControl          = "CHWA" // Apple Silicon 80% hardware charge limit toggle
        case forceDischargeAppleSilicon  = "CH0B" // Charge inhibit register (0x00=allow, 0x02=inhibit)
        case chargeInhibitC              = "CH0C" // Secondary charge inhibit register on newer Apple Silicon
        case adapterInhibit              = "CH0I" // Adapter disconnect / force discharge (0x00=AC, 0x01=battery)

        // Intel charge limit control
        case intelChargeLimit            = "BCLM" // Intel Battery Charge Level Max (10...100)

        // MagSafe LED control (both Apple Silicon & Intel)
        case magSafeLEDColor             = "ACLC" // 0x00=system, 0x01=off, 0x03=green, 0x04=orange, 0x06=blink
    }

    public init(
        architecture: ArchitectureType = SMCClient.currentArchitecture,
        helperClient: HelperXPCClient = .shared
    ) {
        self.architecture = architecture
        self.helperClient = helperClient
        openSMC()
    }

    deinit {
        closeSMC()
    }

    public var isConnected: Bool {
        lock.lock()
        defer { lock.unlock() }
        return connect != 0
    }

    public var desiredChargeInhibited: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _desiredChargeInhibited
    }

    public var desiredForceDischarge: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _desiredForceDischarge
    }

    public var desiredMagSafeLED: MagSafeLEDState {
        lock.lock()
        defer { lock.unlock() }
        return _desiredMagSafeLED
    }

    public var desiredChargeLimit: Int {
        lock.lock()
        defer { lock.unlock() }
        return _desiredChargeLimit
    }

    // MARK: - Connection Lifecycle

    private func openSMC() {
        lock.lock()
        defer { lock.unlock() }

        guard connect == 0 else { return }
        let matching = IOServiceMatching("AppleSMC")
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }

        var newConnect: io_connect_t = 0
        let kr = IOServiceOpen(service, task_self_trap(), 0, &newConnect)
        if kr == kIOReturnSuccess {
            connect = newConnect
        }
    }

    private func closeSMC() {
        lock.lock()
        defer { lock.unlock() }
        if connect != 0 {
            IOServiceClose(connect)
            connect = 0
        }
    }

    // MARK: - Low-Level Key Read / Write

    public func readKey(_ key: String) -> SMCVal_t? {
        guard key.utf8.count == 4 else { return nil }

        lock.lock()
        defer { lock.unlock() }

        guard connect != 0 else { return nil }
        guard let keyCode = Self.fourCharCode(from: key) else { return nil }

        // Step 1: Query key metadata (size & type)
        var infoInput = SMCKeyData_t()
        infoInput.key = keyCode
        infoInput.data8 = Self.kSMCGetKeyInfo

        guard let infoOutput = callSMCLocked(input: infoInput),
              infoOutput.result == 0,
              infoOutput.keyInfo.dataSize > 0,
              infoOutput.keyInfo.dataSize <= 32 else {
            return nil
        }

        // Step 2: Read key payload bytes
        var readInput = SMCKeyData_t()
        readInput.key = keyCode
        readInput.keyInfo.dataSize = infoOutput.keyInfo.dataSize
        readInput.data8 = Self.kSMCReadKey

        guard let readOutput = callSMCLocked(input: readInput),
              readOutput.result == 0 else {
            return nil
        }

        let size = Int(infoOutput.keyInfo.dataSize)
        let rawBytes = Self.extractBytes(from: readOutput.bytes, count: size)
        let dataType = Self.string(fromFourCharCode: infoOutput.keyInfo.dataType)

        return SMCVal_t(
            key: key,
            dataSize: infoOutput.keyInfo.dataSize,
            dataType: dataType,
            bytes: rawBytes
        )
    }

    public func readKey(_ key: SMCKey) -> SMCVal_t? {
        readKey(key.rawValue)
    }

    @discardableResult
    public func writeKey(_ key: String, bytes: [UInt8]) -> Bool {
        guard key.utf8.count == 4, !bytes.isEmpty, bytes.count <= 32 else { return false }

        lock.lock()
        defer { lock.unlock() }

        guard connect != 0 else { return false }
        guard let keyCode = Self.fourCharCode(from: key) else { return false }

        // Query expected key info so dataSize matches hardware register width
        var infoInput = SMCKeyData_t()
        infoInput.key = keyCode
        infoInput.data8 = Self.kSMCGetKeyInfo

        guard let infoOutput = callSMCLocked(input: infoInput),
              infoOutput.result == 0,
              infoOutput.keyInfo.dataSize > 0,
              infoOutput.keyInfo.dataSize <= 32 else {
            return false
        }

        let targetSize = Int(infoOutput.keyInfo.dataSize)
        var padded = Array(repeating: UInt8(0), count: targetSize)
        for i in 0..<min(bytes.count, targetSize) {
            padded[i] = bytes[i]
        }

        var writeInput = SMCKeyData_t()
        writeInput.key = keyCode
        writeInput.data8 = Self.kSMCWriteKey
        writeInput.keyInfo.dataSize = infoOutput.keyInfo.dataSize
        writeInput.bytes = Self.packBytes(padded)

        guard let writeOutput = callSMCLocked(input: writeInput) else {
            return false
        }

        return writeOutput.result == 0
    }

    @discardableResult
    public func writeKey(_ key: SMCKey, bytes: [UInt8]) -> Bool {
        writeKey(key.rawValue, bytes: bytes)
    }

    // MARK: - High-Level Hardware Controls

    /// Inhibits or permits battery charging via AppleSMC (with privileged helper XPC fallback).
    @discardableResult
    public func setChargeInhibited(_ inhibited: Bool) -> Bool {
        lock.lock()
        _desiredChargeInhibited = inhibited
        let limit = _desiredChargeLimit
        let discharge = _desiredForceDischarge
        lock.unlock()

        let value: UInt8 = inhibited ? 0x02 : 0x00
        var succeeded = false

        switch architecture {
        case .appleSilicon:
            let ch0b = writeKey(.forceDischargeAppleSilicon, bytes: [value])
            let ch0c = writeKey(.chargeInhibitC, bytes: [value])
            succeeded = ch0b || ch0c
        case .intel:
            succeeded = writeKey(.forceDischargeAppleSilicon, bytes: [value])
        }

        if !succeeded && helperClient.isConnected {
            succeeded = helperClient.setChargeLimit(
                limit,
                sailingDeadband: 5,
                inhibitCharging: inhibited,
                forceDischarge: discharge
            )
        }
        return succeeded
    }

    /// Programs the hardware charge ceiling where supported (Intel `BCLM`, Apple Silicon `CHWA` for 80%).
    @discardableResult
    public func setChargeLimit(_ percentage: Int) -> Bool {
        let clamped = max(20, min(100, percentage))
        lock.lock()
        _desiredChargeLimit = clamped
        let inhibited = _desiredChargeInhibited
        let discharge = _desiredForceDischarge
        lock.unlock()

        var succeeded = false
        switch architecture {
        case .intel:
            succeeded = writeKey(.intelChargeLimit, bytes: [UInt8(clamped)])
        case .appleSilicon:
            // CHWA supports Apple's native 80% hardware hold when exactly 80%; otherwise CH0B/CH0C enforces custom limits.
            let chwaByte: UInt8 = (clamped == 80) ? 0x01 : 0x00
            succeeded = writeKey(.chargeLimitControl, bytes: [chwaByte])
        }

        if !succeeded && helperClient.isConnected {
            succeeded = helperClient.setChargeLimit(
                clamped,
                sailingDeadband: 5,
                inhibitCharging: inhibited,
                forceDischarge: discharge
            )
        }
        return succeeded
    }

    /// Simulates battery discharge while plugged in by cutting adapter power input (`CH0I` on Apple Silicon).
    @discardableResult
    public func setForceDischarge(_ discharge: Bool) -> Bool {
        lock.lock()
        _desiredForceDischarge = discharge
        let limit = _desiredChargeLimit
        let inhibited = _desiredChargeInhibited
        lock.unlock()

        var succeeded = false
        switch architecture {
        case .appleSilicon:
            let adapterByte: UInt8 = discharge ? 0x01 : 0x00
            let ch0i = writeKey(.adapterInhibit, bytes: [adapterByte])
            let ch0b = discharge ? writeKey(.forceDischargeAppleSilicon, bytes: [0x02]) : true
            succeeded = ch0i && ch0b
        case .intel:
            let ch0i = writeKey(.adapterInhibit, bytes: [discharge ? 0x01 : 0x00])
            let ch0b = writeKey(.forceDischargeAppleSilicon, bytes: [discharge ? 0x02 : 0x00])
            succeeded = ch0i || ch0b
        }

        if !succeeded && helperClient.isConnected {
            succeeded = helperClient.setChargeLimit(
                limit,
                sailingDeadband: 5,
                inhibitCharging: discharge ? true : inhibited,
                forceDischarge: discharge
            )
        }
        return succeeded
    }

    /// Controls the MagSafe connector LED color via `ACLC` (with helper XPC fallback).
    @discardableResult
    public func setMagSafeLED(_ state: MagSafeLEDState) -> Bool {
        lock.lock()
        _desiredMagSafeLED = state
        lock.unlock()

        let code = Self.magSafeCode(for: state)
        var succeeded = writeKey(.magSafeLEDColor, bytes: [code])
        if !succeeded && helperClient.isConnected {
            succeeded = helperClient.setMagSafeLED(state)
        }
        return succeeded
    }

    /// Reads battery temperature in °C from SMC key `TB0T` (handles `sp78` fixed-point and `flt` float formats).
    public func readBatteryTemperature() -> Double? {
        guard let val = readKey(.batteryTemperature) else { return nil }
        return Self.decodeTemperature(from: val)
    }

    /// Reads raw battery state-of-charge / capacity register from SMC key `BRSC` (or `BRPX` fallback).
    public func readBatteryCapacity() -> Int? {
        if let val = readKey(.batteryCurrentCapacity), let decoded = Self.decodeUnsignedInt(from: val) {
            return decoded
        }
        if let val = readKey(.batteryRawPercentage), let decoded = Self.decodeUnsignedInt(from: val) {
            return decoded
        }
        return nil
    }

    /// Reads the current MagSafe LED state from `ACLC` if readable.
    public func readMagSafeLED() -> MagSafeLEDState? {
        guard let val = readKey(.magSafeLEDColor), let first = val.bytes.first else {
            return nil
        }
        switch first {
        case 0x00: return .systemDefault
        case 0x01: return .off
        case 0x03: return .green
        case 0x04: return .orange
        case 0x05, 0x06: return .blinkingOrange
        default: return .systemDefault
        }
    }

    // MARK: - Private SMC Struct Bridging Helpers

    private func callSMCLocked(input: SMCKeyData_t) -> SMCKeyData_t? {
        guard connect != 0 else { return nil }
        var inStruct = input
        var outStruct = SMCKeyData_t()
        let inputSize = MemoryLayout<SMCKeyData_t>.stride
        var outputSize = MemoryLayout<SMCKeyData_t>.stride

        let result = IOConnectCallStructMethod(
            connect,
            Self.kSMCHandleYPCEvent,
            &inStruct,
            inputSize,
            &outStruct,
            &outputSize
        )

        guard result == kIOReturnSuccess else {
            return nil
        }
        return outStruct
    }

    internal static func magSafeCode(for state: MagSafeLEDState) -> UInt8 {
        switch state {
        case .systemDefault:  return 0x00
        case .off:            return 0x01
        case .green:          return 0x03
        case .orange:         return 0x04
        case .blinkingOrange: return 0x06
        }
    }

    internal static func fourCharCode(from key: String) -> UInt32? {
        let utf8 = Array(key.utf8)
        guard utf8.count == 4 else { return nil }
        return (UInt32(utf8[0]) << 24)
            | (UInt32(utf8[1]) << 16)
            | (UInt32(utf8[2]) << 8)
            | UInt32(utf8[3])
    }

    internal static func string(fromFourCharCode code: UInt32) -> String {
        let bytes: [UInt8] = [
            UInt8((code >> 24) & 0xFF),
            UInt8((code >> 16) & 0xFF),
            UInt8((code >> 8) & 0xFF),
            UInt8(code & 0xFF)
        ]
        return String(bytes: bytes, encoding: .ascii) ?? "????"
    }

    private static func extractBytes(from tuple: SMCBytes_t, count: Int) -> [UInt8] {
        let clamped = max(0, min(32, count))
        var copy = tuple
        return withUnsafeBytes(of: &copy) { raw in
            Array(raw.prefix(clamped))
        }
    }

    private static func packBytes(_ bytes: [UInt8]) -> SMCBytes_t {
        var tuple: SMCBytes_t = (
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0
        )
        withUnsafeMutableBytes(of: &tuple) { raw in
            for i in 0..<min(bytes.count, 32) {
                raw[i] = bytes[i]
            }
        }
        return tuple
    }

    internal static func decodeTemperature(from val: SMCVal_t) -> Double? {
        let trimmedType = val.dataType.trimmingCharacters(in: .whitespaces)
        if trimmedType == "flt" && val.bytes.count >= 4 {
            // Apple Silicon SMC `flt ` is IEEE 754 little-endian Float32
            let bits = UInt32(val.bytes[0])
                | (UInt32(val.bytes[1]) << 8)
                | (UInt32(val.bytes[2]) << 16)
                | (UInt32(val.bytes[3]) << 24)
            let temp = Double(Float(bitPattern: bits))
            return (temp > -20.0 && temp < 120.0) ? temp : nil
        }
        if trimmedType == "sp78" && val.bytes.count >= 2 {
            // Big-endian signed 7.8 fixed-point
            let raw = Int16(bitPattern: (UInt16(val.bytes[0]) << 8) | UInt16(val.bytes[1]))
            let temp = Double(raw) / 256.0
            return (temp > -20.0 && temp < 120.0) ? temp : nil
        }
        if val.bytes.count >= 2 {
            let raw = Int16(bitPattern: (UInt16(val.bytes[0]) << 8) | UInt16(val.bytes[1]))
            let temp = Double(raw) / 256.0
            if temp > -20.0 && temp < 120.0 {
                return temp
            }
        }
        return nil
    }

    private static func decodeUnsignedInt(from val: SMCVal_t) -> Int? {
        guard !val.bytes.isEmpty else { return nil }
        switch val.bytes.count {
        case 1:
            return Int(val.bytes[0])
        case 2:
            let be = (UInt16(val.bytes[0]) << 8) | UInt16(val.bytes[1])
            return Int(be)
        default:
            let be = (UInt32(val.bytes[0]) << 24)
                | (UInt32(val.bytes[1]) << 16)
                | (UInt32(val.bytes[2]) << 8)
                | UInt32(val.bytes[3])
            return Int(be)
        }
    }
}
