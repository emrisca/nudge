import AppIntents
import Foundation
import NudgeCore
import NudgeIntents

// MARK: - Lightweight Assertion Harness (CommandLineTools-Compatible)

private struct TestOutcome {
    let name: String
    let passed: Bool
    let details: String
}

private var outcomes: [TestOutcome] = []

private struct TestFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String, file: String = #fileID, line: Int = #line) throws {
    if !condition() {
        throw TestFailure(message: "\(message) (\(file):\(line))")
    }
}

private func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String, file: String = #fileID, line: Int = #line) throws {
    if actual != expected {
        throw TestFailure(message: "\(message) — expected \(expected), got \(actual) (\(file):\(line))")
    }
}

private func runTest(_ name: String, _ body: () throws -> Void) {
    do {
        try body()
        outcomes.append(TestOutcome(name: name, passed: true, details: "OK"))
        print("[PASS] \(name)")
    } catch {
        outcomes.append(TestOutcome(name: name, passed: false, details: "\(error)"))
        print("[FAIL] \(name): \(error)")
    }
}

// MARK: - Deterministic Helpers

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

/// Evaluates NudgeCore's engine priority pipeline deterministically against an injected snapshot.
private func evaluateCorePolicy(
    snapshot: BatterySnapshot,
    config: inout BatteryConfig,
    calibration: CalibrationEngine,
    heatProtection: HeatProtectionManager,
    sailing: SailingModeEngine,
    now: Date = Date()
) -> PolicyTickDecision {
    // 1. Calibration Mode (explicitly bypasses Heat Protection & Charge Limiter)
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

    // 2. Top Up 100% Override & automatic revert on physical unplug
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

    // 3. Heat Protection (5-minute hysteresis)
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

    // 4. Sailing Mode / Charge Limiter
    sailing.targetLimit = config.chargeLimit
    sailing.deadbandPercentage = config.sailingDeadband
    sailing.isEnabled = config.sailingModeEnabled
    let chargingInhibited = sailing.evaluateCharging(currentPercentage: snapshot.displayPercentage)
    let sailingActive = sailing.isSailing

    // 5. Automatic & Manual Discharge
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

// MARK: - Test Suites

print("============================================================")
print("Nudge Standalone Verification Suite (NudgeTestRunner)")
print("============================================================")

// 1. Sailing Mode Deadband & Disable Toggle
runTest("1. Sailing Mode Deadband & Disable Toggle") {
    let engine = SailingModeEngine(targetLimit: 80, deadbandPercentage: 5, isEnabled: true) // Range: 75...80
    try expectEqual(engine.lowerBound, 75, "Lower bound must be targetLimit - deadbandPercentage (75)")

    // Below deadband -> charge allowed
    try expectEqual(engine.evaluateCharging(currentPercentage: 70), false, "Below lower bound should charge")
    try expectEqual(engine.isSailing, false, "isSailing must be false below lower bound")

    // Climbing inside deadband before ceiling -> keep charging
    try expectEqual(engine.evaluateCharging(currentPercentage: 77), false, "Climbing inside deadband should keep charging")

    // Enter sailing at ceiling (80%)
    try expectEqual(engine.evaluateCharging(currentPercentage: 80), true, "Ceiling 80% must enter sailing mode")
    try expectEqual(engine.isSailing, true, "isSailing must be true at ceiling")

    // Stay paused inside deadband (79%, 78%, 76%)
    try expectEqual(engine.evaluateCharging(currentPercentage: 79), true, "79% inside deadband must stay paused")
    try expectEqual(engine.evaluateCharging(currentPercentage: 78), true, "78% inside deadband must stay paused")
    try expectEqual(engine.evaluateCharging(currentPercentage: 76), true, "76% inside deadband must stay paused")

    // Resume at lower bound (75%)
    try expectEqual(engine.evaluateCharging(currentPercentage: 75), false, "75% lower bound must resume charging")
    try expectEqual(engine.isSailing, false, "isSailing must clear at lower bound")

    // Climb inside deadband stays charging until 80%
    try expectEqual(engine.evaluateCharging(currentPercentage: 77), false, "77% after resume should continue charging")

    // Disable toggle clears sailing and uses direct ceiling check
    _ = engine.evaluateCharging(currentPercentage: 80)
    try expectEqual(engine.isSailing, true, "Re-entered sailing at 80%")
    engine.isEnabled = false
    try expectEqual(engine.isSailing, false, "Disabling SailingModeEngine must clear isSailing")
    try expectEqual(engine.evaluateCharging(currentPercentage: 80), true, "Disabled sailing still inhibits at 80%")
    try expectEqual(engine.evaluateCharging(currentPercentage: 79), false, "Disabled sailing resumes immediately at 79%")
    try expectEqual(engine.isSailing, false, "isSailing remains false while disabled")
}

// 2. Heat Protection 5-Minute (300s) Hysteresis
runTest("2. Heat Protection 5-Minute (300s) Hysteresis") {
    let heat = HeatProtectionManager(thresholdCelsius: 35.0, hysteresisCooldownSeconds: 300.0)
    let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    try expectEqual(heat.evaluateTemperature(34.9, now: t0), false, "34.9°C must not trigger")
    try expectEqual(heat.isActive, false, "isActive starts false")
    try expectEqual(heat.remainingCooldownSeconds(now: t0), 0.0, "Cooldown is 0 when inactive")

    // Trigger at >= 35°C
    try expectEqual(heat.evaluateTemperature(35.0, now: t0), true, "35.0°C must trigger heat protection")
    try expectEqual(heat.isActive, true, "isActive must become true")

    // Stay active during 300s cooldown even when cooled below 35°C
    let t120 = t0.addingTimeInterval(120)
    try expectEqual(heat.evaluateTemperature(32.0, now: t120), true, "Must remain active at t+120s")
    try expectEqual(heat.remainingCooldownSeconds(now: t120), 180.0, "Remaining cooldown at t+120s must be 180s")

    let t299 = t0.addingTimeInterval(299)
    try expectEqual(heat.evaluateTemperature(29.0, now: t299), true, "Must remain active at t+299s")
    try expectEqual(heat.isActive, true, "isActive stays true before 300s")

    // Release after 300s when below threshold
    let t300 = t0.addingTimeInterval(300)
    try expectEqual(heat.evaluateTemperature(33.0, now: t300), false, "Must release at t+300s when < 35°C")
    try expectEqual(heat.isActive, false, "isActive must clear after cooldown")
    try expectEqual(heat.remainingCooldownSeconds(now: t300), 0.0, "Remaining cooldown must be 0 after release")

    // Re-trigger on subsequent heat spike
    try expectEqual(heat.evaluateTemperature(37.5, now: t0.addingTimeInterval(310)), true, "37.5°C must re-trigger")
    try expectEqual(heat.isActive, true, "isActive must be true on re-trigger")
}

// 3. Calibration Mode 4-Phase Transitions & Heat Protection Bypass
runTest("3. Calibration Mode 4-Phase Transitions & Heat Protection Bypass") {
    let cal = CalibrationEngine(userTargetLimit: 80)
    try expectEqual(cal.currentPhase, .idle, "Starts idle")
    try expectEqual(cal.bypassesHeatProtection, false, "Does not bypass heat protection when idle")

    cal.startCalibration()
    try expectEqual(cal.currentPhase, .chargeToFull, "Enters chargeToFull")
    try expectEqual(cal.bypassesHeatProtection, true, "Bypasses heat protection while calibrating")

    // Phase 1: chargeToFull -> dischargeToLow at 100%
    try expectEqual(cal.processTick(currentPercentage: 95, isPluggedIn: true), .chargeToFull, "95% holds chargeToFull")
    try expectEqual(cal.processTick(currentPercentage: 100, isPluggedIn: true), .dischargeToLow, "100% transitions to dischargeToLow")
    let phase2Dir = cal.hardwareDirectives(for: .dischargeToLow)
    try expectEqual(phase2Dir.inhibitCharging, true, "dischargeToLow inhibits charging")
    try expectEqual(phase2Dir.forceDischarge, true, "dischargeToLow forces discharge")

    // Phase 2: dischargeToLow -> rechargeToFull at <= 10%
    try expectEqual(cal.processTick(currentPercentage: 30, isPluggedIn: true), .dischargeToLow, "30% holds dischargeToLow")
    try expectEqual(cal.processTick(currentPercentage: 10, isPluggedIn: true), .rechargeToFull, "10% transitions to rechargeToFull")
    let phase3Dir = cal.hardwareDirectives(for: .rechargeToFull)
    try expectEqual(phase3Dir.inhibitCharging, false, "rechargeToFull allows charging")
    try expectEqual(phase3Dir.forceDischarge, false, "rechargeToFull stops discharge")

    // Phase 3: rechargeToFull -> returnToTargetLimit at 100%
    try expectEqual(cal.processTick(currentPercentage: 85, isPluggedIn: true), .rechargeToFull, "85% holds rechargeToFull")
    try expectEqual(cal.processTick(currentPercentage: 100, isPluggedIn: true), .returnToTargetLimit, "100% transitions to returnToTargetLimit")

    // Phase 4: returnToTargetLimit -> idle at <= targetLimit (80%)
    try expectEqual(cal.processTick(currentPercentage: 84, isPluggedIn: true), .returnToTargetLimit, "84% holds returnToTargetLimit")
    try expectEqual(cal.processTick(currentPercentage: 80, isPluggedIn: true), .idle, "80% returns to idle")
    try expectEqual(cal.bypassesHeatProtection, false, "No longer bypasses heat protection when idle")

    // Verify Heat Protection bypass during Calibration in full policy pipeline
    var config = BatteryConfig()
    config.heatProtectionEnabled = true
    config.heatThresholdCelsius = 35.0
    let heat = HeatProtectionManager(thresholdCelsius: 35.0, hysteresisCooldownSeconds: 300.0)
    let sailing = SailingModeEngine(targetLimit: 80, deadbandPercentage: 5)
    let hotSnapshot = makeSnapshot(displayPercentage: 88, temperatureCelsius: 39.5, isPluggedIn: true, isCharging: true)

    cal.startCalibration()
    let duringCal = evaluateCorePolicy(
        snapshot: hotSnapshot,
        config: &config,
        calibration: cal,
        heatProtection: heat,
        sailing: sailing
    )
    try expectEqual(duringCal.calibrationPhase, .chargeToFull, "Active calibration phase preserved")
    try expectEqual(duringCal.chargingInhibited, false, "Charging must NOT be inhibited by heat during calibration")
    try expectEqual(duringCal.heatProtectionActive, false, "Heat protection bypassed during calibration")

    // Cancel returns to idle and re-enables Heat Protection enforcement
    cal.cancelCalibration()
    try expectEqual(cal.currentPhase, .idle, "cancelCalibration resets to idle")
    let afterCancel = evaluateCorePolicy(
        snapshot: hotSnapshot,
        config: &config,
        calibration: cal,
        heatProtection: heat,
        sailing: sailing
    )
    try expectEqual(afterCancel.heatProtectionActive, true, "Heat protection activates once calibration is idle")
    try expectEqual(afterCancel.chargingInhibited, true, "Charging inhibited by heat protection when idle")
}

// 4. Automatic Discharge Trigger
runTest("4. Automatic Discharge Trigger (displayPercentage > chargeLimit)") {
    var config = BatteryConfig()
    config.chargeLimit = 80
    config.automaticDischargeEnabled = true
    let cal = CalibrationEngine(userTargetLimit: 80)
    let heat = HeatProtectionManager()
    let sailing = SailingModeEngine(targetLimit: 80, deadbandPercentage: 5)

    let overLimit = evaluateCorePolicy(
        snapshot: makeSnapshot(displayPercentage: 92, isPluggedIn: true),
        config: &config,
        calibration: cal,
        heatProtection: heat,
        sailing: sailing
    )
    try expectEqual(overLimit.forceDischarge, true, "92% > 80% with automatic discharge enabled must force discharge")
    try expectEqual(overLimit.chargingInhibited, true, "Charging must be inhibited while discharging")

    let atLimit = evaluateCorePolicy(
        snapshot: makeSnapshot(displayPercentage: 80, isPluggedIn: true),
        config: &config,
        calibration: cal,
        heatProtection: heat,
        sailing: sailing
    )
    try expectEqual(atLimit.forceDischarge, false, "80% == 80% must stop automatic discharge")

    config.automaticDischargeEnabled = false
    let disabled = evaluateCorePolicy(
        snapshot: makeSnapshot(displayPercentage: 95, isPluggedIn: true),
        config: &config,
        calibration: cal,
        heatProtection: heat,
        sailing: sailing
    )
    try expectEqual(disabled.forceDischarge, false, "Automatic discharge disabled must not force discharge")
}

// 5. Top Up 100% Override & Automatic Revert on Physical Unplug
runTest("5. Top Up 100% Override & Auto-Revert on Physical Unplug") {
    var config = BatteryConfig()
    config.chargeLimit = 80
    config.topUpActive = true
    let cal = CalibrationEngine(userTargetLimit: 80)
    let heat = HeatProtectionManager()
    let sailing = SailingModeEngine(targetLimit: 80, deadbandPercentage: 5)

    let toppingUp = evaluateCorePolicy(
        snapshot: makeSnapshot(displayPercentage: 88, isPluggedIn: true, isCharging: true),
        config: &config,
        calibration: cal,
        heatProtection: heat,
        sailing: sailing
    )
    try expectEqual(toppingUp.chargingInhibited, false, "Top Up overrides 80% limit and allows charging")
    try expectEqual(toppingUp.forceDischarge, false, "Top Up must not force discharge")
    try expectEqual(config.topUpActive, true, "topUpActive stays true while plugged in")

    let at100 = evaluateCorePolicy(
        snapshot: makeSnapshot(displayPercentage: 100, isPluggedIn: true, isCharging: false),
        config: &config,
        calibration: cal,
        heatProtection: heat,
        sailing: sailing
    )
    try expectEqual(at100.chargingInhibited, true, "Top Up inhibits charging once battery reaches 100%")

    let unplugged = evaluateCorePolicy(
        snapshot: makeSnapshot(displayPercentage: 98, isPluggedIn: false, isCharging: false),
        config: &config,
        calibration: cal,
        heatProtection: heat,
        sailing: sailing
    )
    try expectEqual(config.topUpActive, false, "Physical unplug must revert topUpActive to false")
    try expectEqual(unplugged.topUpActive, false, "Policy decision must reflect reverted topUpActive")
}

// 6. SchedulerEngine Cron Matching & Catch Up on Missed Tasks
runTest("6. SchedulerEngine Cron Matching & Catch Up on Missed Tasks") {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!

    let tempURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("nudge-test-schedules-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let scheduler = SchedulerEngine(storageURL: tempURL, calendar: calendar)

    // Monday 2026-11-16 (weekday == 2)
    let monday0930 = calendar.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 9, minute: 30, second: 10))!
    let monday1100 = calendar.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 11, minute: 0, second: 0))!
    let tuesday0930 = calendar.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: 9, minute: 30, second: 0))!

    let weekdayTask = ScheduledTask(
        name: "Monday Top Up",
        action: .startTopUp,
        targetValue: 100,
        hour: 9,
        minute: 30,
        weekdays: [2], // Monday only
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

    // Exact cron match at Monday 09:30 -> weekdayTask fires; noCatchUpTask (09:15) does not
    var firedNames: [String] = []
    let onTime = scheduler.evaluateDueTasks(now: monday0930, includeMissed: false) { task in
        firedNames.append(task.name)
    }
    try expectEqual(onTime.map(\.name), ["Monday Top Up"], "Exact Monday 09:30 slot must execute weekdayTask")
    try expectEqual(firedNames, ["Monday Top Up"], "Executor callback must receive exact due task")

    // Duplicate evaluation within same slot must not re-fire
    let duplicate = scheduler.evaluateDueTasks(now: monday0930.addingTimeInterval(15), includeMissed: false) { _ in }
    try expectEqual(duplicate.isEmpty, true, "Already executed task must not re-fire in same slot")

    // Next scheduled date for Monday-only task after Tuesday 09:30 must be next Monday (Nov 23)
    let nextDate = scheduler.nextScheduledDate(for: weekdayTask, after: tuesday0930)
    let expectedNextMonday = calendar.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 9, minute: 30, second: 0))!
    try expectEqual(nextDate, expectedNextMonday, "nextScheduledDate must compute next matching weekday")

    // Missed-task catch-up on a fresh SchedulerEngine instance (simulating wake/relaunch at 11:00)
    let missedURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("nudge-test-missed-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: missedURL) }

    let wakeScheduler = SchedulerEngine(storageURL: missedURL, calendar: calendar)
    wakeScheduler.addTask(weekdayTask)
    wakeScheduler.addTask(noCatchUpTask)

    var caughtUp: [String] = []
    let missedResults = wakeScheduler.evaluateDueTasks(now: monday1100, includeMissed: true) { task in
        caughtUp.append(task.name)
    }
    try expectEqual(missedResults.map(\.name), ["Monday Top Up"], "Catch-up at 11:00 must run missed catchUpIfMissed task only")
    try expectEqual(caughtUp, ["Monday Top Up"], "noCatchUpTask must not be caught up")
}

// 7. SleepControlState & SleepController Fallback Trigger Evaluation
runTest("7. SleepControlState & SleepController Fallback Triggers (<= 20% or Unplugged)") {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let controller = SleepController()
    defer { _ = controller.disableKeepAwake() }

    // 7a. Unplug fallback when reenableOnUnplug == true
    _ = controller.enableTimedKeepAwake(minutes: 60, fallbackBatteryPercent: 20, reenableOnUnplug: true, now: now)
    let pluggedRes = controller.evaluate(snapshot: makeSnapshot(displayPercentage: 65, isPluggedIn: true), chargeLimit: 80, now: now)
    try expectEqual(pluggedRes.state.keepAwakeActive, true, "Keep-awake stays active while plugged in at 65%")

    let unpluggedRes = controller.evaluate(snapshot: makeSnapshot(displayPercentage: 65, isPluggedIn: false), chargeLimit: 80, now: now)
    try expectEqual(unpluggedRes.state.keepAwakeActive, false, "Unplugging with reenableOnUnplug == true must disable keep-awake")
    try expectEqual(unpluggedRes.assertionActive, false, "IOPMAssertion must release on unplug fallback")

    // 7b. Low-battery <= 20% fallback when running on battery (reenableOnUnplug == false)
    _ = controller.enableTimedKeepAwake(minutes: 60, fallbackBatteryPercent: 20, reenableOnUnplug: false, now: now)
    let batteryHealthy = controller.evaluate(snapshot: makeSnapshot(displayPercentage: 35, isPluggedIn: false), chargeLimit: 80, now: now)
    try expectEqual(batteryHealthy.state.keepAwakeActive, true, "35% on battery (> 20%) keeps awake when reenableOnUnplug == false")

    let batteryLow = controller.evaluate(snapshot: makeSnapshot(displayPercentage: 20, isPluggedIn: false), chargeLimit: 80, now: now)
    try expectEqual(batteryLow.state.keepAwakeActive, false, "Battery <= 20% must trigger low-battery fallback")
    try expectEqual(batteryLow.assertionActive, false, "IOPMAssertion must release at <= 20% fallback")

    // 7c. Expiry timer fallback
    _ = controller.enableTimedKeepAwake(minutes: 30, fallbackBatteryPercent: 20, reenableOnUnplug: true, now: now)
    let expired = controller.evaluate(snapshot: makeSnapshot(displayPercentage: 70, isPluggedIn: true), chargeLimit: 80, now: now.addingTimeInterval(1801))
    try expectEqual(expired.state.keepAwakeActive, false, "Expired timed keep-awake must deactivate")
    try expectEqual(expired.assertionActive, false, "IOPMAssertion must release on expiry")

    // 7d. Disable sleep until charge limit reached
    _ = controller.configure(disableSleepUntilChargeLimit: true, fallbackBatteryPercent: 20, reenableOnUnplug: true)
    let belowLimit = controller.evaluate(snapshot: makeSnapshot(displayPercentage: 70, isPluggedIn: true), chargeLimit: 80, now: now)
    try expectEqual(belowLimit.assertionActive, true, "Assertion held while charging toward 80% limit")

    let reachedLimit = controller.evaluate(snapshot: makeSnapshot(displayPercentage: 80, isPluggedIn: true), chargeLimit: 80, now: now)
    try expectEqual(reachedLimit.assertionActive, false, "Assertion released once chargeLimit 80% is reached")
}

// 8. BatteryConfig JSON Encode/Decode Round-Trip
runTest("8. BatteryConfig JSON Encode/Decode Round-Trip") {
    var original = BatteryConfig()
    original.chargeLimit = 75
    original.sailingModeEnabled = true
    original.sailingDeadband = 8
    original.heatProtectionEnabled = true
    original.heatThresholdCelsius = 36.5
    original.automaticDischargeEnabled = true
    original.manualDischargeActive = false
    original.topUpActive = true
    original.stopChargingWhenSleeping = true
    original.stopChargingWhenAppClosed = true
    original.disableSleepUntilChargeLimit = true
    original.keepAwakeFallbackPercent = 25
    original.keepAwakeReenableOnUnplug = true
    original.magSafeLEDMode = .orange
    original.syncMagSafeLEDWithState = false
    original.showHardwarePercentage = true
    original.catchUpMissedTasks = true
    original.preferredPowerMode = .lowPower
    original.menuBarComponents = [.liveIcon, .hardwarePercentage, .temperature, .powerFlow, .maxCapacity]
    original.popoverWidgetOrder = [
        .powerFlow,
        .chargeControl,
        .historicalCharts,
        .highEnergyApps,
        .batterySpecs,
        .sleepAndPowerMode,
        .schedule,
        .calibrationAndLED
    ]
    original.hiddenPopoverWidgets = [.calibrationAndLED]
    original.appearancePreference = "dark"

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(original)
    let decoded = try JSONDecoder().decode(BatteryConfig.self, from: data)

    try expectEqual(decoded, original, "Decoded BatteryConfig must equal original")
    try expectEqual(decoded.menuBarComponents, original.menuBarComponents, "menuBarComponents must preserve order")
    try expectEqual(decoded.popoverWidgetOrder, original.popoverWidgetOrder, "popoverWidgetOrder must preserve order")
    try expectEqual(decoded.hiddenPopoverWidgets, [.calibrationAndLED], "hiddenPopoverWidgets must round-trip")
}

// 9. Live IOKitPowerReader.shared.readCurrentSnapshot() Sanity Check
runTest("9. Live IOKitPowerReader.shared.readCurrentSnapshot() Sanity Check") {
    let snapshot = IOKitPowerReader.shared.readCurrentSnapshot()

    try expect((0...100).contains(snapshot.displayPercentage), "displayPercentage out of bounds: \(snapshot.displayPercentage)")
    try expect(snapshot.rawHardwarePercentage >= 0.0 && snapshot.rawHardwarePercentage <= 100.0, "rawHardwarePercentage out of bounds: \(snapshot.rawHardwarePercentage)")
    try expect(snapshot.temperatureCelsius > -10.0 && snapshot.temperatureCelsius < 110.0, "temperatureCelsius out of plausible range: \(snapshot.temperatureCelsius)")
    try expect(snapshot.cycleCount >= 0, "cycleCount must be non-negative: \(snapshot.cycleCount)")
    try expect(snapshot.maxCapacityMah > 0, "maxCapacityMah must be positive: \(snapshot.maxCapacityMah)")
    try expect(snapshot.healthPercentage > 0.0 && snapshot.healthPercentage <= 100.0, "healthPercentage out of bounds: \(snapshot.healthPercentage)")
    try expect(!snapshot.powerFlow.chargerInputWatts.isNaN, "chargerInputWatts must not be NaN")
    try expect(!snapshot.powerFlow.batteryWatts.isNaN, "batteryWatts must not be NaN")
    try expect(!snapshot.powerFlow.systemLoadWatts.isNaN, "systemLoadWatts must not be NaN")
}

// 10. NudgeIntents Type Instantiation & AppShortcutsProvider Check
runTest("10. NudgeIntents Type Instantiation Check") {
    let getStatus = GetBatteryStatusIntent()
    let getLimit = GetChargeLimitIntent()
    let getTemp = GetBatteryTemperatureIntent()
    let setLimit = SetChargeLimitIntent(limit: 80)
    let startDischarge = StartDischargeIntent()
    let stopDischarge = StopDischargeIntent()
    let startTopUp = StartTopUpIntent()
    let stopTopUp = StopTopUpIntent()
    let startCalibration = StartCalibrationIntent()
    let cancelCalibration = CancelCalibrationIntent()
    let toggleSailing = ToggleSailingModeIntent(enabled: true, deadband: 5)
    let toggleHeat = ToggleHeatProtectionIntent(enabled: true, threshold: 35.0)
    let setLED = SetMagSafeLEDIntent(mode: .orange)
    let setPowerMode = SetPowerModeIntent(mode: .lowPower)
    let keepAwake = KeepAwakeIntent(minutes: 45)

    let intents: [any AppIntent] = [
        getStatus, getLimit, getTemp, setLimit,
        startDischarge, stopDischarge, startTopUp, stopTopUp,
        startCalibration, cancelCalibration, toggleSailing, toggleHeat,
        setLED, setPowerMode, keepAwake
    ]

    try expectEqual(intents.count, 15, "All 15 Nudge AppIntent types must instantiate cleanly")
    try expectEqual(setLimit.limit, 80, "SetChargeLimitIntent limit parameter preserved")
    try expectEqual(toggleSailing.deadband, 5, "ToggleSailingModeIntent deadband preserved")
    try expectEqual(toggleHeat.threshold, 35.0, "ToggleHeatProtectionIntent threshold preserved")
    try expectEqual(setLED.mode.coreState, .orange, "MagSafeLEDAppOption maps to core MagSafeLEDState")
    try expectEqual(setPowerMode.mode.coreMode, .lowPower, "PowerModeAppOption maps to core PowerMode")
    try expectEqual(keepAwake.minutes, 45, "KeepAwakeIntent minutes parameter preserved")
    try expect(!NudgeShortcutsProvider.appShortcuts.isEmpty, "NudgeShortcutsProvider must expose Siri/Shortcuts entries")
}

// MARK: - Final Summary & Exit Code

let passedCount = outcomes.filter(\.passed).count
let failedCount = outcomes.count - passedCount

print("============================================================")
print("Results: \(passedCount)/\(outcomes.count) passed, \(failedCount) failed")
print("============================================================")

if failedCount > 0 {
    for failure in outcomes where !failure.passed {
        fputs("FAILED: \(failure.name) -> \(failure.details)\n", stderr)
    }
    exit(EXIT_FAILURE)
}

exit(EXIT_SUCCESS)
