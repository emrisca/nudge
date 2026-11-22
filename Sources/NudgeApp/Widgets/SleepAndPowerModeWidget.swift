import SwiftUI
import NudgeCore

public struct SleepAndPowerModeWidget: View {
    @Environment(\.nudgePalette) private var palette
    @ObservedObject var manager: BatteryManager

    public init(manager: BatteryManager) {
        self.manager = manager
    }

    private var config: BatteryConfig { manager.config }
    private var sleepState: SleepControlState { manager.sleepState }

    public var body: some View {
        NudgeCard(
            title: "Sleep & Power Mode",
            subtitle: "macOS Energy Profile & Wake Assertions",
            symbol: "moon.stars.fill",
            headerTrailing: {
                if sleepState.keepAwakeActive {
                    NudgeTagPill(keepAwakeStatusText, symbol: "cup.and.saucer.fill", style: .primary)
                }
            }
        ) {
            VStack(alignment: .leading, spacing: 12) {
                // Power Mode Segmented Selector
                VStack(alignment: .leading, spacing: 6) {
                    Text("macOS Power Mode")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.mutedForeground)

                    HStack(spacing: 4) {
                        ForEach(PowerMode.allCases) { mode in
                            let isSelected = manager.currentPowerMode == mode
                            Button {
                                manager.setPowerMode(mode)
                            } label: {
                                Text(mode.rawValue)
                                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                                    .foregroundStyle(isSelected ? palette.primaryForeground : palette.foreground)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(isSelected ? palette.primary : Color.clear)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(3)
                    .background(
                        RoundedRectangle(cornerRadius: NudgeMetrics.controlRadius, style: .continuous)
                            .fill(palette.muted)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: NudgeMetrics.controlRadius, style: .continuous)
                            .strokeBorder(palette.border, lineWidth: 1)
                    )
                }

                // Sleep Charging Toggles
                VStack(spacing: 8) {
                    Toggle(
                        isOn: Binding(
                            get: { config.stopChargingWhenSleeping },
                            set: { newVal in manager.updateConfig { $0.stopChargingWhenSleeping = newVal } }
                        )
                    ) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Stop Charging when Sleeping")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(palette.foreground)
                            Text("Pause SMC charging during macOS sleep")
                                .font(.system(size: 10, weight: .regular))
                                .foregroundStyle(palette.mutedForeground)
                        }
                    }
                    .toggleStyle(NudgeSwitchToggleStyle())

                    Toggle(
                        isOn: Binding(
                            get: { config.disableSleepUntilChargeLimit },
                            set: { newVal in manager.updateConfig { $0.disableSleepUntilChargeLimit = newVal } }
                        )
                    ) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Disable Sleep until Charge Limit")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(palette.foreground)
                            Text("Keep Mac awake until target \(config.chargeLimit)% reached")
                                .font(.system(size: 10, weight: .regular))
                                .foregroundStyle(palette.mutedForeground)
                        }
                    }
                    .toggleStyle(NudgeSwitchToggleStyle())
                }

                NudgeSectionDivider()

                // Timed Keep-Awake Section
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Keep Mac Awake")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(palette.foreground)
                        Spacer()
                        if sleepState.keepAwakeActive {
                            Button("Stop") {
                                manager.disableKeepAwake()
                            }
                            .buttonStyle(NudgeDestructiveButtonStyle(compact: true))
                        }
                    }

                    HStack(spacing: 6) {
                        keepAwakeDurationButton("30m", minutes: 30)
                        keepAwakeDurationButton("1h", minutes: 60)
                        keepAwakeDurationButton("2h", minutes: 120)
                        keepAwakeDurationButton("Indefinite", minutes: nil)
                    }

                    // Fallback Safety Triggers
                    HStack(spacing: 8) {
                        HStack(spacing: 5) {
                            Image(systemName: "battery.25percent")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(palette.mutedForeground)
                            Text("Sleep at \(config.keepAwakeFallbackPercent)%")
                                .nudgeMetricFont(size: 10.5, weight: .medium)
                                .foregroundStyle(palette.foreground)

                            HStack(spacing: 2) {
                                Button {
                                    let next = max(5, config.keepAwakeFallbackPercent - 5)
                                    manager.updateConfig { $0.keepAwakeFallbackPercent = next }
                                } label: {
                                    Image(systemName: "minus")
                                        .font(.system(size: 9, weight: .bold))
                                        .frame(width: 18, height: 18)
                                }
                                .buttonStyle(.plain)
                                .background(RoundedRectangle(cornerRadius: 5).fill(palette.card))

                                Button {
                                    let next = min(50, config.keepAwakeFallbackPercent + 5)
                                    manager.updateConfig { $0.keepAwakeFallbackPercent = next }
                                } label: {
                                    Image(systemName: "plus")
                                        .font(.system(size: 9, weight: .bold))
                                        .frame(width: 18, height: 18)
                                }
                                .buttonStyle(.plain)
                                .background(RoundedRectangle(cornerRadius: 5).fill(palette.card))
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(palette.muted)
                        )

                        Button {
                            manager.updateConfig { $0.keepAwakeReenableOnUnplug.toggle() }
                        } label: {
                            Label("Sleep on Unplug", systemImage: config.keepAwakeReenableOnUnplug ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 10.5, weight: .medium))
                                .lineLimit(1)
                        }
                        .buttonStyle(NudgePillToggleButtonStyle(isActive: config.keepAwakeReenableOnUnplug))
                    }
                }
            }
        }
    }

    private func keepAwakeDurationButton(_ label: String, minutes: Int?) -> some View {
        let isIndefiniteActive = sleepState.keepAwakeActive && sleepState.expiresAt == nil && minutes == nil
        return Button {
            manager.enableTimedKeepAwake(
                minutes: minutes,
                fallbackBatteryPercent: config.keepAwakeFallbackPercent,
                reenableOnUnplug: config.keepAwakeReenableOnUnplug
            )
        } label: {
            Text(label)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(NudgePillToggleButtonStyle(isActive: isIndefiniteActive))
    }

    private var keepAwakeStatusText: String {
        if let expires = sleepState.expiresAt {
            let remaining = max(0, Int(expires.timeIntervalSinceNow / 60))
            if remaining >= 60 {
                return "\(remaining / 60)h \(remaining % 60)m"
            }
            return "\(max(1, remaining))m left"
        }
        return "Awake"
    }
}
