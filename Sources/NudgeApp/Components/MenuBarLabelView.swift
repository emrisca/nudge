import SwiftUI
import NudgeCore

/// Dynamic macOS Menu Bar label rendering user-reorderable live telemetry and state icon.
public struct MenuBarLabelView: View {
    @ObservedObject var manager: BatteryManager

    public init(manager: BatteryManager) {
        self.manager = manager
    }

    public var body: some View {
        let components = manager.config.menuBarComponents.isEmpty
            ? [.liveIcon, .displayPercentage]
            : manager.config.menuBarComponents
        let snapshot = manager.latestSnapshot

        HStack(spacing: 5) {
            ForEach(components) { component in
                componentView(for: component, snapshot: snapshot)
            }
        }
        .font(.system(size: 12, weight: .medium))
        .monospacedDigit()
    }

    @ViewBuilder
    private func componentView(for component: MenuBarComponent, snapshot: BatterySnapshot) -> some View {
        switch component {
        case .liveIcon:
            Image(systemName: liveIconSymbol(for: snapshot))
                .symbolRenderingMode(.hierarchical)
        case .displayPercentage:
            Text("\(snapshot.displayPercentage)%")
        case .hardwarePercentage:
            Text(String(format: "HW %.0f%%", snapshot.rawHardwarePercentage))
        case .temperature:
            Text(String(format: "%.1f°C", snapshot.temperatureCelsius))
        case .powerFlow:
            let watts = snapshot.powerFlow.batteryWatts
            if abs(watts) < 0.2 {
                Text(String(format: "%.0fW", snapshot.powerFlow.systemLoadWatts))
            } else {
                Text(String(format: "%+.1fW", watts))
            }
        case .cycles:
            Text("\(snapshot.cycleCount)c")
        case .maxCapacity:
            Text("\(Int(round(snapshot.healthPercentage)))%♥")
        }
    }

    private func liveIconSymbol(for snapshot: BatterySnapshot) -> String {
        switch snapshot.state {
        case .charging:
            return "bolt.batteryblock.fill"
        case .paused:
            return "pause.circle.fill"
        case .sailing:
            return "wind"
        case .discharging:
            return "arrow.down.circle.fill"
        case .overheated:
            return "thermometer.sun.fill"
        case .calibrating:
            return "arrow.triangle.2.circlepath"
        case .unplugged, .unknown:
            switch snapshot.displayPercentage {
            case 88...100: return "battery.100percent"
            case 63..<88: return "battery.75percent"
            case 38..<63: return "battery.50percent"
            case 13..<38: return "battery.25percent"
            default: return "battery.0percent"
            }
        }
    }
}
