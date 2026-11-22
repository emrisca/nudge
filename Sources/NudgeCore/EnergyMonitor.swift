import Foundation
import AppKit
import Darwin

/// Monitors running macOS applications using `NSWorkspace` and `proc_pid_rusage` (`rusage_info_v4`)
/// to calculate live CPU %, memory footprint (MB), normalized Energy Impact, and estimated Watts.
public final class EnergyMonitor: @unchecked Sendable {
    private struct SampleRecord {
        let totalCPUNanoseconds: UInt64
        let idleWakeups: UInt64
        let diskIOBytes: UInt64
        let timestamp: Date
    }

    private let lock = NSLock()
    private var previousSamples: [Int32: SampleRecord] = [:]
    private let nanosecondsPerMachTick: Double

    public init() {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        if timebase.denom > 0 {
            self.nanosecondsPerMachTick = Double(timebase.numer) / Double(timebase.denom)
        } else {
            self.nanosecondsPerMachTick = 1.0
        }
    }

    /// Samples running user-facing applications and returns top energy consumers sorted by impact score.
    public func sampleHighEnergyApps(
        limit: Int = 10,
        systemLoadWatts: Double = 10.0,
        now: Date = Date()
    ) -> [HighEnergyApp] {
        let runningApps = NSWorkspace.shared.runningApplications
        let currentPID = getpid()

        lock.lock()
        let prevMap = previousSamples
        lock.unlock()

        var nextSamples: [Int32: SampleRecord] = [:]
        var rawEntries: [(app: NSRunningApplication, cpu: Double, impact: Double, memMB: Double)] = []

        for app in runningApps {
            let pid = app.processIdentifier
            guard pid > 0, pid != currentPID else { continue }
            guard app.activationPolicy == .regular || app.activationPolicy == .accessory else { continue }
            guard let name = app.localizedName, !name.isEmpty else { continue }

            guard let rusage = readRusage(pid: pid) else { continue }

            let totalTicks = rusage.ri_user_time &+ rusage.ri_system_time
            let totalCPUNs = UInt64(Double(totalTicks) * nanosecondsPerMachTick)
            let idleWakeups = rusage.ri_pkg_idle_wkups
            let diskIO = rusage.ri_diskio_bytesread &+ rusage.ri_diskio_byteswritten
            let memMB = Double(rusage.ri_phys_footprint) / (1024.0 * 1024.0)

            nextSamples[pid] = SampleRecord(
                totalCPUNanoseconds: totalCPUNs,
                idleWakeups: idleWakeups,
                diskIOBytes: diskIO,
                timestamp: now
            )

            let cpuPercent: Double
            let wakeupsPerSec: Double
            let diskMBPerSec: Double

            if let prev = prevMap[pid] {
                let dt = now.timeIntervalSince(prev.timestamp)
                if dt > 0.1 {
                    let deltaCPU = totalCPUNs >= prev.totalCPUNanoseconds ? (totalCPUNs - prev.totalCPUNanoseconds) : 0
                    cpuPercent = (Double(deltaCPU) / (dt * 1_000_000_000.0)) * 100.0

                    let deltaWakeups = idleWakeups >= prev.idleWakeups ? (idleWakeups - prev.idleWakeups) : 0
                    wakeupsPerSec = Double(deltaWakeups) / dt

                    let deltaDisk = diskIO >= prev.diskIOBytes ? (diskIO - prev.diskIOBytes) : 0
                    diskMBPerSec = (Double(deltaDisk) / (1024.0 * 1024.0)) / dt
                } else {
                    cpuPercent = 0.0
                    wakeupsPerSec = 0.0
                    diskMBPerSec = 0.0
                }
            } else {
                // First sample baseline: estimate lightweight activity from process uptime & cumulative CPU
                let launchAge = max(1.0, app.launchDate.map { now.timeIntervalSince($0) } ?? 60.0)
                let avgCPU = (Double(totalCPUNs) / (launchAge * 1_000_000_000.0)) * 100.0
                cpuPercent = min(100.0, avgCPU)
                wakeupsPerSec = Double(idleWakeups) / launchAge
                diskMBPerSec = (Double(diskIO) / (1024.0 * 1024.0)) / launchAge
            }

            // Normalized Energy Impact score (similar to macOS Activity Monitor weighting)
            let energyImpact = (cpuPercent * 1.0)
                + (wakeupsPerSec * 0.05)
                + (diskMBPerSec * 0.8)
                + min(5.0, memMB / 1024.0)

            rawEntries.append((app: app, cpu: cpuPercent, impact: energyImpact, memMB: memMB))
        }

        lock.lock()
        previousSamples = nextSamples
        lock.unlock()

        // Sort descending by energy impact
        rawEntries.sort { $0.impact > $1.impact }

        let totalImpact = max(1.0, rawEntries.reduce(0.0) { $0 + $1.impact })
        let attributableWatts = max(1.0, systemLoadWatts * 0.75)

        func round1(_ v: Double) -> Double { (v * 10.0).rounded() / 10.0 }
        func round2(_ v: Double) -> Double { (v * 100.0).rounded() / 100.0 }

        return rawEntries.prefix(max(1, limit)).map { entry in
            let proportionalW = (entry.impact / totalImpact) * attributableWatts
            let cpuFloorW = (entry.cpu / 100.0) * 2.5
            let estimatedW = min(attributableWatts, max(cpuFloorW, proportionalW))

            return HighEnergyApp(
                id: entry.app.processIdentifier,
                name: entry.app.localizedName ?? "Unknown",
                bundleIdentifier: entry.app.bundleIdentifier,
                cpuPercent: round1(entry.cpu),
                energyImpactScore: round1(entry.impact),
                estimatedWatts: round2(estimatedW),
                memoryMB: round1(entry.memMB)
            )
        }
    }

    /// Safely terminates a running application by PID (refuses to terminate self or invalid PIDs).
    @discardableResult
    public func terminateApp(pid: Int32) -> Bool {
        guard pid > 0, pid != getpid() else { return false }
        guard let app = NSRunningApplication(processIdentifier: pid) else {
            return false
        }
        return app.terminate()
    }

    private func readRusage(pid: Int32) -> rusage_info_v4? {
        var info = rusage_info_v4()
        let kr: Int32 = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rebound in
                proc_pid_rusage(pid, RUSAGE_INFO_V4, rebound)
            }
        }
        return kr == 0 ? info : nil
    }
}
