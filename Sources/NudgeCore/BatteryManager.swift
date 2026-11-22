import Foundation

public struct BatteryConfig: Codable, Sendable {
    public var chargeLimit: Int = 80
    public var sailingDeadband: Int = 5
    public var heatProtectionEnabled: Bool = true
    public var heatThresholdCelsius: Double = 35.0
    public var automaticDischargeEnabled: Bool = false
    public var topUpActive: Bool = false
    public var stopChargingWhenSleeping: Bool = true
    public var disableSleepUntilChargeLimit: Bool = false

    public init() {}
}

public final class BatteryManager: @unchecked Sendable {
    public static let shared = BatteryManager()

    public var config: BatteryConfig
    public let heatProtection: HeatProtectionManager
    public let sailingEngine: SailingModeEngine
    public let calibrationEngine: CalibrationEngine
    public let smcClient: SMCClient
    public let powerReader: IOKitPowerReader

    private let lock = NSLock()

    public init(config: BatteryConfig = BatteryConfig()) {
        self.config = config
        self.heatProtection = HeatProtectionManager(thresholdCelsius: config.heatThresholdCelsius)
        self.sailingEngine = SailingModeEngine(targetLimit: config.chargeLimit, deadbandPercentage: config.sailingDeadband)
        self.calibrationEngine = CalibrationEngine(userTargetLimit: config.chargeLimit)
        self.smcClient = SMCClient.shared
        self.powerReader = IOKitPowerReader.shared
    }

    public func updateConfig(_ mutate: (inout BatteryConfig) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        mutate(&config)
        sailingEngine.targetLimit = config.chargeLimit
        sailingEngine.deadbandPercentage = config.sailingDeadband
    }

    public func tick() -> (snapshot: BatterySnapshot, chargingInhibited: Bool, forceDischarge: Bool) {
        lock.lock()
        defer { lock.unlock() }

        let snapshot = powerReader.readCurrentSnapshot()
        var chargingInhibited = false
        var forceDischarge = false

        // 1. Calibration mode check
        if calibrationEngine.currentPhase != .idle {
            let phase = calibrationEngine.processTick(currentPercentage: snapshot.displayPercentage, isPluggedIn: snapshot.isPluggedIn)
            switch phase {
            case .chargeToFull, .rechargeToFull:
                chargingInhibited = false
                forceDischarge = false
            case .dischargeToLow, .returnToTargetLimit:
                chargingInhibited = true
                forceDischarge = true
            case .idle:
                break
            }
            return (snapshot, chargingInhibited, forceDischarge)
        }

        // 2. Top-up override
        if config.topUpActive {
            if !snapshot.isPluggedIn {
                // Revert top-up upon physical unplug
                config.topUpActive = false
            } else if snapshot.displayPercentage >= 100 {
                chargingInhibited = true
            } else {
                chargingInhibited = false
                return (snapshot, chargingInhibited, forceDischarge)
            }
        }

        // 3. Heat Protection
        if config.heatProtectionEnabled {
            let overheat = heatProtection.evaluateTemperature(snapshot.temperatureCelsius)
            if overheat {
                chargingInhibited = true
                _ = smcClient.setChargeInhibited(true)
                return (snapshot, chargingInhibited, forceDischarge)
            }
        }

        // 4. Sailing Mode / Charge Limiter
        let shouldSail = sailingEngine.evaluateCharging(currentPercentage: snapshot.displayPercentage)
        if shouldSail {
            chargingInhibited = true
        }

        // 5. Automatic Discharge
        if config.automaticDischargeEnabled && snapshot.displayPercentage > config.chargeLimit {
            forceDischarge = true
        }

        _ = smcClient.setChargeInhibited(chargingInhibited)
        _ = smcClient.setForceDischarge(forceDischarge)

        return (snapshot, chargingInhibited, forceDischarge)
    }
}
