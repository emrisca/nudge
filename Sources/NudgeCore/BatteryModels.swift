import Foundation

// MARK: - Core Battery & Power States

public enum ChargingState: String, Codable, Sendable, CaseIterable {
    case charging
    case discharging
    case paused
    case sailing
    case overheated
    case calibrating
    case unplugged
    case unknown
}

public enum PowerMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case lowPower = "Low Power"
    case normal = "Automatic"
    case highPower = "High Power"

    public var id: String { rawValue }
}

public enum MagSafeLEDState: String, Codable, Sendable, CaseIterable, Identifiable {
    case systemDefault = "System"
    case green = "Green"
    case orange = "Orange"
    case blinkingOrange = "Blinking Orange"
    case off = "Off"

    public var id: String { rawValue }
}

public enum ArchitectureType: String, Codable, Sendable {
    case appleSilicon = "Apple Silicon"
    case intel = "Intel"
}

// MARK: - Power Flow Breakdown

public struct PowerFlowBreakdown: Codable, Sendable, Equatable {
    public let chargerInputWatts: Double
    public let batteryWatts: Double       // positive = charging, negative = discharging
    public let systemLoadWatts: Double
    public let socWatts: Double
    public let displayWatts: Double
    public let usbAndPeripheralsWatts: Double

    public init(
        chargerInputWatts: Double,
        batteryWatts: Double,
        systemLoadWatts: Double,
        socWatts: Double,
        displayWatts: Double,
        usbAndPeripheralsWatts: Double
    ) {
        self.chargerInputWatts = chargerInputWatts
        self.batteryWatts = batteryWatts
        self.systemLoadWatts = systemLoadWatts
        self.socWatts = socWatts
        self.displayWatts = displayWatts
        self.usbAndPeripheralsWatts = usbAndPeripheralsWatts
    }
}

// MARK: - Battery Telemetry Snapshot

public struct BatterySnapshot: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let rawHardwarePercentage: Double
    public let displayPercentage: Int
    public let temperatureCelsius: Double
    public let cycleCount: Int
    public let designCapacityMah: Int
    public let maxCapacityMah: Int
    public let currentCapacityMah: Int
    public let voltageVolts: Double
    public let amperageAmps: Double
    public let isPluggedIn: Bool
    public let isCharging: Bool
    public let adapterMaxWatts: Int
    public let timeRemainingMinutes: Int?
    public let powerFlow: PowerFlowBreakdown
    public let state: ChargingState
    public let architecture: ArchitectureType

    public var healthPercentage: Double {
        guard designCapacityMah > 0 else { return 100.0 }
        return min(100.0, (Double(maxCapacityMah) / Double(designCapacityMah)) * 100.0)
    }

    // Convenience aliases
    public var rawPercentage: Double { rawHardwarePercentage }
    public var chargerWattage: Double { powerFlow.chargerInputWatts }
    public var batteryWattage: Double { powerFlow.batteryWatts }
    public var systemWattage: Double { powerFlow.systemLoadWatts }

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        rawHardwarePercentage: Double,
        displayPercentage: Int,
        temperatureCelsius: Double,
        cycleCount: Int,
        designCapacityMah: Int = 5100,
        maxCapacityMah: Int,
        currentCapacityMah: Int,
        voltageVolts: Double = 12.2,
        amperageAmps: Double = 0.0,
        isPluggedIn: Bool,
        isCharging: Bool,
        adapterMaxWatts: Int = 67,
        timeRemainingMinutes: Int? = nil,
        powerFlow: PowerFlowBreakdown,
        state: ChargingState,
        architecture: ArchitectureType = .appleSilicon
    ) {
        self.id = id
        self.timestamp = timestamp
        self.rawHardwarePercentage = rawHardwarePercentage
        self.displayPercentage = displayPercentage
        self.temperatureCelsius = temperatureCelsius
        self.cycleCount = cycleCount
        self.designCapacityMah = designCapacityMah
        self.maxCapacityMah = maxCapacityMah
        self.currentCapacityMah = currentCapacityMah
        self.voltageVolts = voltageVolts
        self.amperageAmps = amperageAmps
        self.isPluggedIn = isPluggedIn
        self.isCharging = isCharging
        self.adapterMaxWatts = adapterMaxWatts
        self.timeRemainingMinutes = timeRemainingMinutes
        self.powerFlow = powerFlow
        self.state = state
        self.architecture = architecture
    }
}

// MARK: - Historical Data Point for Swift Charts

public struct BatteryHistoryPoint: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let displayPercentage: Int
    public let hardwarePercentage: Double
    public let temperatureCelsius: Double
    public let chargerWatts: Double
    public let batteryWatts: Double
    public let systemWatts: Double

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        displayPercentage: Int,
        hardwarePercentage: Double,
        temperatureCelsius: Double,
        chargerWatts: Double,
        batteryWatts: Double,
        systemWatts: Double
    ) {
        self.id = id
        self.timestamp = timestamp
        self.displayPercentage = displayPercentage
        self.hardwarePercentage = hardwarePercentage
        self.temperatureCelsius = temperatureCelsius
        self.chargerWatts = chargerWatts
        self.batteryWatts = batteryWatts
        self.systemWatts = systemWatts
    }
}

// MARK: - High Energy App Model

public struct HighEnergyApp: Codable, Sendable, Identifiable, Equatable {
    public let id: Int32 // pid
    public let name: String
    public let bundleIdentifier: String?
    public let cpuPercent: Double
    public let energyImpactScore: Double // 0..100+ normalized score
    public let estimatedWatts: Double
    public let memoryMB: Double

    public init(
        id: Int32,
        name: String,
        bundleIdentifier: String?,
        cpuPercent: Double,
        energyImpactScore: Double,
        estimatedWatts: Double,
        memoryMB: Double
    ) {
        self.id = id
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.cpuPercent = cpuPercent
        self.energyImpactScore = energyImpactScore
        self.estimatedWatts = estimatedWatts
        self.memoryMB = memoryMB
    }
}

// MARK: - Scheduled Task Model

public enum ScheduledActionType: String, Codable, Sendable, CaseIterable, Identifiable {
    case setChargeLimit = "Set Charge Limit"
    case startTopUp = "Start Top Up (100%)"
    case startDischarge = "Start Discharge"
    case stopDischarge = "Stop Discharge"
    case startCalibration = "Start Calibration"
    case enableSailingMode = "Enable Sailing Mode"
    case setLowPowerMode = "Low Power Mode"
    case setNormalPowerMode = "Automatic Power Mode"

    public var id: String { rawValue }
}

public struct ScheduledTask: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public var name: String
    public var action: ScheduledActionType
    public var targetValue: Int?        // e.g. charge limit percentage
    public var hour: Int                // 0...23
    public var minute: Int              // 0...59
    public var weekdays: [Int]          // 1 = Sunday ... 7 = Saturday; empty = daily
    public var isEnabled: Bool
    public var catchUpIfMissed: Bool
    public var lastExecutedAt: Date?

    public init(
        id: UUID = UUID(),
        name: String,
        action: ScheduledActionType,
        targetValue: Int? = nil,
        hour: Int,
        minute: Int,
        weekdays: [Int] = [],
        isEnabled: Bool = true,
        catchUpIfMissed: Bool = true,
        lastExecutedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.action = action
        self.targetValue = targetValue
        self.hour = hour
        self.minute = minute
        self.weekdays = weekdays
        self.isEnabled = isEnabled
        self.catchUpIfMissed = catchUpIfMissed
        self.lastExecutedAt = lastExecutedAt
    }
}

// MARK: - Sleep Control Configuration

public struct SleepControlState: Codable, Sendable, Equatable {
    public var keepAwakeActive: Bool
    public var disableSleepUntilChargeLimit: Bool
    public var expiresAt: Date?
    public var fallbackBatteryPercent: Int // e.g., re-enable sleep at 20%
    public var reenableOnUnplug: Bool

    public init(
        keepAwakeActive: Bool = false,
        disableSleepUntilChargeLimit: Bool = false,
        expiresAt: Date? = nil,
        fallbackBatteryPercent: Int = 20,
        reenableOnUnplug: Bool = true
    ) {
        self.keepAwakeActive = keepAwakeActive
        self.disableSleepUntilChargeLimit = disableSleepUntilChargeLimit
        self.expiresAt = expiresAt
        self.fallbackBatteryPercent = fallbackBatteryPercent
        self.reenableOnUnplug = reenableOnUnplug
    }
}

// MARK: - Menu Bar & Popover Customization

public enum MenuBarComponent: String, Codable, Sendable, CaseIterable, Identifiable {
    case liveIcon = "Live Status Icon"
    case displayPercentage = "macOS %"
    case hardwarePercentage = "Hardware %"
    case temperature = "Temperature"
    case powerFlow = "Power Flow (W)"
    case cycles = "Cycle Count"
    case maxCapacity = "Battery Health %"

    public var id: String { rawValue }
}

public enum PopoverWidgetKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case chargeControl = "Charge Limiter & Quick Actions"
    case powerFlow = "Power Flow Telemetry"
    case historicalCharts = "Historical Graphs"
    case batterySpecs = "Hardware Specs & Health"
    case highEnergyApps = "Apps Using Significant Energy"
    case sleepAndPowerMode = "Sleep & Power Mode Control"
    case schedule = "Schedule & Automations"
    case calibrationAndLED = "Calibration & MagSafe LED"

    public var id: String { rawValue }
}

// MARK: - Complete Persistent Config

public struct BatteryConfig: Codable, Sendable, Equatable {
    public var chargeLimit: Int = 80
    public var sailingModeEnabled: Bool = true
    public var sailingDeadband: Int = 5
    public var heatProtectionEnabled: Bool = true
    public var heatThresholdCelsius: Double = 35.0
    public var automaticDischargeEnabled: Bool = false
    public var manualDischargeActive: Bool = false
    public var topUpActive: Bool = false
    public var stopChargingWhenSleeping: Bool = true
    public var stopChargingWhenAppClosed: Bool = true
    public var disableSleepUntilChargeLimit: Bool = false
    public var keepAwakeFallbackPercent: Int = 20
    public var keepAwakeReenableOnUnplug: Bool = true
    public var magSafeLEDMode: MagSafeLEDState = .systemDefault
    public var syncMagSafeLEDWithState: Bool = true
    public var showHardwarePercentage: Bool = true
    public var catchUpMissedTasks: Bool = true
    public var preferredPowerMode: PowerMode = .normal
    public var menuBarComponents: [MenuBarComponent] = [.liveIcon, .displayPercentage, .powerFlow]
    public var popoverWidgetOrder: [PopoverWidgetKind] = PopoverWidgetKind.allCases
    public var hiddenPopoverWidgets: [PopoverWidgetKind] = []
    public var appearancePreference: String = "system" // "system", "light", "dark"

    public init() {}
}

// MARK: - Daemon XPC Status

public struct HelperDaemonStatus: Codable, Sendable, Equatable {
    public let isInstalled: Bool
    public let isConnected: Bool
    public let version: String
    public let lastHeartbeat: Date?
    public let enforcedLimit: Int?
    public let fastUserSwitchingProtected: Bool

    public init(
        isInstalled: Bool,
        isConnected: Bool,
        version: String = "1.0.0",
        lastHeartbeat: Date? = nil,
        enforcedLimit: Int? = nil,
        fastUserSwitchingProtected: Bool = true
    ) {
        self.isInstalled = isInstalled
        self.isConnected = isConnected
        self.version = version
        self.lastHeartbeat = lastHeartbeat
        self.enforcedLimit = enforcedLimit
        self.fastUserSwitchingProtected = fastUserSwitchingProtected
    }
}

// MARK: - Tick Result

public struct BatteryTickResult: Sendable, Equatable {
    public let snapshot: BatterySnapshot
    public let chargingInhibited: Bool
    public let forceDischarge: Bool
    public let heatProtectionActive: Bool
    public let heatCooldownRemainingSeconds: TimeInterval
    public let sailingActive: Bool
    public let calibrationPhase: CalibrationPhase
    public let activeMagSafeLED: MagSafeLEDState
    public let sleepAssertionActive: Bool

    public init(
        snapshot: BatterySnapshot,
        chargingInhibited: Bool,
        forceDischarge: Bool,
        heatProtectionActive: Bool,
        heatCooldownRemainingSeconds: TimeInterval,
        sailingActive: Bool,
        calibrationPhase: CalibrationPhase,
        activeMagSafeLED: MagSafeLEDState,
        sleepAssertionActive: Bool
    ) {
        self.snapshot = snapshot
        self.chargingInhibited = chargingInhibited
        self.forceDischarge = forceDischarge
        self.heatProtectionActive = heatProtectionActive
        self.heatCooldownRemainingSeconds = heatCooldownRemainingSeconds
        self.sailingActive = sailingActive
        self.calibrationPhase = calibrationPhase
        self.activeMagSafeLED = activeMagSafeLED
        self.sleepAssertionActive = sleepAssertionActive
    }
}
