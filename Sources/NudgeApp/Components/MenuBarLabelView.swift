import SwiftUI
import NudgeCore

/// Clean icon-only macOS Menu Bar label reflecting live battery and charging state.
public struct MenuBarLabelView: View {
    @ObservedObject var manager: BatteryManager

    public init(manager: BatteryManager) {
        self.manager = manager
    }

    public var body: some View {
        Image(systemName: liveIconSymbol(for: manager.latestSnapshot))
            .symbolRenderingMode(.hierarchical)
            .accessibilityLabel("Nudge")
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
