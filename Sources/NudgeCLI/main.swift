import Foundation
import NudgeCore

// MARK: - CLI Entry Point

private struct NudgeCLI {
    static let version = NudgeVersion.current

    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let subcommand = args.first?.lowercased() else {
            runStatus(json: false)
            return
        }

        let rest = Array(args.dropFirst())

        switch subcommand {
        case "status":
            let json = rest.contains("--json") || rest.contains("-j")
            runStatus(json: json)

        case "limit":
            runLimit(args: rest)

        case "discharge":
            runDischarge(args: rest)

        case "topup":
            runTopUp(args: rest)

        case "calibrate":
            runCalibrate(args: rest)

        case "sailing":
            runSailing(args: rest)

        case "heat":
            runHeat(args: rest)

        case "magsafe":
            runMagSafe(args: rest)

        case "powermode":
            runPowerMode(args: rest)

        case "apps":
            let json = rest.contains("--json") || rest.contains("-j")
            runApps(json: json)

        case "keepawake":
            runKeepAwake(args: rest)

        case "update":
            runUpdate(args: rest)

        case "help", "--help", "-h":
            printHelp()

        case "version", "--version", "-v":
            print("nudge-cli \(version)")

        default:
            fail("Unknown command '\(subcommand)'. Run 'nudge-cli help' for usage.")
        }
    }

    // MARK: - Subcommands

    private static func runStatus(json: Bool) {
        let manager = BatteryManager.shared
        let tick = manager.tick()

        if json {
            print(manager.exportStateSummaryJSON())
            return
        }

        let snap = tick.snapshot
        let cfg = manager.config
        let pf = snap.powerFlow

        print("Nudge Battery Status (v\(version))")
        print("==================================================")
        print("Architecture:       \(snap.architecture.rawValue)")
        print("State:              \(snap.state.rawValue.capitalized) (\(snap.isPluggedIn ? "AC Plugged In" : "On Battery"))")
        print("Display Charge:     \(snap.displayPercentage)% (Raw Hardware: \(String(format: "%.1f", snap.rawHardwarePercentage))%)")
        print("Battery Health:     \(String(format: "%.1f", snap.healthPercentage))% (\(snap.currentCapacityMah)/\(snap.maxCapacityMah) mAh, Design \(snap.designCapacityMah) mAh)")
        print("Cycle Count:        \(snap.cycleCount)")
        print("Temperature:        \(String(format: "%.1f", snap.temperatureCelsius))°C")
        print("Electrical:         \(String(format: "%.2f", snap.voltageVolts))V | \(String(format: "%.2f", snap.amperageAmps))A | Adapter Max \(snap.adapterMaxWatts)W")
        if let mins = snap.timeRemainingMinutes, mins > 0 {
            let h = mins / 60
            let m = mins % 60
            print("Time Remaining:     \(h)h \(m)m")
        }
        print("--------------------------------------------------")
        print("Power Flow:")
        print("  Charger Input:    \(String(format: "%.1f", pf.chargerInputWatts))W")
        print("  Battery Flow:     \(String(format: "%+.1f", pf.batteryWatts))W")
        print("  System Load:      \(String(format: "%.1f", pf.systemLoadWatts))W (SoC \(String(format: "%.1f", pf.socWatts))W | Display \(String(format: "%.1f", pf.displayWatts))W | USB \(String(format: "%.1f", pf.usbAndPeripheralsWatts))W)")
        print("--------------------------------------------------")
        print("Controls & Safeguards:")
        print("  Charge Limit:     \(cfg.chargeLimit)% (Inhibit: \(tick.chargingInhibited ? "ON" : "OFF") | Force Discharge: \(tick.forceDischarge ? "ON" : "OFF"))")
        print("  Top Up (100%):    \(cfg.topUpActive ? "ACTIVE" : "OFF")")
        print("  Sailing Mode:     \(cfg.sailingModeEnabled ? "ON" : "OFF") (Deadband: \(cfg.sailingDeadband)%, Active: \(tick.sailingActive ? "YES" : "NO"))")
        print("  Heat Protection:  \(cfg.heatProtectionEnabled ? "ON" : "OFF") (Threshold: \(String(format: "%.1f", cfg.heatThresholdCelsius))°C, Tripped: \(tick.heatProtectionActive ? "YES" : "NO"))")
        print("  Calibration:      \(tick.calibrationPhase.rawValue)")
        print("  MagSafe LED:      \(tick.activeMagSafeLED.rawValue) (Configured: \(cfg.magSafeLEDMode.rawValue))")
        print("  Power Mode:       \(cfg.preferredPowerMode.rawValue)")
        print("  Keep Awake:       \(tick.sleepAssertionActive ? "ACTIVE" : "OFF")")
        print("==================================================")
    }

    private static func runLimit(args: [String]) {
        guard let raw = args.first, let value = Int(raw), (20...100).contains(value) else {
            fail("Usage: nudge-cli limit <20-100>")
        }

        let manager = BatteryManager.shared
        manager.setChargeLimit(value)
        let tick = manager.tick()
        print("Charge limit set to \(manager.config.chargeLimit)% (current charge: \(tick.snapshot.displayPercentage)%, inhibit: \(tick.chargingInhibited ? "ON" : "OFF")).")
    }

    private static func runDischarge(args: [String]) {
        guard let flag = parseOnOff(args.first) else {
            fail("Usage: nudge-cli discharge <on|off>")
        }

        let manager = BatteryManager.shared
        manager.setManualDischarge(flag)
        let tick = manager.tick()
        print("Manual discharge \(flag ? "enabled" : "disabled") (forceDischarge: \(tick.forceDischarge ? "ON" : "OFF")).")
    }

    private static func runTopUp(args: [String]) {
        guard let flag = parseOnOff(args.first) else {
            fail("Usage: nudge-cli topup <on|off>")
        }

        let manager = BatteryManager.shared
        manager.setTopUp(flag)
        _ = manager.tick()
        if flag {
            print("Top Up enabled. Battery will charge to 100% until unplugged or disabled.")
        } else {
            print("Top Up disabled. Charge limit restored to \(manager.config.chargeLimit)%.")
        }
    }

    private static func runCalibrate(args: [String]) {
        guard let action = args.first?.lowercased() else {
            fail("Usage: nudge-cli calibrate <start|stop>")
        }

        let manager = BatteryManager.shared
        switch action {
        case "start":
            manager.startCalibration()
            let tick = manager.tick()
            print("Calibration started (phase: \(tick.calibrationPhase.rawValue)).")
        case "stop", "cancel":
            manager.cancelCalibration()
            let tick = manager.tick()
            print("Calibration stopped (phase: \(tick.calibrationPhase.rawValue)).")
        default:
            fail("Usage: nudge-cli calibrate <start|stop>")
        }
    }

    private static func runSailing(args: [String]) {
        guard let enabled = parseOnOff(args.first) else {
            fail("Usage: nudge-cli sailing <on|off> [deadband]")
        }

        var deadbandOverride: Int?
        if args.count >= 2 {
            guard let parsed = Int(args[1]), (1...20).contains(parsed) else {
                fail("Deadband must be an integer between 1 and 20.")
            }
            deadbandOverride = parsed
        }

        let manager = BatteryManager.shared
        manager.updateConfig { config in
            config.sailingModeEnabled = enabled
            if let deadbandOverride {
                config.sailingDeadband = deadbandOverride
            }
        }
        _ = manager.tick()
        print("Sailing Mode \(enabled ? "enabled" : "disabled") (deadband: \(manager.config.sailingDeadband)%).")
    }

    private static func runHeat(args: [String]) {
        guard let enabled = parseOnOff(args.first) else {
            fail("Usage: nudge-cli heat <on|off> [celsius]")
        }

        var thresholdOverride: Double?
        if args.count >= 2 {
            guard let parsed = Double(args[1]), (25.0...50.0).contains(parsed) else {
                fail("Heat protection threshold must be between 25.0 and 50.0 °C.")
            }
            thresholdOverride = parsed
        }

        let manager = BatteryManager.shared
        manager.updateConfig { config in
            config.heatProtectionEnabled = enabled
            if let thresholdOverride {
                config.heatThresholdCelsius = thresholdOverride
            }
        }
        _ = manager.tick()
        print(String(format: "Heat Protection %@ (threshold: %.1f°C).", enabled ? "enabled" : "disabled", manager.config.heatThresholdCelsius))
    }

    private static func runMagSafe(args: [String]) {
        guard let raw = args.first?.lowercased() else {
            fail("Usage: nudge-cli magsafe <system|green|orange|blink|off>")
        }

        let mode: MagSafeLEDState
        switch raw {
        case "system", "default":
            mode = .systemDefault
        case "green":
            mode = .green
        case "orange", "amber":
            mode = .orange
        case "blink", "blinking", "blinkingorange":
            mode = .blinkingOrange
        case "off":
            mode = .off
        default:
            fail("Usage: nudge-cli magsafe <system|green|orange|blink|off>")
        }

        BatteryManager.shared.setMagSafeLED(mode)
        print("MagSafe LED set to \(mode.rawValue).")
    }

    private static func runPowerMode(args: [String]) {
        guard let raw = args.first?.lowercased() else {
            fail("Usage: nudge-cli powermode <low|normal|high>")
        }

        let mode: PowerMode
        switch raw {
        case "low", "lowpower":
            mode = .lowPower
        case "normal", "auto", "automatic":
            mode = .normal
        case "high", "highpower":
            mode = .highPower
        default:
            fail("Usage: nudge-cli powermode <low|normal|high>")
        }

        let applied = BatteryManager.shared.setPowerMode(mode)
        if applied {
            print("Power Mode set to \(mode.rawValue).")
        } else {
            print("Power Mode preference updated to \(mode.rawValue) (note: pmset may require administrator privileges).")
        }
    }

    private static func runKeepAwake(args: [String]) {
        guard let raw = args.first?.lowercased() else {
            fail("Usage: nudge-cli keepawake <minutes|on|off>")
        }

        let manager = BatteryManager.shared
        if raw == "off" || raw == "stop" || raw == "0" {
            manager.disableKeepAwake()
            print("Keep Awake disabled.")
            return
        }

        if raw == "on" || raw == "indefinite" {
            let cfg = manager.config
            manager.enableTimedKeepAwake(
                minutes: nil,
                fallbackBatteryPercent: cfg.keepAwakeFallbackPercent,
                reenableOnUnplug: cfg.keepAwakeReenableOnUnplug
            )
            print("Keep Awake enabled indefinitely (fallback at \(cfg.keepAwakeFallbackPercent)%).")
            return
        }

        guard let mins = Int(raw), mins > 0 else {
            fail("Usage: nudge-cli keepawake <minutes|on|off>")
        }

        let cfg = manager.config
        manager.enableTimedKeepAwake(
            minutes: mins,
            fallbackBatteryPercent: cfg.keepAwakeFallbackPercent,
            reenableOnUnplug: cfg.keepAwakeReenableOnUnplug
        )
        print("Keep Awake enabled for \(mins) minutes (fallback at \(cfg.keepAwakeFallbackPercent)%).")
    }

    private static func runApps(json: Bool) {
        let manager = BatteryManager.shared
        let tick = manager.tick()
        let apps = manager.energyMonitor.sampleHighEnergyApps(
            limit: 12,
            systemLoadWatts: tick.snapshot.powerFlow.systemLoadWatts
        )

        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(apps), let str = String(data: data, encoding: .utf8) {
                print(str)
            } else {
                print("[]")
            }
            return
        }

        print("Apps Using Significant Energy")
        print("==================================================================")
        if apps.isEmpty {
            print("No high-energy applications detected right now.")
            print("==================================================================")
            return
        }

        let header = [
            padLeft("APP", width: 24),
            padRight("PID", width: 7),
            padRight("CPU %", width: 8),
            padRight("ENERGY", width: 9),
            padRight("EST W", width: 9),
            padRight("MEM", width: 8)
        ].joined(separator: " ")
        print(header)
        print("------------------------------------------------------------------")

        for app in apps {
            let name = app.name.count > 24 ? String(app.name.prefix(23)) + "…" : app.name
            let row = [
                padLeft(name, width: 24),
                padRight("\(app.id)", width: 7),
                padRight(String(format: "%.1f%%", app.cpuPercent), width: 8),
                padRight(String(format: "%.1f", app.energyImpactScore), width: 9),
                padRight(String(format: "%.2fW", app.estimatedWatts), width: 9),
                padRight(String(format: "%.0fM", app.memoryMB), width: 8)
            ].joined(separator: " ")
            print(row)
        }
        print("==================================================================")
    }

    private static func runUpdate(args: [String]) {
        let includePrereleases = args.contains("--prerelease") || args.contains("--pre")
        let json = args.contains("--json") || args.contains("-j")

        var finished = false
        var exitCode: Int32 = 0

        Task { @MainActor in
            let updater = UpdateManager.shared
            updater.includePrereleases = includePrereleases
            let result = await updater.checkForUpdates(userInitiated: true)

            switch result {
            case .updateAvailable(let release):
                if json {
                    let payload: [String: Any] = [
                        "currentVersion": updater.currentVersionString,
                        "latestVersion": release.tagName,
                        "updateAvailable": true,
                        "releaseURL": release.htmlURL.absoluteString,
                        "asset": release.preferredAsset()?.name ?? ""
                    ]
                    if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]),
                       let str = String(data: data, encoding: .utf8) {
                        print(str)
                    }
                } else {
                    print("Update available: Nudge \(release.displayVersion) (installed: v\(updater.currentVersionString))")
                    print("Release URL: \(release.htmlURL.absoluteString)")
                    if let asset = release.preferredAsset() {
                        print("Asset:       \(asset.name)")
                    }
                    print("Open Nudge Settings -> Software Updates to install & relaunch.")
                }

            case .upToDate:
                if json {
                    let payload: [String: Any] = [
                        "currentVersion": updater.currentVersionString,
                        "latestVersion": updater.latestKnownRelease?.tagName ?? "v\(updater.currentVersionString)",
                        "updateAvailable": false
                    ]
                    if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]),
                       let str = String(data: data, encoding: .utf8) {
                        print(str)
                    }
                } else {
                    print("Nudge v\(updater.currentVersionString) is up to date (GitHub: \(NudgeVersion.repositoryOwner)/\(NudgeVersion.repositoryName)).")
                }

            case .failed(let message):
                fputs("Error checking updates: \(message)\n", stderr)
                exitCode = 1

            default:
                break
            }

            finished = true
        }

        while !finished {
            RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        }
        if exitCode != 0 {
            exit(exitCode)
        }
    }

    // MARK: - Utilities

    private static func padLeft(_ text: String, width: Int) -> String {
        if text.count >= width { return text }
        return text + String(repeating: " ", count: width - text.count)
    }

    private static func padRight(_ text: String, width: Int) -> String {
        if text.count >= width { return text }
        return String(repeating: " ", count: width - text.count) + text
    }

    private static func parseOnOff(_ value: String?) -> Bool? {
        switch value?.lowercased() {
        case "on", "true", "1", "enable", "enabled", "start":
            return true
        case "off", "false", "0", "disable", "disabled", "stop":
            return false
        default:
            return nil
        }
    }

    private static func printHelp() {
        print("""
        Nudge CLI v\(version) — macOS Battery & Power Management

        Usage:
          nudge-cli <command> [arguments]

        Commands:
          status [--json]                     Show live battery status, power flow, and active safeguards
          limit <20-100>                      Set maximum battery charge limit percentage
          discharge <on|off>                  Start or stop forced battery discharge while plugged in
          topup <on|off>                      Temporarily charge to 100% until unplugged
          calibrate <start|stop>              Start or cancel 4-phase battery calibration
          sailing <on|off> [deadband]         Toggle Sailing Mode hysteresis (deadband 1-20%)
          heat <on|off> [celsius]             Toggle Heat Protection (threshold 25.0-50.0°C)
          magsafe <system|green|orange|blink|off>
                                              Set MagSafe charger LED mode
          powermode <low|normal|high>         Switch macOS Power Mode
          apps [--json]                       List apps currently using significant energy
          keepawake <minutes|on|off>          Prevent system sleep for a duration or disable
          update [--prerelease] [--json]      Check GitHub Releases for a newer version of Nudge
          help                                Show this help text
        """)
    }

    private static func fail(_ message: String) -> Never {
        fputs("Error: \(message)\n", stderr)
        exit(EXIT_FAILURE)
    }
}

NudgeCLI.main()
