import AppIntents
import Foundation
import NudgeCore

// MARK: - Telemetry Intents

public struct GetBatteryStatusIntent: AppIntent {
    public static var title: LocalizedStringResource = "Get Battery Status"
    public static var description = IntentDescription(
        "Returns current battery charge percentage, raw hardware percentage, temperature, state, and power flow watts."
    )
    public static var openAppWhenRun: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult & ReturnsValue<BatteryStatusEntity> & ProvidesDialog {
        let entity = BatteryStatusEntity.current()
        return .result(value: entity, dialog: IntentDialog(stringLiteral: entity.summary))
    }
}

public struct GetChargeLimitIntent: AppIntent {
    public static var title: LocalizedStringResource = "Get Charge Limit"
    public static var description = IntentDescription(
        "Returns the currently configured battery charge limit percentage."
    )
    public static var openAppWhenRun: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        let limit = BatteryManager.shared.config.chargeLimit
        return .result(
            value: limit,
            dialog: IntentDialog("Your battery charge limit is set to \(limit)%.")
        )
    }
}

public struct GetBatteryTemperatureIntent: AppIntent {
    public static var title: LocalizedStringResource = "Get Battery Temperature"
    public static var description = IntentDescription(
        "Returns the current battery temperature in degrees Celsius."
    )
    public static var openAppWhenRun: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult & ReturnsValue<Double> & ProvidesDialog {
        let snapshot = BatteryManager.shared.tick().snapshot
        let rounded = (snapshot.temperatureCelsius * 10).rounded() / 10
        return .result(
            value: rounded,
            dialog: IntentDialog(stringLiteral: String(format: "Battery temperature is %.1f°C.", rounded))
        )
    }
}

// MARK: - Charge Limit & Override Intents

public struct SetChargeLimitIntent: AppIntent {
    public static var title: LocalizedStringResource = "Set Charge Limit"
    public static var description = IntentDescription(
        "Sets the maximum battery charge limit between 20% and 100%."
    )
    public static var openAppWhenRun: Bool = false

    @Parameter(title: "Charge Limit", inclusiveRange: (20, 100))
    public var limit: Int

    public init() {
        self.limit = 80
    }

    public init(limit: Int) {
        self.limit = limit
    }

    public static var parameterSummary: some ParameterSummary {
        Summary("Set battery charge limit to \(\.$limit)%")
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        let clamped = max(20, min(100, limit))
        BatteryManager.shared.setChargeLimit(clamped)
        _ = BatteryManager.shared.tick()
        return .result(
            value: clamped,
            dialog: IntentDialog("Battery charge limit set to \(clamped)%.")
        )
    }
}

public struct StartDischargeIntent: AppIntent {
    public static var title: LocalizedStringResource = "Start Battery Discharge"
    public static var description = IntentDescription(
        "Forces the Mac to run on battery power even while connected to a charger."
    )
    public static var openAppWhenRun: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        BatteryManager.shared.setManualDischarge(true)
        _ = BatteryManager.shared.tick()
        return .result(dialog: IntentDialog("Manual battery discharge started."))
    }
}

public struct StopDischargeIntent: AppIntent {
    public static var title: LocalizedStringResource = "Stop Battery Discharge"
    public static var description = IntentDescription(
        "Stops forced battery discharge and returns to normal charge limit management."
    )
    public static var openAppWhenRun: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        BatteryManager.shared.setManualDischarge(false)
        _ = BatteryManager.shared.tick()
        return .result(dialog: IntentDialog("Manual battery discharge stopped."))
    }
}

public struct StartTopUpIntent: AppIntent {
    public static var title: LocalizedStringResource = "Start Top Up"
    public static var description = IntentDescription(
        "Temporarily overrides the charge limit to charge the battery to 100% until unplugged."
    )
    public static var openAppWhenRun: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        BatteryManager.shared.setTopUp(true)
        _ = BatteryManager.shared.tick()
        return .result(dialog: IntentDialog("Top Up started. Charging to 100%."))
    }
}

public struct StopTopUpIntent: AppIntent {
    public static var title: LocalizedStringResource = "Stop Top Up"
    public static var description = IntentDescription(
        "Cancels Top Up mode and returns to your configured charge limit."
    )
    public static var openAppWhenRun: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        BatteryManager.shared.setTopUp(false)
        _ = BatteryManager.shared.tick()
        let limit = BatteryManager.shared.config.chargeLimit
        return .result(dialog: IntentDialog("Top Up stopped. Charge limit restored to \(limit)%."))
    }
}

// MARK: - Calibration Intents

public struct StartCalibrationIntent: AppIntent {
    public static var title: LocalizedStringResource = "Start Battery Calibration"
    public static var description = IntentDescription(
        "Starts the 4-phase battery calibration cycle (100% -> 10% -> 100% -> target limit)."
    )
    public static var openAppWhenRun: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        BatteryManager.shared.startCalibration()
        _ = BatteryManager.shared.tick()
        return .result(dialog: IntentDialog("Battery calibration started."))
    }
}

public struct CancelCalibrationIntent: AppIntent {
    public static var title: LocalizedStringResource = "Cancel Battery Calibration"
    public static var description = IntentDescription(
        "Cancels an active battery calibration cycle and restores normal charge limiting."
    )
    public static var openAppWhenRun: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        BatteryManager.shared.cancelCalibration()
        _ = BatteryManager.shared.tick()
        return .result(dialog: IntentDialog("Battery calibration canceled."))
    }
}

// MARK: - Sailing Mode & Heat Protection Intents

public struct ToggleSailingModeIntent: AppIntent {
    public static var title: LocalizedStringResource = "Toggle Sailing Mode"
    public static var description = IntentDescription(
        "Enables or disables Sailing Mode hysteresis and optionally sets the deadband percentage."
    )
    public static var openAppWhenRun: Bool = false

    @Parameter(title: "Enabled")
    public var enabled: Bool

    @Parameter(title: "Deadband (%)", inclusiveRange: (1, 20))
    public var deadband: Int?

    public init() {
        self.enabled = true
        self.deadband = nil
    }

    public init(enabled: Bool, deadband: Int? = nil) {
        self.enabled = enabled
        self.deadband = deadband
    }

    public static var parameterSummary: some ParameterSummary {
        Summary("Set Sailing Mode enabled to \(\.$enabled)") {
            \.$deadband
        }
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let clampedDeadband = deadband.map { max(1, min(20, $0)) }
        BatteryManager.shared.updateConfig { config in
            config.sailingModeEnabled = enabled
            if let clampedDeadband {
                config.sailingDeadband = clampedDeadband
            }
        }
        _ = BatteryManager.shared.tick()

        let activeDeadband = BatteryManager.shared.config.sailingDeadband
        let message = enabled
            ? "Sailing Mode enabled with \(activeDeadband)% deadband."
            : "Sailing Mode disabled."
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

public struct ToggleHeatProtectionIntent: AppIntent {
    public static var title: LocalizedStringResource = "Toggle Heat Protection"
    public static var description = IntentDescription(
        "Enables or disables automatic charging pause when battery temperature exceeds the threshold."
    )
    public static var openAppWhenRun: Bool = false

    @Parameter(title: "Enabled")
    public var enabled: Bool

    @Parameter(title: "Threshold (°C)", inclusiveRange: (25.0, 50.0))
    public var threshold: Double?

    public init() {
        self.enabled = true
        self.threshold = nil
    }

    public init(enabled: Bool, threshold: Double? = nil) {
        self.enabled = enabled
        self.threshold = threshold
    }

    public static var parameterSummary: some ParameterSummary {
        Summary("Set Heat Protection enabled to \(\.$enabled)") {
            \.$threshold
        }
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let clampedThreshold = threshold.map { max(25.0, min(50.0, $0)) }
        BatteryManager.shared.updateConfig { config in
            config.heatProtectionEnabled = enabled
            if let clampedThreshold {
                config.heatThresholdCelsius = clampedThreshold
            }
        }
        _ = BatteryManager.shared.tick()

        let activeThreshold = BatteryManager.shared.config.heatThresholdCelsius
        let message = enabled
            ? String(format: "Heat Protection enabled at %.1f°C.", activeThreshold)
            : "Heat Protection disabled."
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

// MARK: - MagSafe LED, Power Mode & Keep Awake Intents

public struct SetMagSafeLEDIntent: AppIntent {
    public static var title: LocalizedStringResource = "Set MagSafe LED"
    public static var description = IntentDescription(
        "Sets the MagSafe charger LED color or returns control to macOS."
    )
    public static var openAppWhenRun: Bool = false

    @Parameter(title: "LED Mode")
    public var mode: MagSafeLEDAppOption

    public init() {
        self.mode = .systemDefault
    }

    public init(mode: MagSafeLEDAppOption) {
        self.mode = mode
    }

    public static var parameterSummary: some ParameterSummary {
        Summary("Set MagSafe LED to \(\.$mode)")
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let coreState = mode.coreState
        BatteryManager.shared.setMagSafeLED(coreState)
        return .result(dialog: IntentDialog("MagSafe LED set to \(coreState.rawValue)."))
    }
}

public struct SetPowerModeIntent: AppIntent {
    public static var title: LocalizedStringResource = "Set Power Mode"
    public static var description = IntentDescription(
        "Switches macOS Power Mode between Low Power, Automatic, and High Power."
    )
    public static var openAppWhenRun: Bool = false

    @Parameter(title: "Power Mode")
    public var mode: PowerModeAppOption

    public init() {
        self.mode = .normal
    }

    public init(mode: PowerModeAppOption) {
        self.mode = mode
    }

    public static var parameterSummary: some ParameterSummary {
        Summary("Set Power Mode to \(\.$mode)")
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<Bool> & ProvidesDialog {
        let coreMode = mode.coreMode
        let succeeded = BatteryManager.shared.setPowerMode(coreMode)
        let message = succeeded
            ? "Power Mode set to \(coreMode.rawValue)."
            : "Power Mode preference updated to \(coreMode.rawValue) (system pmset requires elevated privileges)."
        return .result(value: succeeded, dialog: IntentDialog(stringLiteral: message))
    }
}

public struct KeepAwakeIntent: AppIntent {
    public static var title: LocalizedStringResource = "Keep Mac Awake"
    public static var description = IntentDescription(
        "Prevents your Mac from sleeping for a set duration, indefinitely if omitted, or disables Keep Awake when 0."
    )
    public static var openAppWhenRun: Bool = false

    @Parameter(title: "Duration (Minutes)")
    public var minutes: Int?

    public init() {
        self.minutes = nil
    }

    public init(minutes: Int?) {
        self.minutes = minutes
    }

    public static var parameterSummary: some ParameterSummary {
        Summary("Keep Mac awake for \(\.$minutes) minutes")
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let manager = BatteryManager.shared
        if let minutes, minutes <= 0 {
            manager.disableKeepAwake()
            return .result(dialog: IntentDialog("Keep Awake disabled. Normal sleep resumed."))
        }

        let config = manager.config
        manager.enableTimedKeepAwake(
            minutes: minutes,
            fallbackBatteryPercent: config.keepAwakeFallbackPercent,
            reenableOnUnplug: config.keepAwakeReenableOnUnplug
        )

        if let minutes {
            return .result(dialog: IntentDialog("Keeping Mac awake for \(minutes) minutes."))
        } else {
            return .result(dialog: IntentDialog("Keeping Mac awake until disabled or safety fallback triggers."))
        }
    }
}
