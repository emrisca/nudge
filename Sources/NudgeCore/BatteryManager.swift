import Foundation
import Combine

/// Central coordinator for Nudge battery hardware control, telemetry, scheduling,
/// sleep assertions, power mode management, energy monitoring, and persistence.
public final class BatteryManager: ObservableObject, @unchecked Sendable {
    public static let shared = BatteryManager()

    public static var defaultConfigURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return appSupport
            .appendingPathComponent("Nudge", isDirectory: true)
            .appendingPathComponent("config.json", isDirectory: false)
    }

    // MARK: - Published State (Contract)

    @Published public private(set) var config: BatteryConfig
    @Published public private(set) var latestSnapshot: BatterySnapshot
    @Published public private(set) var latestTick: BatteryTickResult
    @Published public private(set) var history: [BatteryHistoryPoint]
    @Published public private(set) var highEnergyApps: [HighEnergyApp]
    @Published public private(set) var scheduledTasks: [ScheduledTask]
    @Published public private(set) var sleepState: SleepControlState
    @Published public private(set) var currentPowerMode: PowerMode
    @Published public private(set) var daemonStatus: HelperDaemonStatus

    // MARK: - Core Sub-Engines

    public let heatProtection: HeatProtectionManager
    public let sailingEngine: SailingModeEngine
    public let calibrationEngine: CalibrationEngine
    public let smcClient: SMCClient
    public let powerReader: IOKitPowerReader
    public let sleepController: SleepController
    public let scheduler: SchedulerEngine
    public let energyMonitor: EnergyMonitor
    public let powerModeController: PowerModeController
    public let historyStore: TelemetryHistoryStore
    public let helperClient: HelperXPCClient

    // MARK: - Internal Concurrency & Low-CPU Monitoring State

    private let lock = NSLock()
    private let configURL: URL
    private let monitorQueue = DispatchQueue(label: "com.emrisca.nudge.monitor", qos: .utility)
    private var monitorTimer: DispatchSourceTimer?

    private var lastWrittenChargeInhibited: Bool?
    private var lastWrittenForceDischarge: Bool?
    private var lastWrittenChargeLimit: Int?
    private var lastWrittenMagSafeLED: MagSafeLEDState?
    private var lastEnergyRefreshDate: Date = .distantPast

    public init(
        config: BatteryConfig? = nil,
        configURL: URL? = nil,
        historyStore: TelemetryHistoryStore? = nil,
        scheduler: SchedulerEngine? = nil,
        smcClient: SMCClient = .shared,
        powerReader: IOKitPowerReader = .shared,
        powerModeController: PowerModeController = .shared,
        helperClient: HelperXPCClient = .shared
    ) {
        let resolvedConfigURL = configURL ?? Self.defaultConfigURL
        let loadedConfig = config ?? Self.loadConfig(from: resolvedConfigURL) ?? BatteryConfig()

        self.configURL = resolvedConfigURL
        self.smcClient = smcClient
        self.powerReader = powerReader
        self.powerModeController = powerModeController
        self.helperClient = helperClient
        self.historyStore = historyStore ?? TelemetryHistoryStore()
        self.scheduler = scheduler ?? SchedulerEngine()
        self.energyMonitor = EnergyMonitor()

        self.heatProtection = HeatProtectionManager(thresholdCelsius: loadedConfig.heatThresholdCelsius)
        self.sailingEngine = SailingModeEngine(
            targetLimit: loadedConfig.chargeLimit,
            deadbandPercentage: loadedConfig.sailingDeadband,
            isEnabled: loadedConfig.sailingModeEnabled
        )
        self.calibrationEngine = CalibrationEngine(userTargetLimit: loadedConfig.chargeLimit)

        let initialSleep = SleepControlState(
            keepAwakeActive: false,
            disableSleepUntilChargeLimit: loadedConfig.disableSleepUntilChargeLimit,
            expiresAt: nil,
            fallbackBatteryPercent: loadedConfig.keepAwakeFallbackPercent,
            reenableOnUnplug: loadedConfig.keepAwakeReenableOnUnplug
        )
        self.sleepController = SleepController(initialState: initialSleep)

        let initialSnapshot = powerReader.readCurrentSnapshot()
        let initialHistory = self.historyStore.seedIfEmpty(with: initialSnapshot)
        let initialPowerMode = powerModeController.detectCurrentMode(forceRefresh: false)
        let initialDaemonStatus = helperClient.status

        self.config = loadedConfig
        self.latestSnapshot = initialSnapshot
        self.latestTick = BatteryTickResult(
            snapshot: initialSnapshot,
            chargingInhibited: false,
            forceDischarge: false,
            heatProtectionActive: false,
            heatCooldownRemainingSeconds: 0,
            sailingActive: false,
            calibrationPhase: .idle,
            activeMagSafeLED: loadedConfig.magSafeLEDMode,
            sleepAssertionActive: false
        )
        self.history = initialHistory
        self.highEnergyApps = []
        self.scheduledTasks = self.scheduler.tasks
        self.sleepState = initialSleep
        self.currentPowerMode = initialPowerMode
        self.daemonStatus = initialDaemonStatus

        wireSleepCallbacks()
    }

    deinit {
        stopMonitoring()
    }

    // MARK: - Monitoring Lifecycle (<1% Idle CPU via DispatchSourceTimer with leeway)

    public func startMonitoring(interval: TimeInterval = 5.0) {
        let clampedInterval = max(1.0, interval)

        lock.lock()
        monitorTimer?.cancel()
        monitorTimer = nil

        let timer = DispatchSource.makeTimerSource(queue: monitorQueue)
        timer.schedule(
            deadline: .now() + clampedInterval,
            repeating: clampedInterval,
            leeway: .milliseconds(500)
        )
        timer.setEventHandler { [weak self] in
            self?.performBackgroundTick()
        }
        monitorTimer = timer
        let shouldCatchUp = config.catchUpMissedTasks
        lock.unlock()

        if shouldCatchUp {
            runMissedScheduledTasksIfNeeded()
        }
        _ = tick()
        timer.resume()
    }

    public func stopMonitoring() {
        lock.lock()
        let timer = monitorTimer
        monitorTimer = nil
        lock.unlock()

        timer?.cancel()
        historyStore.flushToDisk()
    }

    private func performBackgroundTick() {
        _ = tick()

        // Refresh high-energy apps at a relaxed 15s cadence to keep idle CPU <1%
        lock.lock()
        let shouldRefreshApps = Date().timeIntervalSince(lastEnergyRefreshDate) >= 15.0
        lock.unlock()

        if shouldRefreshApps {
            refreshHighEnergyApps()
        }
    }

    // MARK: - Core Control Tick

    @discardableResult
    public func tick() -> BatteryTickResult {
        let now = Date()
        let rawSnapshot = powerReader.readCurrentSnapshot()

        lock.lock()
        var currentConfig = config
        var configMutated = false

        // Keep sub-engines synchronized with current config
        heatProtection.thresholdCelsius = currentConfig.heatThresholdCelsius
        sailingEngine.targetLimit = currentConfig.chargeLimit
        sailingEngine.deadbandPercentage = currentConfig.sailingDeadband
        sailingEngine.isEnabled = currentConfig.sailingModeEnabled
        calibrationEngine.userTargetLimit = currentConfig.chargeLimit

        var chargingInhibited = false
        var forceDischarge = false
        var heatActive = false
        var heatCooldownRemaining: TimeInterval = 0
        var sailingActive = false
        var calibrationPhase = calibrationEngine.currentPhase

        // 1. Calibration Mode (4-phase cycle; explicitly bypasses Heat Protection)
        if calibrationPhase != .idle {
            calibrationPhase = calibrationEngine.processTick(
                currentPercentage: rawSnapshot.displayPercentage,
                isPluggedIn: rawSnapshot.isPluggedIn
            )
            if calibrationPhase != .idle {
                let directives = calibrationEngine.hardwareDirectives(for: calibrationPhase)
                chargingInhibited = directives.inhibitCharging
                forceDischarge = directives.forceDischarge
                heatActive = false
                heatCooldownRemaining = 0
                sailingActive = false
            }
        }

        // 2. Normal Control Pipeline (when not actively calibrating)
        if calibrationPhase == .idle {
            // 2a. Top Up auto-revert upon physical unplug
            if currentConfig.topUpActive && !rawSnapshot.isPluggedIn {
                currentConfig.topUpActive = false
                configMutated = true
            }

            // 2b. Clear manual discharge automatically if already unplugged
            if currentConfig.manualDischargeActive && !rawSnapshot.isPluggedIn {
                currentConfig.manualDischargeActive = false
                configMutated = true
            }

            // 2c. Heat Protection (active unless calibrating)
            if currentConfig.heatProtectionEnabled {
                heatActive = heatProtection.evaluateTemperature(rawSnapshot.temperatureCelsius, now: now)
                heatCooldownRemaining = heatProtection.remainingCooldownSeconds(now: now)
            } else {
                heatProtection.reset()
                heatActive = false
                heatCooldownRemaining = 0
            }

            // 2d. Manual Discharge override (with 5% safety floor)
            if currentConfig.manualDischargeActive && rawSnapshot.isPluggedIn {
                if rawSnapshot.displayPercentage <= 5 {
                    currentConfig.manualDischargeActive = false
                    configMutated = true
                } else {
                    chargingInhibited = true
                    forceDischarge = true
                }
            } else if heatActive {
                // Overheated -> inhibit charging immediately
                chargingInhibited = true
                forceDischarge = false
            } else if currentConfig.topUpActive {
                // Top Up to 100% overrides charge limit & sailing mode
                if rawSnapshot.displayPercentage >= 100 {
                    chargingInhibited = true
                } else {
                    chargingInhibited = false
                }
                forceDischarge = false
            } else {
                // 2e. Sailing Mode / Charge Limiter
                let limitInhibit = sailingEngine.evaluateCharging(currentPercentage: rawSnapshot.displayPercentage)
                sailingActive = sailingEngine.isSailing && currentConfig.sailingModeEnabled && limitInhibit
                chargingInhibited = limitInhibit

                // 2f. Automatic Discharge when chargeLimit < displayPercentage while plugged in
                if currentConfig.automaticDischargeEnabled
                    && rawSnapshot.isPluggedIn
                    && rawSnapshot.displayPercentage > currentConfig.chargeLimit {
                    chargingInhibited = true
                    forceDischarge = true
                }
            }
        }

        if configMutated {
            config = currentConfig
        }

        // 3. Derive effective ChargingState for snapshot
        let effectiveState: ChargingState
        if calibrationPhase != .idle {
            effectiveState = .calibrating
        } else if !rawSnapshot.isPluggedIn {
            effectiveState = .unplugged
        } else if heatActive {
            effectiveState = .overheated
        } else if forceDischarge {
            effectiveState = .discharging
        } else if sailingActive {
            effectiveState = .sailing
        } else if chargingInhibited {
            effectiveState = .paused
        } else if rawSnapshot.isCharging || rawSnapshot.powerFlow.batteryWatts > 0.25 {
            effectiveState = .charging
        } else {
            effectiveState = rawSnapshot.state
        }

        let effectiveSnapshot = BatterySnapshot(
            id: rawSnapshot.id,
            timestamp: rawSnapshot.timestamp,
            rawHardwarePercentage: rawSnapshot.rawHardwarePercentage,
            displayPercentage: rawSnapshot.displayPercentage,
            temperatureCelsius: rawSnapshot.temperatureCelsius,
            cycleCount: rawSnapshot.cycleCount,
            designCapacityMah: rawSnapshot.designCapacityMah,
            maxCapacityMah: rawSnapshot.maxCapacityMah,
            currentCapacityMah: rawSnapshot.currentCapacityMah,
            voltageVolts: rawSnapshot.voltageVolts,
            amperageAmps: rawSnapshot.amperageAmps,
            isPluggedIn: rawSnapshot.isPluggedIn,
            isCharging: rawSnapshot.isCharging && !chargingInhibited && !forceDischarge,
            adapterMaxWatts: rawSnapshot.adapterMaxWatts,
            timeRemainingMinutes: rawSnapshot.timeRemainingMinutes,
            powerFlow: rawSnapshot.powerFlow,
            state: effectiveState,
            architecture: rawSnapshot.architecture
        )

        // 4. Compute desired MagSafe LED state
        let desiredLED = resolveMagSafeLED(
            config: currentConfig,
            state: effectiveState,
            isPluggedIn: effectiveSnapshot.isPluggedIn,
            forceDischarge: forceDischarge,
            chargingInhibited: chargingInhibited
        )

        // Determine if hardware writes changed (avoid hammering SMC every tick)
        let shouldWriteLimit = (lastWrittenChargeLimit != currentConfig.chargeLimit)
        let shouldWriteInhibit = (lastWrittenChargeInhibited != chargingInhibited)
        let shouldWriteDischarge = (lastWrittenForceDischarge != forceDischarge)
        let shouldWriteLED = (lastWrittenMagSafeLED != desiredLED)

        lastWrittenChargeLimit = currentConfig.chargeLimit
        lastWrittenChargeInhibited = chargingInhibited
        lastWrittenForceDischarge = forceDischarge
        lastWrittenMagSafeLED = desiredLED

        let finalConfig = currentConfig
        lock.unlock()

        if configMutated {
            Self.persistConfig(finalConfig, to: configURL)
        }

        // 5. Apply hardware commands (SMC direct + Helper XPC)
        if shouldWriteLimit {
            _ = smcClient.setChargeLimit(finalConfig.chargeLimit)
        }
        if shouldWriteInhibit {
            _ = smcClient.setChargeInhibited(chargingInhibited)
        }
        if shouldWriteDischarge {
            _ = smcClient.setForceDischarge(forceDischarge)
        }
        if shouldWriteLED {
            _ = smcClient.setMagSafeLED(desiredLED)
        }
        if (shouldWriteLimit || shouldWriteInhibit || shouldWriteDischarge) && helperClient.isConnected {
            _ = helperClient.setChargeLimit(
                finalConfig.chargeLimit,
                sailingDeadband: finalConfig.sailingDeadband,
                inhibitCharging: chargingInhibited,
                forceDischarge: forceDischarge
            )
        }

        // 6. Evaluate Sleep Assertions
        let sleepEval = sleepController.evaluate(
            snapshot: effectiveSnapshot,
            chargeLimit: finalConfig.chargeLimit,
            now: now
        )

        // 7. Record Telemetry History & Power Mode
        let updatedHistory = historyStore.record(snapshot: effectiveSnapshot)
        let detectedPowerMode = powerModeController.detectCurrentMode(forceRefresh: false)
        let currentDaemon = helperClient.status

        // 8. Evaluate due scheduled tasks (current minute)
        evaluateScheduledTasks(now: now, includeMissed: false)

        let tickResult = BatteryTickResult(
            snapshot: effectiveSnapshot,
            chargingInhibited: chargingInhibited,
            forceDischarge: forceDischarge,
            heatProtectionActive: heatActive,
            heatCooldownRemainingSeconds: heatCooldownRemaining,
            sailingActive: sailingActive,
            calibrationPhase: calibrationPhase,
            activeMagSafeLED: desiredLED,
            sleepAssertionActive: sleepEval.assertionActive
        )

        // 9. Publish updates cleanly
        let updatedTasks = scheduler.tasks
        let didMutateConfig = configMutated
        publishOnMain {
            if didMutateConfig {
                self.config = finalConfig
            }
            self.latestSnapshot = effectiveSnapshot
            self.latestTick = tickResult
            self.history = updatedHistory
            self.sleepState = sleepEval.state
            self.currentPowerMode = detectedPowerMode
            self.daemonStatus = currentDaemon
            self.scheduledTasks = updatedTasks
        }

        return tickResult
    }

    // MARK: - Configuration & Controls (Contract)

    public func updateConfig(_ mutate: (inout BatteryConfig) -> Void) {
        lock.lock()
        var updated = config
        mutate(&updated)

        // Sanitize bounds
        updated.chargeLimit = max(20, min(100, updated.chargeLimit))
        updated.sailingDeadband = max(1, min(20, updated.sailingDeadband))
        updated.heatThresholdCelsius = max(25.0, min(60.0, updated.heatThresholdCelsius))
        updated.keepAwakeFallbackPercent = max(5, min(95, updated.keepAwakeFallbackPercent))

        let stopWhenClosedChanged = (updated.stopChargingWhenAppClosed != config.stopChargingWhenAppClosed)
        config = updated

        heatProtection.thresholdCelsius = updated.heatThresholdCelsius
        sailingEngine.targetLimit = updated.chargeLimit
        sailingEngine.deadbandPercentage = updated.sailingDeadband
        sailingEngine.isEnabled = updated.sailingModeEnabled
        calibrationEngine.userTargetLimit = updated.chargeLimit
        lock.unlock()

        let updatedSleep = sleepController.configure(
            disableSleepUntilChargeLimit: updated.disableSleepUntilChargeLimit,
            fallbackBatteryPercent: updated.keepAwakeFallbackPercent,
            reenableOnUnplug: updated.keepAwakeReenableOnUnplug
        )

        if stopWhenClosedChanged && helperClient.isConnected {
            _ = helperClient.setStopChargingWhenClosed(updated.stopChargingWhenAppClosed)
        }

        let finalUpdated = updated
        Self.persistConfig(finalUpdated, to: configURL)

        publishOnMain {
            self.config = finalUpdated
            self.sleepState = updatedSleep
        }
    }

    public func setChargeLimit(_ percentage: Int) {
        let clamped = max(20, min(100, percentage))
        updateConfig { cfg in
            cfg.chargeLimit = clamped
            if clamped < 100 {
                cfg.topUpActive = false
            }
        }
        _ = tick()
    }

    public func setManualDischarge(_ active: Bool) {
        updateConfig { cfg in
            cfg.manualDischargeActive = active
            if active {
                cfg.topUpActive = false
            }
        }
        _ = tick()
    }

    public func setTopUp(_ active: Bool) {
        updateConfig { cfg in
            cfg.topUpActive = active
            if active {
                cfg.manualDischargeActive = false
            }
        }
        _ = tick()
    }

    public func startCalibration() {
        updateConfig { cfg in
            cfg.topUpActive = false
            cfg.manualDischargeActive = false
        }
        calibrationEngine.startCalibration()
        _ = tick()
    }

    public func cancelCalibration() {
        calibrationEngine.cancelCalibration()
        _ = tick()
    }

    public func setMagSafeLED(_ state: MagSafeLEDState) {
        updateConfig { cfg in
            cfg.magSafeLEDMode = state
            cfg.syncMagSafeLEDWithState = (state == .systemDefault)
        }
        lock.lock()
        lastWrittenMagSafeLED = state
        lock.unlock()
        _ = smcClient.setMagSafeLED(state)
        _ = tick()
    }

    @discardableResult
    public func setPowerMode(_ mode: PowerMode) -> Bool {
        updateConfig { cfg in
            cfg.preferredPowerMode = mode
        }
        let applied = powerModeController.setPowerMode(mode)
        let effectiveMode = applied ? mode : powerModeController.detectCurrentMode(forceRefresh: false)
        publishOnMain {
            self.currentPowerMode = effectiveMode
        }
        return applied
    }

    public func enableTimedKeepAwake(
        minutes: Int?,
        fallbackBatteryPercent: Int? = nil,
        reenableOnUnplug: Bool? = nil
    ) {
        if let fallback = fallbackBatteryPercent, let unplug = reenableOnUnplug {
            updateConfig { cfg in
                cfg.keepAwakeFallbackPercent = fallback
                cfg.keepAwakeReenableOnUnplug = unplug
            }
        } else if let fallback = fallbackBatteryPercent {
            updateConfig { cfg in
                cfg.keepAwakeFallbackPercent = fallback
            }
        } else if let unplug = reenableOnUnplug {
            updateConfig { cfg in
                cfg.keepAwakeReenableOnUnplug = unplug
            }
        }

        let updatedSleep = sleepController.enableTimedKeepAwake(
            minutes: minutes,
            fallbackBatteryPercent: fallbackBatteryPercent,
            reenableOnUnplug: reenableOnUnplug
        )
        publishOnMain {
            self.sleepState = updatedSleep
        }
        _ = tick()
    }

    public func disableKeepAwake() {
        let updatedSleep = sleepController.disableKeepAwake()
        publishOnMain {
            self.sleepState = updatedSleep
        }
        _ = tick()
    }

    // MARK: - Scheduler Management (Contract)

    public func addScheduledTask(_ task: ScheduledTask) {
        scheduler.addTask(task)
        let updated = scheduler.tasks
        publishOnMain {
            self.scheduledTasks = updated
        }
    }

    public func updateScheduledTask(_ task: ScheduledTask) {
        scheduler.updateTask(task)
        let updated = scheduler.tasks
        publishOnMain {
            self.scheduledTasks = updated
        }
    }

    public func removeScheduledTask(id: UUID) {
        scheduler.removeTask(id: id)
        let updated = scheduler.tasks
        publishOnMain {
            self.scheduledTasks = updated
        }
    }

    public func runMissedScheduledTasksIfNeeded() {
        lock.lock()
        let allowCatchUp = config.catchUpMissedTasks
        lock.unlock()
        guard allowCatchUp else { return }

        evaluateScheduledTasks(now: Date(), includeMissed: true)
    }

    // MARK: - High-Energy Apps Monitoring (Contract)

    public func refreshHighEnergyApps() {
        lock.lock()
        let systemWatts = latestSnapshot.powerFlow.systemLoadWatts
        lastEnergyRefreshDate = Date()
        lock.unlock()

        let apps = energyMonitor.sampleHighEnergyApps(limit: 10, systemLoadWatts: systemWatts)
        publishOnMain {
            self.highEnergyApps = apps
        }
    }

    @discardableResult
    public func terminateHighEnergyApp(pid: Int32) -> Bool {
        let terminated = energyMonitor.terminateApp(pid: pid)
        if terminated {
            monitorQueue.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.refreshHighEnergyApps()
            }
        }
        return terminated
    }

    // MARK: - Privileged Helper Daemon (Contract)

    @discardableResult
    public func installOrConnectHelperDaemon() -> HelperDaemonStatus {
        let status = helperClient.installOrConnect()
        if status.isConnected {
            lock.lock()
            let cfg = config
            let inhibited = lastWrittenChargeInhibited ?? false
            let discharge = lastWrittenForceDischarge ?? false
            lock.unlock()

            _ = helperClient.setStopChargingWhenClosed(cfg.stopChargingWhenAppClosed)
            _ = helperClient.setChargeLimit(
                cfg.chargeLimit,
                sailingDeadband: cfg.sailingDeadband,
                inhibitCharging: inhibited,
                forceDischarge: discharge
            )
        }
        publishOnMain {
            self.daemonStatus = status
        }
        return status
    }

    // MARK: - JSON State Summary Export (Contract)

    public func exportStateSummaryJSON() -> String {
        struct StateSummary: Codable {
            let timestamp: Date
            let config: BatteryConfig
            let snapshot: BatterySnapshot
            let chargingInhibited: Bool
            let forceDischarge: Bool
            let heatProtectionActive: Bool
            let heatCooldownRemainingSeconds: TimeInterval
            let sailingActive: Bool
            let calibrationPhase: CalibrationPhase
            let activeMagSafeLED: MagSafeLEDState
            let sleepState: SleepControlState
            let sleepAssertionActive: Bool
            let powerMode: PowerMode
            let daemonStatus: HelperDaemonStatus
            let scheduledTaskCount: Int
            let historyPointCount: Int
        }

        lock.lock()
        let currentCfg = config
        let currentSnap = latestSnapshot
        let currentTick = latestTick
        let currentSleep = sleepState
        let currentMode = currentPowerMode
        let currentDaemon = daemonStatus
        let taskCount = scheduledTasks.count
        let histCount = history.count
        lock.unlock()

        let summary = StateSummary(
            timestamp: Date(),
            config: currentCfg,
            snapshot: currentSnap,
            chargingInhibited: currentTick.chargingInhibited,
            forceDischarge: currentTick.forceDischarge,
            heatProtectionActive: currentTick.heatProtectionActive,
            heatCooldownRemainingSeconds: currentTick.heatCooldownRemainingSeconds,
            sailingActive: currentTick.sailingActive,
            calibrationPhase: currentTick.calibrationPhase,
            activeMagSafeLED: currentTick.activeMagSafeLED,
            sleepState: currentSleep,
            sleepAssertionActive: currentTick.sleepAssertionActive,
            powerMode: currentMode,
            daemonStatus: currentDaemon,
            scheduledTaskCount: taskCount,
            historyPointCount: histCount
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        guard let data = try? encoder.encode(summary),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }

    // MARK: - Private Helpers

    private func resolveMagSafeLED(
        config: BatteryConfig,
        state: ChargingState,
        isPluggedIn: Bool,
        forceDischarge: Bool,
        chargingInhibited: Bool
    ) -> MagSafeLEDState {
        guard config.syncMagSafeLEDWithState else {
            return config.magSafeLEDMode
        }
        guard isPluggedIn else {
            return .systemDefault
        }
        if forceDischarge || state == .discharging {
            return (config.magSafeLEDMode == .off) ? .off : .blinkingOrange
        }
        if chargingInhibited || state == .paused || state == .sailing || state == .overheated {
            return .green
        }
        if state == .charging || state == .calibrating {
            return .orange
        }
        return .systemDefault
    }

    private func evaluateScheduledTasks(now: Date, includeMissed: Bool) {
        let executed = scheduler.evaluateDueTasks(now: now, includeMissed: includeMissed) { [weak self] task in
            self?.executeScheduledAction(task)
        }
        if !executed.isEmpty {
            let updated = scheduler.tasks
            publishOnMain {
                self.scheduledTasks = updated
            }
        }
    }

    private func executeScheduledAction(_ task: ScheduledTask) {
        switch task.action {
        case .setChargeLimit:
            let limit = task.targetValue ?? 80
            updateConfig { cfg in
                cfg.chargeLimit = limit
                cfg.topUpActive = false
            }
        case .startTopUp:
            updateConfig { cfg in
                cfg.topUpActive = true
                cfg.manualDischargeActive = false
            }
        case .startDischarge:
            updateConfig { cfg in
                cfg.manualDischargeActive = true
                cfg.topUpActive = false
            }
        case .stopDischarge:
            updateConfig { cfg in
                cfg.manualDischargeActive = false
            }
        case .startCalibration:
            updateConfig { cfg in
                cfg.topUpActive = false
                cfg.manualDischargeActive = false
            }
            calibrationEngine.startCalibration()
        case .enableSailingMode:
            updateConfig { cfg in
                cfg.sailingModeEnabled = true
                if let band = task.targetValue {
                    cfg.sailingDeadband = band
                }
            }
        case .setLowPowerMode:
            _ = setPowerMode(.lowPower)
        case .setNormalPowerMode:
            _ = setPowerMode(.normal)
        }
    }

    private func wireSleepCallbacks() {
        sleepController.onWillSleep = { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let stopOnSleep = self.config.stopChargingWhenSleeping
            let limit = self.config.chargeLimit
            let deadband = self.config.sailingDeadband
            self.lock.unlock()

            if stopOnSleep {
                _ = self.smcClient.setChargeInhibited(true)
                if self.helperClient.isConnected {
                    _ = self.helperClient.setChargeLimit(
                        limit,
                        sailingDeadband: deadband,
                        inhibitCharging: true,
                        forceDischarge: false
                    )
                }
            }
            self.historyStore.flushToDisk()
        }

        sleepController.onDidWake = { [weak self] in
            guard let self else { return }
            self.monitorQueue.async {
                self.runMissedScheduledTasksIfNeeded()
                _ = self.tick()
            }
        }
    }

    private func publishOnMain(_ updates: @escaping @Sendable () -> Void) {
        if Thread.isMainThread {
            updates()
        } else {
            DispatchQueue.main.async(execute: updates)
        }
    }

    // MARK: - Config Persistence

    private static func loadConfig(from url: URL) -> BatteryConfig? {
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(BatteryConfig.self, from: data)
    }

    private static func persistConfig(_ config: BatteryConfig, to url: URL) {
        do {
            let dir = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(config)
            try data.write(to: url, options: .atomic)
        } catch {
            // Non-fatal persistence failure; in-memory config remains authoritative.
        }
    }
}
