import AppIntents
import Foundation
import NudgeCore

// MARK: - MagSafe LED AppEnum

public enum MagSafeLEDAppOption: String, AppEnum, Sendable {
    case systemDefault
    case green
    case orange
    case blinkingOrange
    case off

    public static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "MagSafe LED Mode")
    }

    public static var caseDisplayRepresentations: [MagSafeLEDAppOption: DisplayRepresentation] {
        [
            .systemDefault: DisplayRepresentation(
                title: "System",
                subtitle: "Let macOS control the MagSafe LED"
            ),
            .green: DisplayRepresentation(
                title: "Green",
                subtitle: "Solid green indicator"
            ),
            .orange: DisplayRepresentation(
                title: "Orange",
                subtitle: "Solid amber/orange indicator"
            ),
            .blinkingOrange: DisplayRepresentation(
                title: "Blinking Orange",
                subtitle: "Pulsing orange indicator"
            ),
            .off: DisplayRepresentation(
                title: "Off",
                subtitle: "Turn off MagSafe LED"
            )
        ]
    }

    public var coreState: MagSafeLEDState {
        switch self {
        case .systemDefault: return .systemDefault
        case .green: return .green
        case .orange: return .orange
        case .blinkingOrange: return .blinkingOrange
        case .off: return .off
        }
    }

    public init(coreState: MagSafeLEDState) {
        switch coreState {
        case .systemDefault: self = .systemDefault
        case .green: self = .green
        case .orange: self = .orange
        case .blinkingOrange: self = .blinkingOrange
        case .off: self = .off
        }
    }
}

// MARK: - Power Mode AppEnum

public enum PowerModeAppOption: String, AppEnum, Sendable {
    case lowPower
    case normal
    case highPower

    public static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Power Mode")
    }

    public static var caseDisplayRepresentations: [PowerModeAppOption: DisplayRepresentation] {
        [
            .lowPower: DisplayRepresentation(
                title: "Low Power",
                subtitle: "Reduce energy usage to extend battery life"
            ),
            .normal: DisplayRepresentation(
                title: "Automatic",
                subtitle: "Balanced performance and battery efficiency"
            ),
            .highPower: DisplayRepresentation(
                title: "High Power",
                subtitle: "Maximize sustained performance on supported Macs"
            )
        ]
    }

    public var coreMode: PowerMode {
        switch self {
        case .lowPower: return .lowPower
        case .normal: return .normal
        case .highPower: return .highPower
        }
    }

    public init(coreMode: PowerMode) {
        switch coreMode {
        case .lowPower: self = .lowPower
        case .normal: self = .normal
        case .highPower: self = .highPower
        }
    }
}

// MARK: - Battery Status Entity

public struct BatteryStatusEntity: AppEntity, Sendable {
    public static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Battery Status")
    }

    public static var defaultQuery = BatteryStatusEntityQuery()

    public let id: String

    @Property(title: "Charge Percentage")
    public var displayPercentage: Int

    @Property(title: "Raw Hardware Percentage")
    public var rawHardwarePercentage: Double

    @Property(title: "Temperature (°C)")
    public var temperatureCelsius: Double

    @Property(title: "Charging State")
    public var state: String

    @Property(title: "Charger Input (W)")
    public var chargerInputWatts: Double

    @Property(title: "Battery Power (W)")
    public var batteryWatts: Double

    @Property(title: "System Load (W)")
    public var systemLoadWatts: Double

    @Property(title: "Charge Limit")
    public var chargeLimit: Int

    @Property(title: "Cycle Count")
    public var cycleCount: Int

    @Property(title: "Summary")
    public var summary: String

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(displayPercentage)% (\(state.capitalized))",
            subtitle: "Raw \(String(format: "%.1f", rawHardwarePercentage))% • \(String(format: "%.1f", temperatureCelsius))°C • \(String(format: "%.1f", systemLoadWatts))W"
        )
    }

    public init(from snapshot: BatterySnapshot, chargeLimit: Int) {
        self.id = "current-battery-status"
        self.displayPercentage = snapshot.displayPercentage
        self.rawHardwarePercentage = (snapshot.rawHardwarePercentage * 10).rounded() / 10
        self.temperatureCelsius = (snapshot.temperatureCelsius * 10).rounded() / 10
        self.state = snapshot.state.rawValue
        self.chargerInputWatts = (snapshot.powerFlow.chargerInputWatts * 10).rounded() / 10
        self.batteryWatts = (snapshot.powerFlow.batteryWatts * 10).rounded() / 10
        self.systemLoadWatts = (snapshot.powerFlow.systemLoadWatts * 10).rounded() / 10
        self.chargeLimit = chargeLimit
        self.cycleCount = snapshot.cycleCount
        self.summary = String(
            format: "Battery %d%% (Raw %.1f%%), %.1f°C, State: %@, Limit: %d%%, Power: Charger %.1fW / Battery %.1fW / System %.1fW",
            snapshot.displayPercentage,
            snapshot.rawHardwarePercentage,
            snapshot.temperatureCelsius,
            snapshot.state.rawValue.capitalized,
            chargeLimit,
            snapshot.powerFlow.chargerInputWatts,
            snapshot.powerFlow.batteryWatts,
            snapshot.powerFlow.systemLoadWatts
        )
    }

    public static func current() -> BatteryStatusEntity {
        let manager = BatteryManager.shared
        let tick = manager.tick()
        return BatteryStatusEntity(from: tick.snapshot, chargeLimit: manager.config.chargeLimit)
    }
}

public struct BatteryStatusEntityQuery: EntityQuery {
    public init() {}

    public func entities(for identifiers: [String]) async throws -> [BatteryStatusEntity] {
        [BatteryStatusEntity.current()]
    }

    public func suggestedEntities() async throws -> [BatteryStatusEntity] {
        [BatteryStatusEntity.current()]
    }
}
