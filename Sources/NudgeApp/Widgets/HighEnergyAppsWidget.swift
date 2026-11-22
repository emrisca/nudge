import SwiftUI
import NudgeCore

public struct HighEnergyAppsWidget: View {
    @Environment(\.nudgePalette) private var palette
    @ObservedObject var manager: BatteryManager

    var maxVisibleCount: Int = 5

    @State private var confirmingPID: Int32? = nil
    @State private var feedbackMessage: String? = nil

    public init(manager: BatteryManager, maxVisibleCount: Int = 5) {
        self.manager = manager
        self.maxVisibleCount = maxVisibleCount
    }

    private var sortedApps: [HighEnergyApp] {
        manager.highEnergyApps.sorted { $0.energyImpactScore > $1.energyImpactScore }
    }

    public var body: some View {
        NudgeCard(
            title: "Apps Using Significant Energy",
            subtitle: sortedApps.isEmpty ? "All processes nominal" : "Top \(min(sortedApps.count, maxVisibleCount)) energy consumers",
            symbol: "flame.fill",
            headerTrailing: {
                Button {
                    manager.refreshHighEnergyApps()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(NudgeIconButtonStyle())
                .help("Refresh High Energy Apps")
            }
        ) {
            VStack(spacing: 8) {
                if let feedbackMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text(feedbackMessage)
                            .font(.system(size: 11, weight: .medium))
                        Spacer()
                    }
                    .foregroundStyle(palette.accentForeground)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(palette.accent)
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if sortedApps.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "leaf.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(palette.accentForeground)
                        Text("No high-energy apps detected right now.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(palette.mutedForeground)
                        Spacer()
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: NudgeMetrics.controlRadius, style: .continuous)
                            .fill(palette.muted.opacity(0.6))
                    )
                } else {
                    ForEach(Array(sortedApps.prefix(maxVisibleCount))) { app in
                        appRow(app)
                    }
                }
            }
        }
    }

    private func appRow(_ app: HighEnergyApp) -> some View {
        let isConfirming = confirmingPID == app.id
        let normalizedScore = min(1.0, max(0.05, app.energyImpactScore / 100.0))
        let barColor: Color = app.energyImpactScore >= 65
            ? palette.destructive
            : (app.energyImpactScore >= 35 ? palette.warning : palette.primary)

        return VStack(spacing: 6) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.foreground)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(String(format: "CPU %.1f%%", app.cpuPercent))
                        Text("·")
                        Text(String(format: "%.1fW", app.estimatedWatts))
                        Text("·")
                        Text(String(format: "%.0f MB", app.memoryMB))
                    }
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(palette.mutedForeground)
                }

                Spacer(minLength: 4)

                if isConfirming {
                    HStack(spacing: 4) {
                        Button("Quit") {
                            let name = app.name
                            manager.terminateHighEnergyApp(pid: app.id)
                            confirmingPID = nil
                            withAnimation {
                                feedbackMessage = "Sent terminate signal to \(name)"
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                                withAnimation {
                                    if feedbackMessage == "Sent terminate signal to \(name)" {
                                        feedbackMessage = nil
                                    }
                                }
                            }
                        }
                        .buttonStyle(NudgeDestructiveButtonStyle(compact: true))

                        Button {
                            confirmingPID = nil
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .buttonStyle(NudgeSecondaryButtonStyle(compact: true))
                    }
                } else {
                    Button {
                        withAnimation(.easeOut(duration: 0.14)) {
                            confirmingPID = app.id
                        }
                    } label: {
                        Text("Terminate")
                            .font(.system(size: 10.5, weight: .semibold))
                    }
                    .buttonStyle(NudgeSecondaryButtonStyle(compact: true))
                }
            }

            // Energy impact score bar
            HStack(spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule(style: .continuous)
                            .fill(palette.muted)
                        Capsule(style: .continuous)
                            .fill(barColor)
                            .frame(width: max(4, geo.size.width * normalizedScore))
                    }
                }
                .frame(height: 4)

                Text(String(format: "Impact %.0f", app.energyImpactScore))
                    .nudgeMetricFont(size: 9.5, weight: .semibold)
                    .foregroundStyle(palette.mutedForeground)
                    .frame(width: 54, alignment: .trailing)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: NudgeMetrics.controlRadius, style: .continuous)
                .fill(palette.muted.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: NudgeMetrics.controlRadius, style: .continuous)
                .strokeBorder(isConfirming ? palette.destructive.opacity(0.5) : palette.border.opacity(0.6), lineWidth: 1)
        )
    }
}
