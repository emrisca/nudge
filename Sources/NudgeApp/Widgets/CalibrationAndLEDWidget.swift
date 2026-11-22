import SwiftUI
import NudgeCore

public struct CalibrationAndLEDWidget: View {
    @Environment(\.nudgePalette) private var palette
    @ObservedObject var manager: BatteryManager

    public init(manager: BatteryManager) {
        self.manager = manager
    }

    private var phase: CalibrationPhase { manager.latestTick.calibrationPhase }
    private var isCalibrating: Bool { phase != .idle }
    private var activeLED: MagSafeLEDState { manager.config.magSafeLEDMode }

    public var body: some View {
        NudgeCard(
            title: "Calibration & MagSafe LED",
            subtitle: "4-Phase Full Cycle & Hardware Indicator",
            symbol: "gauge.with.dots.needle.67percent",
            headerTrailing: {
                if isCalibrating {
                    NudgeTagPill("Heat Bypass", symbol: "shield.lefthalf.filled", style: .warning)
                }
            }
        ) {
            VStack(alignment: .leading, spacing: 14) {
                // 4-Phase Calibration Stepper
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Battery Calibration")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(palette.foreground)
                        Spacer()
                        Text(phaseDescription(phase))
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(isCalibrating ? palette.accentForeground : palette.mutedForeground)
                    }

                    HStack(spacing: 4) {
                        calibrationStep(index: 1, title: "100%", caption: "Full", stepPhase: .chargeToFull)
                        stepArrow
                        calibrationStep(index: 2, title: "10%", caption: "Drain", stepPhase: .dischargeToLow)
                        stepArrow
                        calibrationStep(index: 3, title: "100%", caption: "Top", stepPhase: .rechargeToFull)
                        stepArrow
                        calibrationStep(index: 4, title: "\(manager.config.chargeLimit)%", caption: "Limit", stepPhase: .returnToTargetLimit)
                    }

                    HStack(spacing: 8) {
                        if isCalibrating {
                            Button {
                                manager.cancelCalibration()
                            } label: {
                                Label("Cancel Calibration", systemImage: "stop.circle.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(NudgeDestructiveButtonStyle(compact: false))
                        } else {
                            Button {
                                manager.startCalibration()
                            } label: {
                                Label("Start 4-Phase Calibration", systemImage: "arrow.triangle.2.circlepath")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(NudgePrimaryButtonStyle(compact: true))
                        }
                    }
                }

                NudgeSectionDivider()

                // MagSafe LED Control
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 7) {
                        MagSafeLEDDot(state: manager.latestTick.activeMagSafeLED)
                        Text("MagSafe LED")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(palette.foreground)
                        Spacer()
                        Text("Live: \(manager.latestTick.activeMagSafeLED.rawValue)")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(palette.mutedForeground)
                    }

                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 5),
                            GridItem(.flexible(), spacing: 5),
                            GridItem(.flexible(), spacing: 5)
                        ],
                        spacing: 5
                    ) {
                        ForEach(MagSafeLEDState.allCases) { state in
                            Button {
                                manager.setMagSafeLED(state)
                            } label: {
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(ledPreviewColor(state))
                                        .frame(width: 6, height: 6)
                                    Text(shortLEDLabel(state))
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(NudgePillToggleButtonStyle(isActive: activeLED == state))
                        }
                    }

                    Toggle(
                        isOn: Binding(
                            get: { manager.config.syncMagSafeLEDWithState },
                            set: { newVal in manager.updateConfig { $0.syncMagSafeLEDWithState = newVal } }
                        )
                    ) {
                        Text("Auto-Sync LED with Charge State")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(palette.foreground)
                    }
                    .toggleStyle(NudgeSwitchToggleStyle())
                }
            }
        }
    }

    private func calibrationStep(index: Int, title: String, caption: String, stepPhase: CalibrationPhase) -> some View {
        let currentOrder = phaseOrder(phase)
        let stepOrder = phaseOrder(stepPhase)
        let isCompleted = isCalibrating && currentOrder > stepOrder
        let isCurrent = isCalibrating && currentOrder == stepOrder

        return VStack(spacing: 2) {
            Text(title)
                .nudgeMetricFont(size: 11.5, weight: .bold)
                .foregroundStyle(
                    isCurrent
                        ? palette.primaryForeground
                        : (isCompleted ? palette.accentForeground : palette.foreground)
                )
            Text(caption)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(
                    isCurrent
                        ? palette.primaryForeground.opacity(0.8)
                        : palette.mutedForeground
                )
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    isCurrent
                        ? palette.primary
                        : (isCompleted ? palette.accent : palette.muted)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isCurrent ? palette.primary : palette.border, lineWidth: 1)
        )
    }

    private var stepArrow: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 8.5, weight: .bold))
            .foregroundStyle(palette.mutedForeground.opacity(0.6))
    }

    private func phaseOrder(_ p: CalibrationPhase) -> Int {
        switch p {
        case .idle: return 0
        case .chargeToFull: return 1
        case .dischargeToLow: return 2
        case .rechargeToFull: return 3
        case .returnToTargetLimit: return 4
        }
    }

    private func phaseDescription(_ p: CalibrationPhase) -> String {
        switch p {
        case .idle: return "Ready"
        case .chargeToFull: return "Phase 1/4 · Charging to 100%"
        case .dischargeToLow: return "Phase 2/4 · Draining to 10%"
        case .rechargeToFull: return "Phase 3/4 · Topping to 100%"
        case .returnToTargetLimit: return "Phase 4/4 · Settling to \(manager.config.chargeLimit)%"
        }
    }

    private func shortLEDLabel(_ state: MagSafeLEDState) -> String {
        switch state {
        case .systemDefault: return "System"
        case .green: return "Green"
        case .orange: return "Orange"
        case .blinkingOrange: return "Blink"
        case .off: return "Off"
        }
    }

    private func ledPreviewColor(_ state: MagSafeLEDState) -> Color {
        switch state {
        case .systemDefault: return palette.mutedForeground
        case .green: return Color(hex: 0x22C55E)
        case .orange, .blinkingOrange: return Color(hex: 0xF97316)
        case .off: return Color.gray.opacity(0.35)
        }
    }
}

private struct MagSafeLEDDot: View {
    let state: MagSafeLEDState
    @State private var blinkOn: Bool = true

    var body: some View {
        Circle()
            .fill(dotColor)
            .frame(width: 9, height: 9)
            .shadow(color: dotColor.opacity(state == .off ? 0 : 0.7), radius: 4)
            .opacity(state == .blinkingOrange ? (blinkOn ? 1.0 : 0.25) : 1.0)
            .onAppear {
                if state == .blinkingOrange {
                    withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                        blinkOn.toggle()
                    }
                }
            }
    }

    private var dotColor: Color {
        switch state {
        case .green: return Color(hex: 0x22C55E)
        case .orange, .blinkingOrange: return Color(hex: 0xF97316)
        case .off: return Color.gray.opacity(0.35)
        case .systemDefault: return Color(hex: 0xAFF33E)
        }
    }
}
