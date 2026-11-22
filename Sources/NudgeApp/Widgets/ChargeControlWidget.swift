import SwiftUI
import NudgeCore

public struct ChargeControlWidget: View {
    @Environment(\.nudgePalette) private var palette
    @ObservedObject var manager: BatteryManager

    @State private var sliderLimit: Double = 80

    public init(manager: BatteryManager) {
        self.manager = manager
        self._sliderLimit = State(initialValue: Double(manager.config.chargeLimit))
    }

    private var snapshot: BatterySnapshot { manager.latestSnapshot }
    private var config: BatteryConfig { manager.config }
    private var tick: BatteryTickResult { manager.latestTick }

    public var body: some View {
        NudgeCard(padding: 15) {
            VStack(alignment: .leading, spacing: 14) {
                // Hero battery percentage + state
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(snapshot.displayPercentage)%")
                                .nudgeMetricFont(size: 40, weight: .bold)
                                .foregroundStyle(palette.cardForeground)

                            if config.showHardwarePercentage {
                                NudgeTagPill(
                                    String(format: "HW %.1f%%", snapshot.rawHardwarePercentage),
                                    symbol: "cpu",
                                    style: .secondary
                                )
                            }
                        }

                        HStack(spacing: 6) {
                            Image(systemName: snapshot.isPluggedIn ? "powerplug.fill" : "battery.75percent")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(snapshot.isPluggedIn ? palette.highlightText : palette.mutedForeground)
                            Text(statusSubtitle)
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(palette.mutedForeground)
                                .monospacedDigit()
                        }
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 6) {
                        ChargingStateBadge(state: snapshot.state)
                        Text(String(format: "%.1f°C · %+.1fW", snapshot.temperatureCelsius, snapshot.powerFlow.batteryWatts))
                            .nudgeMetricFont(size: 11, weight: .medium)
                            .foregroundStyle(palette.mutedForeground)
                    }
                }

                // Heat protection active cooldown banner
                if tick.heatProtectionActive || tick.heatCooldownRemainingSeconds > 0 {
                    HStack(spacing: 8) {
                        Image(systemName: "thermometer.sun.fill")
                            .font(.system(size: 12, weight: .bold))
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Heat Protection Active")
                                .font(.system(size: 11.5, weight: .semibold))
                            Text(
                                tick.heatCooldownRemainingSeconds > 0
                                    ? "Charging paused · Cooldown \(formattedCooldown(tick.heatCooldownRemainingSeconds))"
                                    : String(format: "Battery %.1f°C exceeded %.0f°C limit", snapshot.temperatureCelsius, config.heatThresholdCelsius)
                            )
                            .font(.system(size: 10.5, weight: .medium))
                            .monospacedDigit()
                            .opacity(0.92)
                        }
                        Spacer()
                    }
                    .foregroundStyle(palette.isDark ? palette.destructiveForeground : palette.destructive)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: NudgeMetrics.controlRadius, style: .continuous)
                            .fill(palette.destructive.opacity(palette.isDark ? 0.45 : 0.10))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: NudgeMetrics.controlRadius, style: .continuous)
                            .strokeBorder(palette.destructive.opacity(0.45), lineWidth: 1)
                    )
                }

                // Interactive Charge Limit Slider + Sailing Deadband
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text("Charge Limit")
                            .nudgeHeadingFont(size: 12, weight: .semibold)
                            .foregroundStyle(palette.foreground)

                        if config.sailingModeEnabled {
                            let floorPercent = max(20, Int(round(sliderLimit)) - config.sailingDeadband)
                            NudgeTagPill("Sail \(floorPercent)–\(Int(round(sliderLimit)))%", symbol: "wind", style: .accent)
                        }

                        Spacer()

                        Text("\(Int(round(sliderLimit)))%")
                            .nudgeMetricFont(size: 14, weight: .bold)
                            .foregroundStyle(palette.secondaryForeground)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(palette.secondary)
                            )
                    }

                    ChargeLimitSlider(
                        value: $sliderLimit,
                        range: 20...100,
                        sailingEnabled: config.sailingModeEnabled,
                        sailingDeadband: config.sailingDeadband,
                        currentBatteryPercent: snapshot.displayPercentage
                    ) { committed in
                        manager.setChargeLimit(committed)
                    }
                }

                NudgeSectionDivider()

                // One-tap Action Pills
                VStack(spacing: 7) {
                    HStack(spacing: 7) {
                        Button {
                            manager.setTopUp(!config.topUpActive)
                        } label: {
                            Label("Top Up", systemImage: "arrow.up.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(NudgePillToggleButtonStyle(isActive: config.topUpActive))

                        Button {
                            manager.setManualDischarge(!config.manualDischargeActive)
                        } label: {
                            Label("Discharge", systemImage: "arrow.down.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(
                            NudgePillToggleButtonStyle(
                                isActive: config.manualDischargeActive,
                                activeFill: palette.warning,
                                activeForeground: Color(hex: 0x040302)
                            )
                        )

                        Button {
                            manager.updateConfig { $0.sailingModeEnabled.toggle() }
                        } label: {
                            Label("Sailing", systemImage: "wind")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(NudgePillToggleButtonStyle(isActive: config.sailingModeEnabled))
                    }

                    HStack(spacing: 7) {
                        Button {
                            manager.updateConfig { $0.heatProtectionEnabled.toggle() }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "thermometer.medium")
                                Text(heatPillLabel)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(
                            NudgePillToggleButtonStyle(
                                isActive: config.heatProtectionEnabled,
                                activeFill: tick.heatProtectionActive ? palette.destructive : palette.primary,
                                activeForeground: tick.heatProtectionActive ? palette.destructiveForeground : palette.primaryForeground
                            )
                        )

                        Button {
                            manager.updateConfig { $0.automaticDischargeEnabled.toggle() }
                        } label: {
                            Label("Auto Discharge", systemImage: "bolt.slash.fill")
                                .lineLimit(1)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(NudgePillToggleButtonStyle(isActive: config.automaticDischargeEnabled))
                    }
                }
            }
        }
        .onChange(of: manager.config.chargeLimit) { _, newValue in
            sliderLimit = Double(newValue)
        }
        .onAppear {
            sliderLimit = Double(manager.config.chargeLimit)
        }
    }

    private var statusSubtitle: String {
        var parts: [String] = []
        if snapshot.isPluggedIn {
            parts.append("Adapter \(snapshot.adapterMaxWatts)W")
        } else {
            parts.append("Unplugged")
        }
        if let mins = snapshot.timeRemainingMinutes, mins > 0 {
            let h = mins / 60
            let m = mins % 60
            parts.append(h > 0 ? "\(h)h \(m)m left" : "\(m)m left")
        } else if tick.sailingActive {
            parts.append("Sailing deadband")
        } else if tick.chargingInhibited && snapshot.isPluggedIn {
            parts.append("Holding at \(config.chargeLimit)%")
        }
        return parts.joined(separator: " · ")
    }

    private var heatPillLabel: String {
        if tick.heatCooldownRemainingSeconds > 0 {
            return "Heat \(formattedCooldown(tick.heatCooldownRemainingSeconds))"
        }
        return "Heat \(Int(config.heatThresholdCelsius))°C"
    }

    private func formattedCooldown(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(ceil(seconds)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
