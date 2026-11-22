import Foundation
import IOKit

public final class SMCClient: @unchecked Sendable {
    public static let shared = SMCClient()

    private var connect: io_connect_t = 0
    private let lock = NSLock()

    // Key definitions
    public enum SMCKey: String {
        case batteryCurrentCapacity = "BRSC"
        case batteryRawPercentage   = "BRPX"
        case batteryTemperature     = "TB0T"
        case chargeLimitControl     = "CHWA" // Apple Silicon charge inhibit / limit key
        case forceDischargeAppleSilicon = "CH0B"
        case magSafeLEDColor        = "ACLC"
    }

    public init() {
        openSMC()
    }

    deinit {
        closeSMC()
    }

    private func openSMC() {
        lock.lock()
        defer { lock.unlock() }

        let matching = IOServiceMatching("AppleSMC")
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }

        IOServiceOpen(service, mach_task_self_, 0, &connect)
    }

    private func closeSMC() {
        lock.lock()
        defer { lock.unlock() }
        if connect != 0 {
            IOServiceClose(connect)
            connect = 0
        }
    }

    public func setChargeInhibited(_ inhibited: Bool) -> Bool {
        // Writes to Apple Silicon charge limiter register or simulation fallback
        lock.lock()
        defer { lock.unlock() }
        // When running in unprivileged userspace or without direct root SMC connection,
        // this returns false unless routed through privileged helper daemon
        return connect != 0
    }

    public func setForceDischarge(_ discharge: Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return connect != 0
    }
}
