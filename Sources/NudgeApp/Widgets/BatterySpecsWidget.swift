import SwiftUI
import NudgeCore

public struct BatterySpecsWidget: View {
    @Environment(\.nudgePalette) private var palette
    @ObservedObject var manager: BatteryManager

    public init(manager: BatteryManager) {
        self.manager = manager
    }

    private var snapshot: BatterySnapshot { manager.latestSnapshot }
    private var daemon: HelperDaemonStatus { manager.daemonStatus }

    public var body: some View {
        NudgeCard(
            title: "Hardware Specs & Health",
            subtitle: "IOKit SmartBattery & SMC Telemetry",
            symbol: "cpu.fill",
            headerTrailing: {
                NudgeTagPill(
                    snapshot.architecture.rawValue,
                    symbol: snapshot.architecture == .appleSilicon ? "applelogo" : "cpu",
                    style: .muted
                )
            }
        ) {
            VStack(spacing: 12) {
                // 2-Column Metric Grid
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    specTile(
                        label: "macOS vs Hardware",
                        value: "\(snapshot.displayPercentage)% / \(String(format: "%.1f%%", snapshot.rawHardwarePercentage))",
                        icon: "percent"
                    )
                    specTile(
                        label: "Battery Health",
                        value: String(format: "%.1f%%", snapshot.healthPercentage),
                        icon: "heart.fill",
                        highlight: snapshot.healthPercentage >= 80
                    )
                    specTile(
                        label: "Cycle Count",
                        value: "\(snapshot.cycleCount) cycles",
                        icon: "arrow.2.squarepath"
                    )
                    specTile(
                        label: "Voltage / Current",
                        value: String(format: "%.2fV · %+.2fA", snapshot.voltageVolts, snapshot.amperageAmps),
                        icon: "waveform.path.ecg"
                    )
                }

                // Capacity Comparison Bar (Current / Max / Design mAh)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Cell Capacity")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.foreground)
                        Spacer()
                        Text("\(snapshot.currentCapacityMah) / \(snapshot.maxCapacityMah) mAh")
                            .nudgeMetricFont(size: 11, weight: .semibold)
                            .foregroundStyle(palette.foreground)
                    }

                    GeometryReader { geo in
                        let design = max(1.0, Double(snapshot.designCapacityMah))
                        let maxRatio = min(1.0, Double(snapshot.maxCapacityMah) / design)
                        let currentRatio = min(maxRatio, Double(snapshot.currentCapacityMah) / design)

                        ZStack(alignment: .leading) {
                            Capsule(style: .continuous)
                                .fill(palette.muted)
                            Capsule(style: .continuous)
                                .fill(palette.chart3.opacity(0.28))
                                .frame(width: max(4, geo.size.width * maxRatio))
                            Capsule(style: .continuous)
                                .fill(palette.primary)
                                .frame(width: max(4, geo.size.width * currentRatio))
                        }
                    }
                    .frame(height: 7)

                    HStack {
                        Text("Design: \(snapshot.designCapacityMah) mAh")
                        Spacer()
                        Text("Max FCC: \(snapshot.maxCapacityMah) mAh")
                    }
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(palette.mutedForeground)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: NudgeMetrics.controlRadius, style: .continuous)
                        .fill(palette.muted.opacity(0.6))
                )

                // Privileged Daemon & Fast User Switching Status Strip
                HStack(spacing: 6) {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(daemon.isConnected ? palette.chart3 : palette.warning)
                            .frame(width: 7, height: 7)
                        Text(daemon.isConnected ? "Helper v\(daemon.version)" : "Helper Offline")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(palette.foreground)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(palette.muted)
                    )

                    if daemon.fastUserSwitchingProtected {
                        NudgeTagPill("Fast User Switch Safe", symbol: "person.2.fill", style: .accent)
                    }

                    Spacer()

                    if !daemon.isConnected {
                        Button("Connect") {
                            manager.installOrConnectHelperDaemon()
                        }
                        .buttonStyle(NudgePrimaryButtonStyle(compact: true))
                    }
                }
            }
        }
    }

    private func specTile(label: String, value: String, icon: String, highlight: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(highlight ? palette.accentForeground : palette.mutedForeground)
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(palette.mutedForeground)
                    .lineLimit(1)
            }
            Text(value)
                .nudgeMetricFont(size: 12.5, weight: .bold)
                .foregroundStyle(palette.foreground)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: NudgeMetrics.controlRadius, style: .continuous)
                .fill(palette.muted.opacity(0.75))
        )
        .overlay(
            RoundedRectangle(cornerRadius: NudgeMetrics.controlRadius, style: .continuous)
                .strokeBorder(palette.border.opacity(0.7), lineWidth: 1)
        )
    }
}
