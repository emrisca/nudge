import XCTest
@testable import NudgeCore

final class NudgeCoreTests: XCTestCase {

    // MARK: - Helpers

    private struct PolicyTickDecision: Equatable {
        var chargingInhibited: Bool
        var forceDischarge: Bool
        var heatProtectionActive: Bool
        var sailingActive: Bool
        var calibrationPhase: CalibrationPhase
        var topUpActive: Bool
    }

    private func makeSnapshot(
        displayPercentage: Int,
        temperatureCelsius: Double = 30.0,
        isPluggedIn: Bool = true,
        isCharging: Bool = false
    ) -> BatterySnapshot {
        let flow = PowerFlowBreakdown(
            chargerInputWatts: isPluggedIn ? 30.0 : 0.0,
            batteryWatts: isCharging ? 20.0 : (isPluggedIn ? 0.0 : -10.0),
            systemLoadWatts: 10.0,
            socWatts: 4.5,
            displayWatts: 3.5,
            usbAndPeripheralsWatts: 2.0
        )
        return BatterySnapshot(
            rawHardwarePercentage: Double(displayPercentage),
            displayPercentage: displayPercentage,
            temperatureCelsius: temperatureCelsius,
            cycleCount: 42,
            designCapacityMah: 5100,
            maxCapacityMah: 4845,
            currentCapacityMah: Int(4845.0 * Double(displayPercentage) / 100.0),
            voltageVolts: 12.1,
            amperageAmps: isCharging ? 1.6 : 0.0,
            isPluggedIn: isPluggedIn,
            isCharging: isCharging,
            adapterMaxWatts: 67,
            timeRemainingMinutes: 180,
            powerFlow: flow,
            state: isPluggedIn ? (isCharging ? .charging : .paused) : .unplugged,
            architecture: .appleSilicon
        )
    }

    private func evaluateCorePolicy(
        snapshot: BatterySnapshot,
        config: inout BatteryConfig,
        calibration: CalibrationEngine,
        heatProtection: HeatProtectionManager,
        sailing: SailingModeEngine,
        now: Date = Date()
    ) -> PolicyTickDecision {
        if calibration.isActive {
            let phase = calibration.processTick(
                currentPercentage: snapshot.displayPercentage,
                isPluggedIn: snapshot.isPluggedIn
            )
            if phase != .idle {
                let directives = calibration.hardwareDirectives(for: phase)
                return PolicyTickDecision(
                    chargingInhibited: directives.inhibitCharging,
                    forceDischarge: directives.forceDischarge,
                    heatProtectionActive: false,
                    sailingActive: false,
                    calibrationPhase: phase,
                    topUpActive: config.topUpActive
                )
            }
        }

        if config.topUpActive {
            if !snapshot.isPluggedIn {
                config.topUpActive = false
            } else if snapshot.displayPercentage >= 100 {
                return PolicyTickDecision(
                    chargingInhibited: true,
                    forceDischarge: false,
                    heatProtectionActive: false,
                    sailingActive: false,
                    calibrationPhase: .idle,
                    topUpActive: true
                )
            } else {
                return PolicyTickDecision(
                    chargingInhibited: false,
                    forceDischarge: false,
                    heatProtectionActive: false,
                    sailingActive: false,
                    calibrationPhase: .idle,
                    topUpActive: true
                )
            }
        }

        if config.heatProtectionEnabled {
            if heatProtection.evaluateTemperature(snapshot.temperatureCelsius, now: now) {
                return PolicyTickDecision(
                    chargingInhibited: true,
                    forceDischarge: false,
                    heatProtectionActive: true,
                    sailingActive: false,
                    calibrationPhase: .idle,
                    topUpActive: config.topUpActive
                )
            }
        }

        sailing.targetLimit = config.chargeLimit
        sailing.deadbandPercentage = config.sailingDeadband
        sailing.isEnabled = config.sailingModeEnabled
        let chargingInhibited = sailing.evaluateCharging(currentPercentage: snapshot.displayPercentage)
        let sailingActive = sailing.isSailing

        let autoDischarge = config.automaticDischargeEnabled
            && snapshot.isPluggedIn
            && snapshot.displayPercentage > config.chargeLimit
        let manualDischarge = config.manualDischargeActive && snapshot.isPluggedIn
        let forceDischarge = autoDischarge || manualDischarge

        return PolicyTickDecision(
            chargingInhibited: chargingInhibited || forceDischarge,
            forceDischarge: forceDischarge,
            heatProtectionActive: false,
            sailingActive: sailingActive,
            calibrationPhase: .idle,
            topUpActive: config.topUpActive
        )
    }

    // MARK: - 1. Sailing Mode Deadband & Disable Toggle

    func testSailingModeDeadbandAndDisableToggle() {
        let engine = SailingModeEngine(targetLimit: 80, deadbandPercentage: 5, isEnabled: true)
        XCTAssertEqual(engine.lowerBound, 75)

        XCTAssertFalse(engine.evaluateCharging(currentPercentage: 70))
        XCTAssertFalse(engine.isSailing)
        XCTAssertFalse(engine.evaluateCharging(currentPercentage: 77))

        // Enter sailing at ceiling
        XCTAssertTrue(engine.evaluateCharging(currentPercentage: 80))
        XCTAssertTrue(engine.isSailing)

        // Stay paused inside deadband
        XCTAssertTrue(engine.evaluateCharging(currentPercentage: 79))
        XCTAssertTrue(engine.evaluateCharging(currentPercentage: 78))
        XCTAssertTrue(engine.evaluateCharging(currentPercentage: 76))

        // Resume at lower bound
        XCTAssertFalse(engine.evaluateCharging(currentPercentage: 75))
        XCTAssertFalse(engine.isSailing)

        // Climb inside deadband keeps charging until 80%
        XCTAssertFalse(engine.evaluateCharging(currentPercentage: 77))

        // Disable toggle
        _ = engine.evaluateCharging(currentPercentage: 80)
        XCTAssertTrue(engine.isSailing)
        engine.isEnabled = false
        XCTAssertFalse(engine.isSailing)
        XCTAssertTrue(engine.evaluateCharging(currentPercentage: 80))
        XCTAssertFalse(engine.evaluateCharging(currentPercentage: 79))
        XCTAssertFalse(engine.isSailing)
    }

    // MARK: - 2. Heat Protection 5-Minute (300s) Hysteresis

    func testHeatProtectionHysteresis() {
        let heat = HeatProtectionManager(thresholdCelsius: 35.0, hysteresisCooldownSeconds: 300.0)
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)

        XCTAssertFalse(heat.evaluateTemperature(34.9, now: t0))
        XCTAssertFalse(heat.isActive)
        XCTAssertEqual(heat.remainingCooldownSeconds(now: t0), 0.0)

        // Trigger >= 35°C
        XCTAssertTrue(heat.evaluateTemperature(35.0, now: t0))
        XCTAssertTrue(heat.isActive)

        // Stay active during cooldown even below 35°C
        let t120 = t0.addingTimeInterval(120)
        XCTAssertTrue(heat.evaluateTemperature(32.0, now: t120))
        XCTAssertEqual(heat.remainingCooldownSeconds(now: t120), 180.0, accuracy: 0.001)
        XCTAssertTrue(heat.evaluateTemperature(29.0, now: t0.addingTimeInterval(299)))
        XCTAssertTrue(heat.isActive)

        // Release after 300s
        let t300 = t0.addingTimeInterval(300)
        XCTAssertFalse(heat.evaluateTemperature(33.0, now: t300))
        XCTAssertFalse(heat.isActive)
        XCTAssertEqual(heat.remainingCooldownSeconds(now: t300), 0.0)

        // Re-trigger on subsequent overheat
        XCTAssertTrue(heat.evaluateTemperature(37.5, now: t0.addingTimeInterval(310)))
        XCTAssertTrue(heat.isActive)
    }

    // MARK: - 3. Calibration Mode 4-Phase Transitions & Heat Protection Bypass

    func testCalibrationModeTransitionsAndHeatBypass() {
        let cal = CalibrationEngine(userTargetLimit: 80)
        XCTAssertEqual(cal.currentPhase, .idle)
        XCTAssertFalse(cal.bypassesHeatProtection)

        cal.startCalibration()
        XCTAssertEqual(cal.currentPhase, .chargeToFull)
        XCTAssertTrue(cal.bypassesHeatProtection)

        XCTAssertEqual(cal.processTick(currentPercentage: 95, isPluggedIn: true), .chargeToFull)
        XCTAssertEqual(cal.processTick(currentPercentage: 100, isPluggedIn: true), .dischargeToLow)

        let phase2 = cal.hardwareDirectives(for: .dischargeToLow)
        XCTAssertTrue(phase2.inhibitCharging)
        XCTAssertTrue(phase2.forceDischarge)

        XCTAssertEqual(cal.processTick(currentPercentage: 30, isPluggedIn: true), .dischargeToLow)
        XCTAssertEqual(cal.processTick(currentPercentage: 10, isPluggedIn: true), .rechargeToFull)

        let phase3 = cal.hardwareDirectives(for: .rechargeToFull)
        XCTAssertFalse(phase3.inhibitCharging)
        XCTAssertFalse(phase3.forceDischarge)

        XCTAssertEqual(cal.processTick(currentPercentage: 90, isPluggedIn: true), .rechargeToFull)
        XCTAssertEqual(cal.processTick(currentPercentage: 100, isPluggedIn: true), .returnToTargetLimit)

        XCTAssertEqual(cal.processTick(currentPercentage: 82, isPluggedIn: true), .returnToTargetLimit)
        XCTAssertEqual(cal.processTick(currentPercentage: 80, isPluggedIn: true), .idle)
        XCTAssertFalse(cal.bypassesHeatProtection)

        // Heat protection bypass during calibration
        var config = BatteryConfig()
        config.heatProtectionEnabled = true
        config.heatThresholdCelsius = 35.0
        let heat = HeatProtectionManager(thresholdCelsius: 35.0, hysteresisCooldownSeconds: 300.0)
        let sailing = SailingModeEngine(targetLimit: 80, deadbandPercentage: 5)
        let hotSnap = makeSnapshot(displayPercentage: 88, temperatureCelsius: 39.5, isPluggedIn: true, isCharging: true)

        cal.startCalibration()
        let duringCal = evaluateCorePolicy(snapshot: hotSnap, config: &config, calibration: cal, heatProtection: heat, sailing: sailing)
        XCTAssertEqual(duringCal.calibrationPhase, .chargeToFull)
        XCTAssertFalse(duringCal.chargingInhibited)
        XCTAssertFalse(duringCal.heatProtectionActive)

        cal.cancelCalibration()
        XCTAssertEqual(cal.currentPhase, .idle)
        let afterCal = evaluateCorePolicy(snapshot: hotSnap, config: &config, calibration: cal, heatProtection: heat, sailing: sailing)
        XCTAssertTrue(afterCal.heatProtectionActive)
        XCTAssertTrue(afterCal.chargingInhibited)
    }

    // MARK: - 4. Automatic Discharge Trigger

    func testAutomaticDischargeTrigger() {
        var config = BatteryConfig()
        config.chargeLimit = 80
        config.automaticDischargeEnabled = true
        let cal = CalibrationEngine(userTargetLimit: 80)
        let heat = HeatProtectionManager()
        let sailing = SailingModeEngine(targetLimit: 80, deadbandPercentage: 5)

        let overLimit = evaluateCorePolicy(snapshot: makeSnapshot(displayPercentage: 92), config: &config, calibration: cal, heatProtection: heat, sailing: sailing)
        XCTAssertTrue(overLimit.forceDischarge)
        XCTAssertTrue(overLimit.chargingInhibited)

        let atLimit = evaluateCorePolicy(snapshot: makeSnapshot(displayPercentage: 80), config: &config, calibration: cal, heatProtection: heat, sailing: sailing)
        XCTAssertFalse(atLimit.forceDischarge)

        config.automaticDischargeEnabled = false
        let disabled = evaluateCorePolicy(snapshot: makeSnapshot(displayPercentage: 95), config: &config, calibration: cal, heatProtection: heat, sailing: sailing)
        XCTAssertFalse(disabled.forceDischarge)
    }

    // MARK: - 5. Top Up 100% Override & Auto-Revert on Physical Unplug

    func testTopUpOverrideAndUnplugRevert() {
        var config = BatteryConfig()
        config.chargeLimit = 80
        config.topUpActive = true
        let cal = CalibrationEngine(userTargetLimit: 80)
        let heat = HeatProtectionManager()
        let sailing = SailingModeEngine(targetLimit: 80, deadbandPercentage: 5)

        let toppingUp = evaluateCorePolicy(snapshot: makeSnapshot(displayPercentage: 88, isPluggedIn: true, isCharging: true), config: &config, calibration: cal, heatProtection: heat, sailing: sailing)
        XCTAssertFalse(toppingUp.chargingInhibited)
        XCTAssertFalse(toppingUp.forceDischarge)
        XCTAssertTrue(config.topUpActive)

        let full = evaluateCorePolicy(snapshot: makeSnapshot(displayPercentage: 100, isPluggedIn: true), config: &config, calibration: cal, heatProtection: heat, sailing: sailing)
        XCTAssertTrue(full.chargingInhibited)

        let unplugged = evaluateCorePolicy(snapshot: makeSnapshot(displayPercentage: 98, isPluggedIn: false), config: &config, calibration: cal, heatProtection: heat, sailing: sailing)
        XCTAssertFalse(config.topUpActive)
        XCTAssertFalse(unplugged.topUpActive)
    }

    // MARK: - 6. SchedulerEngine Cron Matching & Missed Task Catch-Up

    func testSchedulerEngineCronMatchingAndMissedCatchUp() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("nudge-xctest-schedules-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let scheduler = SchedulerEngine(storageURL: tempURL, calendar: calendar)

        let monday0930 = calendar.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 9, minute: 30, second: 10))!
        let monday1100 = calendar.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 11, minute: 0, second: 0))!
        let tuesday0930 = calendar.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: 9, minute: 30, second: 0))!

        let weekdayTask = ScheduledTask(
            name: "Monday Top Up",
            action: .startTopUp,
            targetValue: 100,
            hour: 9,
            minute: 30,
            weekdays: [2],
            isEnabled: true,
            catchUpIfMissed: true,
            lastExecutedAt: nil
        )
        let noCatchUpTask = ScheduledTask(
            name: "Skip Missed Limit",
            action: .setChargeLimit,
            targetValue: 70,
            hour: 9,
            minute: 15,
            weekdays: [2],
            isEnabled: true,
            catchUpIfMissed: false,
            lastExecutedAt: nil
        )
        scheduler.addTask(weekdayTask)
        scheduler.addTask(noCatchUpTask)

        let onTime = scheduler.evaluateDueTasks(now: monday0930, includeMissed: false) { _ in }
        XCTAssertEqual(onTime.map(\.name), ["Monday Top Up"])

        let duplicate = scheduler.evaluateDueTasks(now: monday0930.addingTimeInterval(15), includeMissed: false) { _ in }
        XCTAssertTrue(duplicate.isEmpty)

        let expectedNextMonday = calendar.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 9, minute: 30, second: 0))!
        XCTAssertEqual(scheduler.nextScheduledDate(for: weekdayTask, after: tuesday0930), expectedNextMonday)

        // Fresh scheduler simulating wake/relaunch catch-up at 11:00
        let missedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("nudge-xctest-missed-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: missedURL) }

        let wakeScheduler = SchedulerEngine(storageURL: missedURL, calendar: calendar)
        wakeScheduler.addTask(weekdayTask)
        wakeScheduler.addTask(noCatchUpTask)

        let missed = wakeScheduler.evaluateDueTasks(now: monday1100, includeMissed: true) { _ in }
        XCTAssertEqual(missed.map(\.name), ["Monday Top Up"])
    }

    // MARK: - 7. SleepControlState & SleepController Fallback Triggers

    func testSleepControlFallbackTriggers() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let controller = SleepController()
        defer { _ = controller.disableKeepAwake() }

        // Unplug fallback
        _ = controller.enableTimedKeepAwake(minutes: 60, fallbackBatteryPercent: 20, reenableOnUnplug: true, now: now)
        let plugged = controller.evaluate(snapshot: makeSnapshot(displayPercentage: 65, isPluggedIn: true), chargeLimit: 80, now: now)
        XCTAssertTrue(plugged.state.keepAwakeActive)

        let unplugged = controller.evaluate(snapshot: makeSnapshot(displayPercentage: 65, isPluggedIn: false), chargeLimit: 80, now: now)
        XCTAssertFalse(unplugged.state.keepAwakeActive)
        XCTAssertFalse(unplugged.assertionActive)

        // Low-battery <= 20% fallback
        _ = controller.enableTimedKeepAwake(minutes: 60, fallbackBatteryPercent: 20, reenableOnUnplug: false, now: now)
        let healthy = controller.evaluate(snapshot: makeSnapshot(displayPercentage: 35, isPluggedIn: false), chargeLimit: 80, now: now)
        XCTAssertTrue(healthy.state.keepAwakeActive)

        let low = controller.evaluate(snapshot: makeSnapshot(displayPercentage: 20, isPluggedIn: false), chargeLimit: 80, now: now)
        XCTAssertFalse(low.state.keepAwakeActive)
        XCTAssertFalse(low.assertionActive)

        // Timer expiry fallback
        _ = controller.enableTimedKeepAwake(minutes: 30, fallbackBatteryPercent: 20, reenableOnUnplug: true, now: now)
        let expired = controller.evaluate(snapshot: makeSnapshot(displayPercentage: 70, isPluggedIn: true), chargeLimit: 80, now: now.addingTimeInterval(1801))
        XCTAssertFalse(expired.state.keepAwakeActive)
        XCTAssertFalse(expired.assertionActive)

        // Disable sleep until charge limit
        _ = controller.configure(disableSleepUntilChargeLimit: true, fallbackBatteryPercent: 20, reenableOnUnplug: true)
        let belowLimit = controller.evaluate(snapshot: makeSnapshot(displayPercentage: 70, isPluggedIn: true), chargeLimit: 80, now: now)
        XCTAssertTrue(belowLimit.assertionActive)

        let atLimit = controller.evaluate(snapshot: makeSnapshot(displayPercentage: 80, isPluggedIn: true), chargeLimit: 80, now: now)
        XCTAssertFalse(atLimit.assertionActive)
    }

    // MARK: - 8. BatteryConfig JSON Encode/Decode Round-Trip

    func testBatteryConfigJSONRoundTrip() throws {
        var config = BatteryConfig()
        config.chargeLimit = 75
        config.sailingModeEnabled = true
        config.sailingDeadband = 8
        config.heatProtectionEnabled = true
        config.heatThresholdCelsius = 36.5
        config.automaticDischargeEnabled = true
        config.topUpActive = true
        config.disableSleepUntilChargeLimit = true
        config.keepAwakeFallbackPercent = 25
        config.magSafeLEDMode = .orange
        config.syncMagSafeLEDWithState = false
        config.preferredPowerMode = .lowPower
        config.menuBarComponents = [.liveIcon, .hardwarePercentage, .temperature, .powerFlow, .maxCapacity]
        config.popoverWidgetOrder = [
            .powerFlow,
            .chargeControl,
            .historicalCharts,
            .highEnergyApps,
            .batterySpecs,
            .sleepAndPowerMode,
            .schedule,
            .calibrationAndLED
        ]
        config.hiddenPopoverWidgets = [.calibrationAndLED]
        config.appearancePreference = "dark"

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(BatteryConfig.self, from: data)

        XCTAssertEqual(decoded, config)
        XCTAssertEqual(decoded.menuBarComponents, config.menuBarComponents)
        XCTAssertEqual(decoded.popoverWidgetOrder, config.popoverWidgetOrder)
        XCTAssertEqual(decoded.hiddenPopoverWidgets, [.calibrationAndLED])
    }

    // MARK: - 9. Live IOKitPowerReader Sanity Check

    func testLiveIOKitPowerReaderSanity() {
        let snapshot = IOKitPowerReader.shared.readCurrentSnapshot()

        XCTAssertTrue((0...100).contains(snapshot.displayPercentage))
        XCTAssertGreaterThanOrEqual(snapshot.rawHardwarePercentage, 0.0)
        XCTAssertLessThanOrEqual(snapshot.rawHardwarePercentage, 100.0)
        XCTAssertGreaterThan(snapshot.temperatureCelsius, -10.0)
        XCTAssertLessThan(snapshot.temperatureCelsius, 110.0)
        XCTAssertGreaterThanOrEqual(snapshot.cycleCount, 0)
        XCTAssertGreaterThan(snapshot.maxCapacityMah, 0)
        XCTAssertGreaterThan(snapshot.healthPercentage, 0.0)
        XCTAssertLessThanOrEqual(snapshot.healthPercentage, 100.0)
        XCTAssertFalse(snapshot.powerFlow.chargerInputWatts.isNaN)
        XCTAssertFalse(snapshot.powerFlow.batteryWatts.isNaN)
        XCTAssertFalse(snapshot.powerFlow.systemLoadWatts.isNaN)
    }

    // MARK: - 10. GitHub Releases Updater SemVer & Checksums

    func testUpdaterSemVerAndChecksumParsing() throws {
        let v100 = try XCTUnwrap(SemanticVersion(parsing: "v1.0.0"))
        let v110Beta = try XCTUnwrap(SemanticVersion(parsing: "v1.1.0-beta.1"))
        let v110 = try XCTUnwrap(SemanticVersion(parsing: "1.1.0"))
        let v1100 = try XCTUnwrap(SemanticVersion(parsing: "v1.10.0"))

        XCTAssertLessThan(v100, v110Beta)
        XCTAssertLessThan(v110Beta, v110)
        XCTAssertLessThan(v110, v1100)
        XCTAssertNil(SemanticVersion(parsing: "invalid"))

        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("nudge-xctest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempFile) }
        try Data("nudge-checksum".utf8).write(to: tempFile)
        let hash = try ChecksumVerifier.sha256Hex(forFileAt: tempFile)
        let parsed = ChecksumVerifier.parseChecksums("\(hash)  Nudge-1.1.0-macOS-arm64.zip\n")
        XCTAssertEqual(parsed["Nudge-1.1.0-macOS-arm64.zip"], hash)
    }

    // MARK: - 11. Launch at Login Plist & Registration

    @MainActor
    func testLaunchAtLoginManagerToggle() {
        let tempAgents = FileManager.default.temporaryDirectory
            .appendingPathComponent("nudge-xctest-agents-\(UUID().uuidString)", isDirectory: true)
        let suiteName = "com.emrisca.nudge.xctest.launch.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            try? FileManager.default.removeItem(at: tempAgents)
            defaults.removePersistentDomain(forName: suiteName)
        }

        let manager = LaunchAtLoginManager(
            defaults: defaults,
            launchAgentsDirectory: tempAgents,
            bundleURLProvider: { URL(fileURLWithPath: "/Applications/Nudge.app") },
            useSMAppService: false
        )

        let onStatus = manager.setEnabled(true)
        XCTAssertTrue(onStatus.isEnabled)
        XCTAssertEqual(onStatus.backend, .launchAgent)
        XCTAssertTrue(FileManager.default.fileExists(atPath: manager.launchAgentPlistURL.path))

        let offStatus = manager.setEnabled(false)
        XCTAssertFalse(offStatus.isEnabled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: manager.launchAgentPlistURL.path))
    }
}
