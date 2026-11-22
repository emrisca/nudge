import Foundation

public enum ChargingState: String, Codable, Sendable {
    case charging
    case discharging
    case paused
    case unplugged
    case unknown
}

public enum PowerMode: String, Codable, Sendable {
    case normal
    case lowPower
    case highPower
}

public struct BatterySnapshot: Codable, Sendable {
    public let timestamp: Date
    public let rawPercentage: Double
    public let displayPercentage: Int
    public let temperatureCelsius: Double
    public let cycleCount: Int
    public let maxCapacityMah: Int
    public let currentCapacityMah: Int
    public let isPluggedIn: Bool
    public let isCharging: Bool
    public let chargerWattage: Double
    public let batteryWattage: Double
    public let systemWattage: Double
    public let state: ChargingState

    public init(
        timestamp: Date = Date(),
        rawPercentage: Double,
        displayPercentage: Int,
        temperatureCelsius: Double,
        cycleCount: Int,
        maxCapacityMah: Int,
        currentCapacityMah: Int,
        isPluggedIn: Bool,
        isCharging: Bool,
        chargerWattage: Double,
        batteryWattage: Double,
        systemWattage: Double,
        state: ChargingState
    ) {
        self.timestamp = timestamp
        self.rawPercentage = rawPercentage
        self.displayPercentage = displayPercentage
        self.temperatureCelsius = temperatureCelsius
        self.cycleCount = cycleCount
        self.maxCapacityMah = maxCapacityMah
        self.currentCapacityMah = currentCapacityMah
        self.isPluggedIn = isPluggedIn
        self.isCharging = isCharging
        self.chargerWattage = chargerWattage
        self.batteryWattage = batteryWattage
        self.systemWattage = systemWattage
        self.state = state
    }
}
