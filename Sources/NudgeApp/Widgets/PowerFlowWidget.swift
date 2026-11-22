import SwiftUI
import NudgeCore

public struct PowerFlowWidget: View {
    @Environment(\.nudgePalette) private var palette
    @ObservedObject var manager: BatteryManager

    public init(manager: BatteryManager) {
        self.manager = manager
    }

    private var snapshot: BatterySnapshot { manager.latestSnapshot }
    private var flow: PowerFlowBreakdown { snapshot.powerFlow }

    private var chargerToSystemActive: Bool {
        snapshot.isPluggedIn && flow.chargerInputWatts > 0.3
    }

    private var batteryDirection: FlowDirection {
        if flow.batteryWatts > 0.25 { return .forward }   // System/Charger -> Battery (charging)
        if flow.batteryWatts < -0.25 { return .reverse }  // Battery -> System (discharging)
        return .idle
    }

    public var body: some View {
        NudgeCard(
            title: "Power Flow",
            subtitle: snapshot.isPluggedIn ? "AC Adapter & Thermal Distribution" : "Battery Delivery Telemetry",
            symbol: "bolt.horizontal.fill",
            headerTrailing: {
                NudgeTagPill(
                    String(format: "%.1fW Load", flow.systemLoadWatts),
                    style: .accent
                )
            }
        ) {
            VStack(spacing: 14) {
                // 3-Node Directional Flow Diagram
                HStack(spacing: 0) {
                    flowNode(
                        title: "Adapter",
                        value: String(format: "%.1fW", flow.chargerInputWatts),
                        caption: snapshot.isPluggedIn ? "Max \(snapshot.adapterMaxWatts)W" : "Unplugged",
                        symbol: "powerplug.fill",
                        isActive: chargerToSystemActive,
                        accentColor: palette.primary
                    )

                    FlowConnector(
                        direction: chargerToSystemActive ? .forward : .idle,
                        color: palette.primary
                    )

                    flowNode(
                        title: "System",
                        value: String(format: "%.1fW", flow.systemLoadWatts),
                        caption: "Total Draw",
                        symbol: "laptopcomputer",
                        isActive: true,
                        accentColor: palette.chart2
                    )

                    FlowConnector(
                        direction: batteryDirection,
                        color: batteryDirection == .forward ? palette.primary : palette.warning
                    )

                    flowNode(
                        title: "Battery",
                        value: String(format: "%+.1fW", flow.batteryWatts),
                        caption: batteryCaption,
                        symbol: batteryDirection == .forward ? "battery.100percent.bolt" : "battery.75percent",
                        isActive: batteryDirection != .idle,
                        accentColor: batteryDirection == .forward ? palette.primary : (batteryDirection == .reverse ? palette.warning : palette.mutedForeground)
                    )
                }

                NudgeSectionDivider()

                // System Load Breakdown Bars (SoC / Display / USB & Peripherals)
                VStack(spacing: 8) {
                    let denom = max(1.0, flow.systemLoadWatts)
                    breakdownRow(
                        label: "Apple Silicon / SoC",
                        watts: flow.socWatts,
                        fraction: flow.socWatts / denom,
                        color: palette.chart1
                    )
                    breakdownRow(
                        label: "Display & Backlight",
                        watts: flow.displayWatts,
                        fraction: flow.displayWatts / denom,
                        color: palette.chart3
                    )
                    breakdownRow(
                        label: "USB & Peripherals",
                        watts: flow.usbAndPeripheralsWatts,
                        fraction: flow.usbAndPeripheralsWatts / denom,
                        color: palette.chart2
                    )
                }
            }
        }
    }

    private var batteryCaption: String {
        if flow.batteryWatts > 0.25 { return "Charging" }
        if flow.batteryWatts < -0.25 { return "Draining" }
        return "Bypassed"
    }

    private func flowNode(
        title: String,
        value: String,
        caption: String,
        symbol: String,
        isActive: Bool,
        accentColor: Color
    ) -> some View {
        VStack(spacing: 5) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(isActive ? accentColor.opacity(palette.isDark ? 0.22 : 0.28) : palette.muted)
                    .frame(width: 38, height: 38)
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(isActive ? accentColor : palette.border, lineWidth: isActive ? 1.5 : 1)
                    )

                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isActive ? (accentColor == palette.primary && !palette.isDark ? palette.primaryForeground : accentColor) : palette.mutedForeground)
            }

            Text(title)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(palette.mutedForeground)

            Text(value)
                .nudgeMetricFont(size: 13.5, weight: .bold)
                .foregroundStyle(palette.foreground)

            Text(caption)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(palette.mutedForeground)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private func breakdownRow(label: String, watts: Double, fraction: Double, color: Color) -> some View {
        let clamped = min(1.0, max(0.0, fraction))
        return VStack(spacing: 4) {
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(color)
                        .frame(width: 7, height: 7)
                    Text(label)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(palette.foreground)
                }
                Spacer()
                Text(String(format: "%.1f W", watts))
                    .nudgeMetricFont(size: 11.5, weight: .semibold)
                    .foregroundStyle(palette.foreground)
                Text(String(format: "(%d%%)", Int(round(clamped * 100))))
                    .nudgeMetricFont(size: 10.5, weight: .regular)
                    .foregroundStyle(palette.mutedForeground)
                    .frame(width: 38, alignment: .trailing)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(palette.muted)
                    Capsule(style: .continuous)
                        .fill(color)
                        .frame(width: max(4, geo.size.width * clamped))
                        .animation(.easeOut(duration: 0.3), value: clamped)
                }
            }
            .frame(height: 5)
        }
    }
}

private enum FlowDirection {
    case forward
    case reverse
    case idle
}

private struct FlowConnector: View {
    @Environment(\.nudgePalette) private var palette
    let direction: FlowDirection
    let color: Color

    @State private var pulseStep: Int = 0

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.45)) { context in
            let tick = Int(context.date.timeIntervalSinceReferenceDate / 0.45) % 3
            HStack(spacing: 2) {
                ForEach(0..<3, id: \.self) { idx in
                    let activeIdx = direction == .reverse ? (2 - tick) : tick
                    let isLit = direction != .idle && idx == activeIdx
                    Image(systemName: direction == .reverse ? "chevron.left" : "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(
                            direction == .idle
                                ? palette.border
                                : color.opacity(isLit ? 1.0 : 0.30)
                        )
                }
            }
            .frame(width: 34)
            .padding(.bottom, 22)
        }
    }
}
