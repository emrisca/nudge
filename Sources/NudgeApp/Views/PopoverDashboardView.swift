import SwiftUI
import AppKit
import NudgeCore

public struct PopoverDashboardView: View {
    @Environment(\.nudgePalette) private var palette
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var manager: BatteryManager
    @ObservedObject var navigation: NudgeNavigationController

    @State private var isExpanded: Bool
    @State private var isEditingLayout: Bool = false
    @State private var draggedWidget: PopoverWidgetKind? = nil

    @MainActor
    public init(manager: BatteryManager, initialExpanded: Bool = false) {
        self.manager = manager
        self.navigation = .shared
        self._isExpanded = State(initialValue: initialExpanded)
    }

    public init(manager: BatteryManager, navigation: NudgeNavigationController, initialExpanded: Bool = false) {
        self.manager = manager
        self.navigation = navigation
        self._isExpanded = State(initialValue: initialExpanded)
    }

    /// Complete normalized widget order containing all PopoverWidgetKind cases exactly once.
    private var orderedWidgets: [PopoverWidgetKind] {
        var result = manager.config.popoverWidgetOrder
        for kind in PopoverWidgetKind.allCases where !result.contains(kind) {
            result.append(kind)
        }
        return result
    }

    private var visibleWidgets: [PopoverWidgetKind] {
        let hidden = Set(manager.config.hiddenPopoverWidgets)
        return orderedWidgets.filter { !hidden.contains($0) }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Always-visible sleek compact quick bar (default collapsed state)
            CompactQuickBarView(manager: manager, isExpanded: $isExpanded)

            // Expandable full Moss widget dashboard toggled by the far-right 2x2 grid button
            if isExpanded {
                NudgeSectionDivider()

                expandedToolbar

                NudgeSectionDivider()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 12) {
                        if isEditingLayout {
                            editModePanel
                        } else {
                            if visibleWidgets.isEmpty {
                                emptyWidgetsBanner
                            } else {
                                ForEach(visibleWidgets) { kind in
                                    widgetView(for: kind)
                                        .draggable(kind.rawValue) {
                                            dragPreview(for: kind)
                                                .onAppear { draggedWidget = kind }
                                        }
                                        .dropDestination(for: String.self) { items, _ in
                                            guard let raw = items.first,
                                                  let source = PopoverWidgetKind(rawValue: raw) else { return false }
                                            moveWidget(source, before: kind)
                                            draggedWidget = nil
                                            return true
                                        }
                                }
                            }
                        }
                    }
                    .padding(14)
                }
                .frame(maxHeight: 540)

                NudgeSectionDivider()

                footerBar
            }
        }
        .frame(width: NudgeMetrics.popoverWidth)
        .fixedSize(horizontal: false, vertical: !isExpanded)
        .background(
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                palette.popover.opacity(palette.isDark ? 0.84 : 0.88)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: NudgeMetrics.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: NudgeMetrics.cardRadius, style: .continuous)
                .strokeBorder(
                    palette.isDark ? Color.white.opacity(0.11) : palette.border,
                    lineWidth: 1
                )
        )
        .foregroundStyle(palette.popoverForeground)
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: isExpanded)
    }

    // MARK: - Expanded Dashboard Toolbar

    private var expandedToolbar: some View {
        HStack(spacing: 8) {
            NudgeBrandBadge(size: 24)

            HStack(spacing: 6) {
                Text("Nudge")
                    .nudgeHeadingFont(size: 13.5, weight: .bold)
                    .foregroundStyle(palette.popoverForeground)
                ChargingStateBadge(state: manager.latestSnapshot.state, compact: true)
            }

            Spacer(minLength: 4)

            // Light / Dark Quick Toggle
            Button {
                toggleAppearance()
            } label: {
                Image(systemName: palette.isDark ? "sun.max.fill" : "moon.fill")
            }
            .buttonStyle(NudgeIconButtonStyle())
            .help("Toggle Light / Dark Theme")

            // Edit Layout Toggle
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isEditingLayout.toggle()
                }
            } label: {
                Image(systemName: isEditingLayout ? "checkmark" : "slider.horizontal.3")
            }
            .buttonStyle(NudgeIconButtonStyle(isActive: isEditingLayout))
            .help(isEditingLayout ? "Done Editing Layout" : "Customize Popover Widgets")

            // Open Full Dashboard Window (keeps .accessory policy / Dock hidden)
            Button {
                navigation.openDashboard(using: openWindow, section: .overview)
            } label: {
                Image(systemName: "macwindow")
            }
            .buttonStyle(NudgeIconButtonStyle())
            .help("Open Full Dashboard")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(palette.card.opacity(0.75))
    }

    // MARK: - Edit Layout Mode

    private var editModePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Customize Popover Widgets")
                        .nudgeHeadingFont(size: 13, weight: .semibold)
                        .foregroundStyle(palette.foreground)
                    Text("Drag rows or use arrows to reorder. Toggle eye to show or hide.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(palette.mutedForeground)
                }
                Spacer()
                Button("Reset") {
                    manager.updateConfig {
                        $0.popoverWidgetOrder = PopoverWidgetKind.allCases
                        $0.hiddenPopoverWidgets = []
                    }
                }
                .buttonStyle(NudgeSecondaryButtonStyle(compact: true))
            }

            VStack(spacing: 6) {
                let allOrdered = orderedWidgets
                let hiddenSet = Set(manager.config.hiddenPopoverWidgets)

                ForEach(Array(allOrdered.enumerated()), id: \.element.id) { index, kind in
                    let isVisible = !hiddenSet.contains(kind)
                    HStack(spacing: 8) {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.mutedForeground)

                        Image(systemName: kind.symbolName)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(isVisible ? palette.accentForeground : palette.mutedForeground)
                            .frame(width: 24, height: 24)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(isVisible ? palette.accent : palette.muted)
                            )

                        Text(kind.rawValue)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(isVisible ? palette.foreground : palette.mutedForeground)
                            .lineLimit(1)

                        Spacer()

                        // Move Up
                        Button {
                            moveWidgetByOffset(kind, offset: -1)
                        } label: {
                            Image(systemName: "chevron.up")
                                .font(.system(size: 10, weight: .bold))
                                .frame(width: 22, height: 22)
                        }
                        .buttonStyle(.plain)
                        .disabled(index == 0)
                        .opacity(index == 0 ? 0.35 : 1.0)

                        // Move Down
                        Button {
                            moveWidgetByOffset(kind, offset: 1)
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .bold))
                                .frame(width: 22, height: 22)
                        }
                        .buttonStyle(.plain)
                        .disabled(index == allOrdered.count - 1)
                        .opacity(index == allOrdered.count - 1 ? 0.35 : 1.0)

                        // Visibility Toggle
                        Button {
                            toggleVisibility(kind)
                        } label: {
                            Image(systemName: isVisible ? "eye.fill" : "eye.slash")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(isVisible ? palette.primaryForeground : palette.mutedForeground)
                                .frame(width: 26, height: 24)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(isVisible ? palette.primary : palette.muted)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: NudgeMetrics.controlRadius, style: .continuous)
                            .fill(palette.card)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: NudgeMetrics.controlRadius, style: .continuous)
                            .strokeBorder(palette.border, lineWidth: 1)
                    )
                    .draggable(kind.rawValue) {
                        dragPreview(for: kind)
                    }
                    .dropDestination(for: String.self) { items, _ in
                        guard let raw = items.first,
                              let source = PopoverWidgetKind(rawValue: raw) else { return false }
                        moveWidget(source, before: kind)
                        return true
                    }
                }
            }

            Button {
                withAnimation { isEditingLayout = false }
            } label: {
                Text("Done")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(NudgePrimaryButtonStyle())
        }
    }

    private var emptyWidgetsBanner: some View {
        NudgeCard {
            VStack(spacing: 8) {
                Text("All Popover Widgets Hidden")
                    .nudgeHeadingFont(size: 13, weight: .semibold)
                Text("Enable widgets to monitor battery telemetry and controls here.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(palette.mutedForeground)
                    .multilineTextAlignment(.center)
                Button("Customize Layout") {
                    withAnimation { isEditingLayout = true }
                }
                .buttonStyle(NudgePrimaryButtonStyle(compact: true))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Footer

    private var footerBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(manager.daemonStatus.isConnected ? palette.statusPositive : palette.warning)
                .frame(width: 7, height: 7)

            Text(
                manager.daemonStatus.isConnected
                    ? "Daemon Active · Limit \(manager.config.chargeLimit)%"
                    : "App Mode · Limit \(manager.config.chargeLimit)%"
            )
            .font(.system(size: 10.5, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(palette.mutedForeground)

            Spacer()

            Button {
                navigation.openDashboard(using: openWindow, section: .settings)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Settings")
                        .font(.system(size: 10.5, weight: .semibold))
                }
                .foregroundStyle(palette.secondaryForeground)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(palette.secondary)
                )
            }
            .buttonStyle(.plain)
            .help("Open Settings in Full Dashboard")

            Button {
                _ = manager.tick()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Sync")
                        .font(.system(size: 10.5, weight: .semibold))
                }
                .foregroundStyle(palette.foreground)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(palette.muted)
                )
            }
            .buttonStyle(.plain)
            .help("Force Telemetry Sync")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(palette.card.opacity(0.75))
    }

    // MARK: - Widget Factory & Drag Helpers

    @ViewBuilder
    private func widgetView(for kind: PopoverWidgetKind) -> some View {
        switch kind {
        case .chargeControl:
            ChargeControlWidget(manager: manager)
        case .powerFlow:
            PowerFlowWidget(manager: manager)
        case .historicalCharts:
            HistoricalChartsWidget(manager: manager)
        case .batterySpecs:
            BatterySpecsWidget(manager: manager)
        case .highEnergyApps:
            HighEnergyAppsWidget(manager: manager)
        case .sleepAndPowerMode:
            SleepAndPowerModeWidget(manager: manager)
        case .schedule:
            ScheduleWidget(manager: manager)
        case .calibrationAndLED:
            CalibrationAndLEDWidget(manager: manager)
        }
    }

    private func dragPreview(for kind: PopoverWidgetKind) -> some View {
        HStack(spacing: 8) {
            Image(systemName: kind.symbolName)
                .foregroundStyle(palette.primaryForeground)
            Text(kind.shortTitle)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.primaryForeground)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: NudgeMetrics.controlRadius, style: .continuous)
                .fill(palette.primary)
        )
    }

    private func toggleAppearance() {
        let next: NudgeAppearance = palette.isDark ? .light : .dark
        manager.updateConfig { $0.appearancePreference = next.rawValue }
    }

    private func toggleVisibility(_ kind: PopoverWidgetKind) {
        manager.updateConfig { cfg in
            if let idx = cfg.hiddenPopoverWidgets.firstIndex(of: kind) {
                cfg.hiddenPopoverWidgets.remove(at: idx)
            } else {
                cfg.hiddenPopoverWidgets.append(kind)
            }
        }
    }

    private func moveWidget(_ source: PopoverWidgetKind, before target: PopoverWidgetKind) {
        guard source != target else { return }
        var order = orderedWidgets
        guard let fromIdx = order.firstIndex(of: source),
              let toIdx = order.firstIndex(of: target) else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            let item = order.remove(at: fromIdx)
            order.insert(item, at: toIdx)
            manager.updateConfig { $0.popoverWidgetOrder = order }
        }
    }

    private func moveWidgetByOffset(_ kind: PopoverWidgetKind, offset: Int) {
        var order = orderedWidgets
        guard let idx = order.firstIndex(of: kind) else { return }
        let dest = idx + offset
        guard dest >= 0 && dest < order.count else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            order.swapAt(idx, dest)
            manager.updateConfig { $0.popoverWidgetOrder = order }
        }
    }
}
