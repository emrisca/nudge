import Foundation
import IOKit
import IOKit.pwr_mgt

/// Detects and controls macOS system power modes (Low Power, Automatic, High Power)
/// using `ProcessInfo`, `IOPMrootDomain` / IOKit power management, and `pmset`.
public final class PowerModeController: @unchecked Sendable {
    public static let shared = PowerModeController()

    private let lock = NSLock()
    private var cachedMode: PowerMode = .normal
    private var preferredMode: PowerMode = .normal
    private var lastPmsetPoll: Date = .distantPast
    private var powerStateObserver: NSObjectProtocol?

    public init() {
        cachedMode = detectCurrentMode(forceRefresh: true)
        preferredMode = cachedMode
        powerStateObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            _ = self.detectCurrentMode(forceRefresh: false)
        }
    }

    deinit {
        if let obs = powerStateObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    /// Detects the active macOS power mode. Uses fast `ProcessInfo` & IOKit checks on every call,
    /// throttling `pmset -g` inspection to keep idle CPU <1%.
    public func detectCurrentMode(forceRefresh: Bool = false) -> PowerMode {
        // Fast zero-spawn check: macOS Low Power Mode
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            lock.lock()
            cachedMode = .lowPower
            lock.unlock()
            return .lowPower
        }

        // Fast IOKit IOPMrootDomain check (zero subprocess overhead)
        if let ioMode = readIOPMRootDomainPowerMode() {
            lock.lock()
            cachedMode = ioMode
            lock.unlock()
            return ioMode
        }

        lock.lock()
        let shouldPollPmset = forceRefresh || Date().timeIntervalSince(lastPmsetPoll) >= 60.0
        let previous = cachedMode
        lock.unlock()

        if shouldPollPmset {
            let parsed = readPmsetPowerMode()
            lock.lock()
            lastPmsetPoll = Date()
            if let parsed {
                cachedMode = parsed
                lock.unlock()
                return parsed
            }
            // If previously lowPower and ProcessInfo reports false now, revert to normal
            if cachedMode == .lowPower {
                cachedMode = .normal
            }
            let result = cachedMode
            lock.unlock()
            return result
        }

        if previous == .lowPower {
            lock.lock()
            cachedMode = .normal
            lock.unlock()
            return .normal
        }
        return previous
    }

    /// Attempts to apply the requested `PowerMode` cleanly via `pmset` where permitted,
    /// tracking preference gracefully without crashing if running unprivileged.
    @discardableResult
    public func setPowerMode(_ mode: PowerMode) -> Bool {
        lock.lock()
        preferredMode = mode
        lock.unlock()

        let current = detectCurrentMode(forceRefresh: true)
        if current == mode {
            return true
        }

        // Try macOS `pmset -a powermode <0|1|2>` first (0=Automatic, 1=Low Power, 2=High Power)
        let powerModeValue: String
        switch mode {
        case .normal:    powerModeValue = "0"
        case .lowPower:  powerModeValue = "1"
        case .highPower: powerModeValue = "2"
        }

        var succeeded = runPmset(arguments: ["-a", "powermode", powerModeValue])

        // Fallback to `lowpowermode <0|1>` on Macs without High Power Mode support
        if !succeeded && (mode == .lowPower || mode == .normal) {
            let lpmVal = (mode == .lowPower) ? "1" : "0"
            succeeded = runPmset(arguments: ["-a", "lowpowermode", lpmVal])
        }

        if succeeded {
            lock.lock()
            cachedMode = mode
            lastPmsetPoll = Date()
            lock.unlock()
        }

        return succeeded
    }

    public var currentPreferredMode: PowerMode {
        lock.lock()
        defer { lock.unlock() }
        return preferredMode
    }

    // MARK: - Private Platform Probes

    /// Queries `IOPMrootDomain` in IORegistry for system power mode properties without spawning a subprocess.
    private func readIOPMRootDomainPowerMode() -> PowerMode? {
        let matching = IOServiceMatching("IOPMrootDomain")
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        if let pmNum = IORegistryEntryCreateCFProperty(
            service,
            "PowerMode" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? NSNumber {
            switch pmNum.intValue {
            case 1: return .lowPower
            case 2: return .highPower
            default: return .normal
            }
        }

        if let lpmNum = IORegistryEntryCreateCFProperty(
            service,
            "LowPowerMode" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? NSNumber, lpmNum.intValue == 1 {
            return .lowPower
        }

        return nil
    }

    private func readPmsetPowerMode() -> PowerMode? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return nil }

        return Self.parsePmsetOutput(output)
    }

    internal static func parsePmsetOutput(_ output: String) -> PowerMode? {
        var foundLowPower: Int?
        var foundPowerMode: Int?

        for rawLine in output.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces).lowercased()
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count >= 2 else { continue }

            if parts[0] == "powermode", let val = Int(parts[1]) {
                foundPowerMode = val
            } else if parts[0] == "lowpowermode", let val = Int(parts[1]) {
                foundLowPower = val
            }
        }

        if let pm = foundPowerMode {
            switch pm {
            case 1: return .lowPower
            case 2: return .highPower
            default: return .normal
            }
        }
        if let lpm = foundLowPower {
            return lpm == 1 ? .lowPower : .normal
        }
        return nil
    }

    private func runPmset(arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
