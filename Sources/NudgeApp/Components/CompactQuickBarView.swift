import SwiftUI
import AppKit
import NudgeCore

/// Compact, AlDente-inspired floating quick bar rendered at the top of the macOS Menu Bar popover,
/// styled in the Moss tweakcn design system (Light & Dark).
public struct CompactQuickBarView: View {
    @Environment(\.nudgePalette) private var palette
    @ObservedObject var manager: BatteryManager
    @ObservedObject private var updater = UpdateManager.shared
    @Binding var isExpanded: Bool

    @State private var sliderLimit: Double = 80
    @State private var hoveredControl: QuickBarControl? = nil

    private let quickPresets: [Int] = [60, 70, 80, 85, 90, 100]

    private enum QuickBarControl {
        case limit
        case discharge
        case topUp
        case expand
        case exit
    }

    public init(manager: BatteryManager, isExpanded: Binding<Bool>) {
        self.manager = manager
        self._isExpanded = isExpanded
        self._sliderLimit = State(initialValue: Double(manager.config.chargeLimit))
    }

    private var config: BatteryConfig { manager.config }
    private var snapshot: BatterySnapshot { manager.latestSnapshot }

    private var isTopUpDimmed: Bool {
        !config.topUpActive && (!snapshot.isPluggedIn || snapshot.displayPercentage >= 100)
    }

    public var body: some View {
        VStack(spacing: 16) {
            // Row 1: Tactile capsule controls + Grid expand + Exit
            HStack(spacing: 7) {
                limitPill

                Spacer(minLength: 6)

                dischargePill

                topUpPill

                expandGridButton

                exitButton
            }

            // Row 2: Full-width high-contrast Moss charge limit slider
            CompactMossLimitSlider(
                value: $sliderLimit,
                range: 20...100,
                sailingEnabled: config.sailingModeEnabled,
                sailingDeadband: config.sailingDeadband
            ) { committed in
                manager.setChargeLimit(committed)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .onAppear {
            sliderLimit = Double(manager.config.chargeLimit)
        }
        .onChange(of: manager.config.chargeLimit) { _, newValue in
            sliderLimit = Double(newValue)
        }
    }

    // MARK: - Row 1 Controls

    private var limitPill: some View {
        let isHovered = hoveredControl == .limit
        return Button {
            cycleQuickPreset()
        } label: {
            HStack(spacing: 4) {
                Text("Limit:")
                    .font(.system(size: 13.5, weight: .bold))
                Text("\(Int(round(sliderLimit)))%")
                    .font(.system(size: 13.5, weight: .regular))
                    .monospacedDigit()
            }
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .tracking(NudgeMetrics.tightTracking)
            .foregroundStyle(palette.isDark ? palette.foreground : palette.secondaryForeground)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(
                Capsule(style: .continuous)
                    .fill(pillSurfaceColor(hovered: isHovered))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(pillBorderColor(hovered: isHovered), lineWidth: 1)
            )
        }
        .buttonStyle(QuickBarTactileButtonStyle())
        .onHover { hovering in
            hoveredControl = hovering ? .limit : (hoveredControl == .limit ? nil : hoveredControl)
        }
        .help("Click to cycle charge limit presets (60%–100%)")
    }

    private var dischargePill: some View {
        let isActive = config.manualDischargeActive
        let isHovered = hoveredControl == .discharge

        return Button {
            manager.setManualDischarge(!config.manualDischargeActive)
        } label: {
            HStack(spacing: 5) {
                Text("Discharge")
                    .font(.system(size: 13, weight: isActive ? .semibold : .medium))
                Image(systemName: "minus.circle")
                    .font(.system(size: 16.5, weight: .regular))
            }
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .tracking(NudgeMetrics.tightTracking)
            .foregroundStyle(
                isActive
                    ? palette.primaryForeground
                    : (palette.isDark ? palette.foreground : palette.secondaryForeground)
            )
            .padding(.horizontal, 11)
            .frame(height: 36)
            .background(
                Capsule(style: .continuous)
                    .fill(isActive ? palette.primary : pillSurfaceColor(hovered: isHovered))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(
                        isActive ? palette.ring : pillBorderColor(hovered: isHovered),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(QuickBarTactileButtonStyle())
        .onHover { hovering in
            hoveredControl = hovering ? .discharge : (hoveredControl == .discharge ? nil : hoveredControl)
        }
        .help(isActive ? "Stop Manual Discharge" : "Discharge battery while plugged in")
    }

    private var topUpPill: some View {
        let isActive = config.topUpActive
        let isHovered = hoveredControl == .topUp
        let dimmed = isTopUpDimmed && !isHovered

        return Button {
            manager.setTopUp(!config.topUpActive)
        } label: {
            HStack(spacing: 5) {
                Text("Top Up")
                    .font(.system(size: 13, weight: isActive ? .semibold : .medium))
                Image(systemName: "plus.circle")
                    .font(.system(size: 16.5, weight: .regular))
            }
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .tracking(NudgeMetrics.tightTracking)
            .foregroundStyle(
                isActive
                    ? palette.primaryForeground
                    : (dimmed
                        ? palette.mutedForeground.opacity(0.75)
                        : (palette.isDark ? palette.foreground.opacity(0.78) : palette.mutedForeground))
            )
            .padding(.horizontal, 11)
            .frame(height: 36)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        isActive
                            ? palette.primary
                            : (dimmed
                                ? palette.muted.opacity(palette.isDark ? 0.65 : 0.85)
                                : pillSurfaceColor(hovered: isHovered))
                    )
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(
                        isActive ? palette.ring : pillBorderColor(hovered: isHovered, muted: dimmed),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(QuickBarTactileButtonStyle())
        .onHover { hovering in
            hoveredControl = hovering ? .topUp : (hoveredControl == .topUp ? nil : hoveredControl)
        }
        .help(isActive ? "Cancel Top Up to 100%" : "Temporarily charge to 100%")
    }

    private var expandGridButton: some View {
        let isHovered = hoveredControl == .expand

        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                isExpanded.toggle()
            }
        } label: {
            QuickBarGridIcon()
                .foregroundStyle(
                    isExpanded
                        ? palette.accentForeground
                        : (palette.isDark ? palette.foreground : palette.secondaryForeground)
                )
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(isExpanded ? palette.accent : pillSurfaceColor(hovered: isHovered))
                )
                .overlay(
                    Circle()
                        .strokeBorder(
                            isExpanded ? palette.ring.opacity(0.75) : pillBorderColor(hovered: isHovered),
                            lineWidth: 1
                        )
                )
                .overlay(alignment: .topTrailing) {
                    if updater.hasUnignoredUpdate {
                        Circle()
                            .fill(palette.primary)
                            .frame(width: 8, height: 8)
                            .overlay(
                                Circle()
                                    .strokeBorder(palette.popover, lineWidth: 1.5)
                            )
                            .offset(x: -1, y: 1)
                    }
                }
        }
        .buttonStyle(QuickBarTactileButtonStyle())
        .onHover { hovering in
            hoveredControl = hovering ? .expand : (hoveredControl == .expand ? nil : hoveredControl)
        }
        .help(
            updater.hasUnignoredUpdate
                ? "Expand Dashboard — Update \(updater.availableRelease?.displayVersion ?? "") available"
                : (isExpanded ? "Collapse Dashboard" : "Expand Widget Dashboard")
        )
        .accessibilityLabel(isExpanded ? "Collapse Dashboard" : "Expand Widget Dashboard")
    }

    private var exitButton: some View {
        let isHovered = hoveredControl == .exit

        return Button {
            NSApp.terminate(nil)
        } label: {
            Image(systemName: "power")
                .font(.system(size: 14.5, weight: .semibold))
                .foregroundStyle(
                    isHovered
                        ? palette.destructiveForeground
                        : (palette.isDark ? palette.foreground.opacity(0.78) : palette.mutedForeground)
                )
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(isHovered ? palette.destructive : pillSurfaceColor(hovered: false))
                )
                .overlay(
                    Circle()
                        .strokeBorder(
                            isHovered ? palette.destructive : pillBorderColor(hovered: false),
                            lineWidth: 1
                        )
                )
                .animation(.easeOut(duration: 0.14), value: isHovered)
        }
        .buttonStyle(QuickBarTactileButtonStyle())
        .onHover { hovering in
            hoveredControl = hovering ? .exit : (hoveredControl == .exit ? nil : hoveredControl)
        }
        .help("Quit Nudge")
        .accessibilityLabel("Quit Nudge")
    }

    // MARK: - Helpers

    private func pillSurfaceColor(hovered: Bool) -> Color {
        if palette.isDark {
            return palette.secondary.opacity(hovered ? 0.98 : 0.78)
        } else {
            return palette.secondary.opacity(hovered ? 0.92 : 0.66)
        }
    }

    private func pillBorderColor(hovered: Bool, muted: Bool = false) -> Color {
        if hovered {
            return palette.ring.opacity(0.75)
        }
        if muted {
            return palette.border.opacity(palette.isDark ? 0.55 : 0.7)
        }
        return palette.isDark
            ? Color.white.opacity(0.08)
            : palette.border.opacity(0.9)
    }

    private func cycleQuickPreset() {
        let current = Int(round(sliderLimit))
        let next = quickPresets.first(where: { $0 > current }) ?? quickPresets.first ?? 80
        withAnimation(.easeOut(duration: 0.14)) {
            sliderLimit = Double(next)
        }
        manager.setChargeLimit(next)
    }
}

// MARK: - Custom 3-Squares + 1-Circle Grid Icon (matches quick-bar design)

private struct QuickBarGridIcon: View {
    var body: some View {
        let tileSize: CGFloat = 6.5
        let spacing: CGFloat = 2.5
        let lineWidth: CGFloat = 1.6

        VStack(spacing: spacing) {
            HStack(spacing: spacing) {
                RoundedRectangle(cornerRadius: 1.8, style: .continuous)
                    .strokeBorder(lineWidth: lineWidth)
                    .frame(width: tileSize, height: tileSize)
                RoundedRectangle(cornerRadius: 1.8, style: .continuous)
                    .strokeBorder(lineWidth: lineWidth)
                    .frame(width: tileSize, height: tileSize)
            }
            HStack(spacing: spacing) {
                RoundedRectangle(cornerRadius: 1.8, style: .continuous)
                    .strokeBorder(lineWidth: lineWidth)
                    .frame(width: tileSize, height: tileSize)
                Circle()
                    .strokeBorder(lineWidth: lineWidth)
                    .frame(width: tileSize, height: tileSize)
            }
        }
    }
}

// MARK: - Compact Full-Width Moss Slider

private struct CompactMossLimitSlider: View {
    @Environment(\.nudgePalette) private var palette

    @Binding var value: Double
    let range: ClosedRange<Double>
    let sailingEnabled: Bool
    let sailingDeadband: Int
    let onCommit: (Int) -> Void

    @State private var isDragging: Bool = false

    private let trackHeight: CGFloat = 7
    private let thumbWidth: CGFloat = 24
    private let thumbHeight: CGFloat = 19

    private func normalized(_ val: Double) -> CGFloat {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return CGFloat(min(1, max(0, (val - range.lowerBound) / span)))
    }

    var body: some View {
        GeometryReader { geo in
            let width = max(1, geo.size.width)
            let usableWidth = max(1, width - thumbWidth)
            let fraction = normalized(value)
            let thumbOriginX = usableWidth * fraction
            let fillWidth = thumbOriginX + (thumbWidth * 0.5)

            let deadbandFloor = max(range.lowerBound, value - Double(sailingDeadband))
            let deadbandStartX = usableWidth * normalized(deadbandFloor) + (thumbWidth * 0.5)
            let deadbandWidth = max(0, fillWidth - deadbandStartX)

            ZStack(alignment: .leading) {
                // Unfilled track
                Capsule(style: .continuous)
                    .fill(palette.isDark ? Color.white.opacity(0.16) : palette.input)
                    .frame(height: trackHeight)
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(
                                palette.isDark ? Color.white.opacity(0.05) : palette.border.opacity(0.8),
                                lineWidth: 0.5
                            )
                    )

                // Filled Moss green progress bar
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: palette.isDark
                                ? [palette.chart2, palette.chart3]
                                : [palette.accent, palette.primary],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(trackHeight, fillWidth), height: trackHeight)

                // Subtle Sailing Mode deadband tick when enabled
                if sailingEnabled && deadbandWidth > 3 {
                    Capsule(style: .continuous)
                        .fill(Color.black.opacity(palette.isDark ? 0.30 : 0.18))
                        .frame(width: deadbandWidth, height: trackHeight)
                        .offset(x: deadbandStartX)

                    RoundedRectangle(cornerRadius: 1)
                        .fill(palette.isDark ? Color(hex: 0xF9F8F7).opacity(0.7) : Color(hex: 0xFAFAF9).opacity(0.85))
                        .frame(width: 2, height: trackHeight + 3)
                        .offset(x: max(0, deadbandStartX - 1))
                }

                // Oversized crisp off-white pill thumb knob
                Capsule(style: .continuous)
                    .fill(Color(hex: 0xF9F8F7))
                    .frame(
                        width: isDragging ? thumbWidth + 2 : thumbWidth,
                        height: isDragging ? thumbHeight + 1.5 : thumbHeight
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(
                                palette.isDark ? Color.black.opacity(0.22) : palette.border,
                                lineWidth: 0.75
                            )
                    )
                    .shadow(
                        color: Color.black.opacity(palette.isDark ? 0.42 : 0.22),
                        radius: isDragging ? 5 : 3,
                        x: 0,
                        y: 1.5
                    )
                    .offset(x: isDragging ? max(0, min(width - (thumbWidth + 2), thumbOriginX - 1)) : thumbOriginX)
                    .animation(.easeOut(duration: 0.1), value: isDragging)
            }
            .frame(height: 22)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        isDragging = true
                        let clampedX = min(width - thumbWidth * 0.5, max(thumbWidth * 0.5, gesture.location.x))
                        let ratio = (clampedX - thumbWidth * 0.5) / usableWidth
                        let raw = range.lowerBound + Double(ratio) * (range.upperBound - range.lowerBound)
                        value = min(range.upperBound, max(range.lowerBound, round(raw)))
                    }
                    .onEnded { _ in
                        isDragging = false
                        onCommit(Int(round(value)))
                    }
            )
        }
        .frame(height: 22)
    }
}

private struct QuickBarTactileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeOut(duration: 0.11), value: configuration.isPressed)
    }
}
