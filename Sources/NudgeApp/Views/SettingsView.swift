import SwiftUI
import NudgeCore

// MARK: - Settings & Privileged Daemon View

public struct SettingsView: View {
    @Environment(\.nudgePalette) private var palette
    @ObservedObject var manager: BatteryManager

    public init(manager: BatteryManager) {
        self.manager = manager
    }

    private var config: BatteryConfig { manager.config }
    private var daemon: HelperDaemonStatus { manager.daemonStatus }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Appearance Theme Switcher
            NudgeCard(
                title: "Appearance & Theme",
                subtitle: "Moss tweakcn Design System · System / Light / Dark",
                symbol: "paintbrush.fill"
            ) {
                HStack(spacing: 10) {
                    ForEach(NudgeAppearance.allCases) { mode in
                        appearanceOptionCard(mode)
                    }
                }
            }

            // GitHub Releases Software Updater
            UpdateSettingsCard(updater: .shared)

            // Privileged Helper Daemon (SMJobBless / LaunchDaemon)
            NudgeCard(
                title: "Privileged Helper Daemon",
                subtitle: "SMJobBless / LaunchDaemon always-on hardware SMC enforcement",
                symbol: "shield.checkered",
                headerTrailing: {
                    NudgeTagPill(
                        daemon.isConnected ? "Connected v\(daemon.version)" : (daemon.isInstalled ? "Installed · Idle" : "Not Installed"),
                        symbol: daemon.isConnected ? "checkmark.seal.fill" : "exclamationmark.triangle.fill",
                        style: daemon.isConnected ? .accent : .warning
                    )
                }
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        daemonMetric(
                            title: "Enforced Limit",
                            value: daemon.enforcedLimit.map { "\($0)%" } ?? "\(config.chargeLimit)%"
                        )
                        daemonMetric(
                            title: "Fast User Switching",
                            value: daemon.fastUserSwitchingProtected ? "Protected" : "Unprotected"
                        )
                        daemonMetric(
                            title: "Last Heartbeat",
                            value: daemon.lastHeartbeat.map { relativeTime($0) } ?? "Pending"
                        )
                    }

                    HStack(spacing: 10) {
                        Button {
                            manager.installOrConnectHelperDaemon()
                        } label: {
                            Label(
                                daemon.isConnected ? "Reconnect Helper Daemon" : "Install & Connect Helper Daemon",
                                systemImage: "bolt.shield.fill"
                            )
                        }
                        .buttonStyle(NudgePrimaryButtonStyle())

                        Text("Keeps charge limits active across macOS sleep, Fast User Switching, and app closure.")
                            .font(.system(size: 11))
                            .foregroundStyle(palette.mutedForeground)
                    }
                }
            }

            // Enforcement & Safety Thresholds
            NudgeCard(
                title: "Background Enforcement & Thresholds",
                subtitle: "Fine-tune SMC behavior, Sailing Deadband, and Thermal Protection",
                symbol: "gearshape.2.fill"
            ) {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle(
                        isOn: Binding(
                            get: { config.stopChargingWhenAppClosed },
                            set: { val in manager.updateConfig { $0.stopChargingWhenAppClosed = val } }
                        )
                    ) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Stop Charging when App Closed")
                                .font(.system(size: 12.5, weight: .medium))
                            Text("Keep charge limit enforced via background helper even after quitting Nudge")
                                .font(.system(size: 11))
                                .foregroundStyle(palette.mutedForeground)
                        }
                    }
                    .toggleStyle(NudgeSwitchToggleStyle())

                    Toggle(
                        isOn: Binding(
                            get: { config.stopChargingWhenSleeping },
                            set: { val in manager.updateConfig { $0.stopChargingWhenSleeping = val } }
                        )
                    ) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Stop Charging when Sleeping")
                                .font(.system(size: 12.5, weight: .medium))
                            Text("Prevent battery from charging above target limit while lid is closed")
                                .font(.system(size: 11))
                                .foregroundStyle(palette.mutedForeground)
                        }
                    }
                    .toggleStyle(NudgeSwitchToggleStyle())

                    Toggle(
                        isOn: Binding(
                            get: { config.showHardwarePercentage },
                            set: { val in manager.updateConfig { $0.showHardwarePercentage = val } }
                        )
                    ) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Show Raw Hardware Percentage")
                                .font(.system(size: 12.5, weight: .medium))
                            Text("Display unsmoothed AppleSmartBattery cell percentage alongside macOS UI %")
                                .font(.system(size: 11))
                                .foregroundStyle(palette.mutedForeground)
                        }
                    }
                    .toggleStyle(NudgeSwitchToggleStyle())

                    NudgeSectionDivider()

                    // Sailing Deadband Slider
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Sailing Mode Deadband")
                                .font(.system(size: 12.5, weight: .semibold))
                            Spacer()
                            Text("-\(config.sailingDeadband)% (Resume at \(max(20, config.chargeLimit - config.sailingDeadband))%)")
                                .nudgeMetricFont(size: 12, weight: .semibold)
                                .foregroundStyle(palette.highlightText)
                        }

                        Slider(
                            value: Binding(
                                get: { Double(config.sailingDeadband) },
                                set: { val in manager.updateConfig { $0.sailingDeadband = Int(round(val)) } }
                            ),
                            in: 2...15,
                            step: 1
                        )
                        .tint(palette.primary)
                    }

                    // Heat Protection Threshold Slider
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Heat Protection Threshold")
                                .font(.system(size: 12.5, weight: .semibold))
                            Spacer()
                            Text(String(format: "%.0f°C", config.heatThresholdCelsius))
                                .nudgeMetricFont(size: 12, weight: .semibold)
                                .foregroundStyle(palette.foreground)
                        }

                        Slider(
                            value: Binding(
                                get: { config.heatThresholdCelsius },
                                set: { val in manager.updateConfig { $0.heatThresholdCelsius = round(val) } }
                            ),
                            in: 30...45,
                            step: 1
                        )
                        .tint(palette.primary)
                    }
                }
            }
        }
    }

    private func appearanceOptionCard(_ mode: NudgeAppearance) -> some View {
        let isSelected = NudgeAppearance.from(config.appearancePreference) == mode
        return Button {
            manager.updateConfig { $0.appearancePreference = mode.rawValue }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                // Visual mini-preview of Moss theme surface + sage primary pill
                themePreviewSwatch(for: mode)

                HStack(spacing: 6) {
                    Image(systemName: mode.symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isSelected ? palette.primaryForeground : palette.foreground)
                    Text(mode.label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isSelected ? palette.primaryForeground : palette.foreground)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(palette.primaryForeground)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: NudgeMetrics.controlRadius, style: .continuous)
                    .fill(isSelected ? palette.primary : palette.muted)
            )
            .overlay(
                RoundedRectangle(cornerRadius: NudgeMetrics.controlRadius, style: .continuous)
                    .strokeBorder(isSelected ? palette.ring : palette.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func themePreviewSwatch(for mode: NudgeAppearance) -> some View {
        switch mode {
        case .system:
            HStack(spacing: 0) {
                ZStack {
                    NudgePalette.light.background
                    HStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(NudgePalette.light.primary)
                            .frame(width: 12, height: 10)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(NudgePalette.light.secondary)
                            .frame(height: 10)
                    }
                    .padding(.horizontal, 5)
                }
                ZStack {
                    NudgePalette.dark.background
                    HStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(NudgePalette.dark.primary)
                            .frame(width: 12, height: 10)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(NudgePalette.dark.secondary)
                            .frame(height: 10)
                    }
                    .padding(.horizontal, 5)
                }
            }
            .frame(height: 28)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(palette.border, lineWidth: 1)
            )
        case .light, .dark:
            let previewPalette = mode == .dark ? NudgePalette.dark : NudgePalette.light
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(previewPalette.background)
                .frame(height: 28)
                .overlay(
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(previewPalette.primary)
                            .frame(width: 18, height: 10)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(previewPalette.accent)
                            .frame(width: 10, height: 10)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(previewPalette.secondary)
                            .frame(height: 10)
                    }
                    .padding(.horizontal, 6)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(previewPalette.border, lineWidth: 1)
                )
        }
    }

    private func daemonMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(palette.mutedForeground)
            Text(value)
                .nudgeMetricFont(size: 12.5, weight: .semibold)
                .foregroundStyle(palette.foreground)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: NudgeMetrics.controlRadius, style: .continuous)
                .fill(palette.muted.opacity(0.75))
        )
    }

    private func relativeTime(_ date: Date) -> String {
        let secs = max(0, Int(Date().timeIntervalSince(date)))
        if secs < 5 { return "Just now" }
        if secs < 60 { return "\(secs)s ago" }
        return "\(secs / 60)m ago"
    }
}

// MARK: - Menu Bar & Popover Layout Customizer

public struct LayoutCustomizerView: View {
    @Environment(\.nudgePalette) private var palette
    @ObservedObject var manager: BatteryManager

    public init(manager: BatteryManager) {
        self.manager = manager
    }

    private var orderedPopoverWidgets: [PopoverWidgetKind] {
        var result = manager.config.popoverWidgetOrder
        for kind in PopoverWidgetKind.allCases where !result.contains(kind) {
            result.append(kind)
        }
        return result
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Live macOS Menu Bar Preview Card
            NudgeCard(
                title: "Live Menu Bar Preview",
                subtitle: "Real-time render of your active macOS menu bar components",
                symbol: "menubar.rectangle",
                headerTrailing: {
                    Button("Reset Defaults") {
                        manager.updateConfig {
                            $0.menuBarComponents = [.liveIcon]
                            $0.popoverWidgetOrder = PopoverWidgetKind.allCases
                            $0.hiddenPopoverWidgets = []
                        }
                    }
                    .buttonStyle(NudgeSecondaryButtonStyle(compact: true))
                }
            ) {
                HStack {
                    Spacer()
                    MenuBarLabelView(manager: manager)
                        .foregroundStyle(palette.foreground)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Capsule(style: .continuous)
                                .fill(palette.muted)
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(palette.ring, lineWidth: 1.5)
                        )
                    Spacer()
                }
                .padding(.vertical, 4)
            }

            // Two-column drag-and-drop editors
            HStack(alignment: .top, spacing: 16) {
                menuBarEditorCard
                popoverWidgetEditorCard
            }
        }
    }

    private var menuBarEditorCard: some View {
        NudgeCard(
            title: "Menu Bar Items",
            subtitle: "Drag active items to reorder or toggle components below",
            symbol: "rectangle.topthird.inset.filled"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Active Order (Drag to Reorder)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.mutedForeground)

                let active = manager.config.menuBarComponents
                VStack(spacing: 6) {
                    ForEach(Array(active.enumerated()), id: \.element.id) { index, comp in
                        HStack(spacing: 8) {
                            Image(systemName: "line.3.horizontal")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(palette.mutedForeground)

                            Image(systemName: comp.symbolName)
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(palette.accentForeground)
                                .frame(width: 22, height: 22)
                                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(palette.accent))

                            Text(comp.rawValue)
                                .font(.system(size: 12, weight: .medium))

                            Spacer()

                            Button {
                                moveMenuBarItem(comp, offset: -1)
                            } label: {
                                Image(systemName: "chevron.up")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .buttonStyle(.plain)
                            .disabled(index == 0)
                            .opacity(index == 0 ? 0.35 : 1)

                            Button {
                                moveMenuBarItem(comp, offset: 1)
                            } label: {
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .buttonStyle(.plain)
                            .disabled(index == active.count - 1)
                            .opacity(index == active.count - 1 ? 0.35 : 1)

                            Button {
                                toggleMenuBarComponent(comp)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(palette.mutedForeground)
                            }
                            .buttonStyle(.plain)
                            .disabled(active.count <= 1)
                            .opacity(active.count <= 1 ? 0.35 : 1)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: NudgeMetrics.controlRadius, style: .continuous)
                                .fill(palette.muted.opacity(0.65))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: NudgeMetrics.controlRadius, style: .continuous)
                                .strokeBorder(palette.border, lineWidth: 1)
                        )
                        .draggable(comp.rawValue)
                        .dropDestination(for: String.self) { items, _ in
                            guard let raw = items.first,
                                  let source = MenuBarComponent(rawValue: raw) else { return false }
                            reorderMenuBarItem(source, before: comp)
                            return true
                        }
                    }
                }

                let inactive = MenuBarComponent.allCases.filter { !active.contains($0) }
                if !inactive.isEmpty {
                    NudgeSectionDivider()

                    Text("Available Components")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.mutedForeground)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                        ForEach(inactive) { comp in
                            Button {
                                toggleMenuBarComponent(comp)
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 11))
                                    Text(comp.rawValue)
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(NudgeSecondaryButtonStyle(compact: true))
                        }
                    }
                }
            }
        }
    }

    private var popoverWidgetEditorCard: some View {
        NudgeCard(
            title: "Popover Dashboard Widgets",
            subtitle: "Drag cards to customize your 420pt menu bar popover",
            symbol: "square.grid.2x2.fill"
        ) {
            let ordered = orderedPopoverWidgets
            let hidden = Set(manager.config.hiddenPopoverWidgets)

            VStack(spacing: 6) {
                ForEach(Array(ordered.enumerated()), id: \.element.id) { index, kind in
                    let isVisible = !hidden.contains(kind)
                    HStack(spacing: 8) {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.mutedForeground)

                        Image(systemName: kind.symbolName)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(isVisible ? palette.accentForeground : palette.mutedForeground)
                            .frame(width: 22, height: 22)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(isVisible ? palette.accent : palette.muted))

                        Text(kind.rawValue)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(isVisible ? palette.foreground : palette.mutedForeground)
                            .lineLimit(1)

                        Spacer()

                        Button {
                            movePopoverWidget(kind, offset: -1)
                        } label: {
                            Image(systemName: "chevron.up")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .buttonStyle(.plain)
                        .disabled(index == 0)
                        .opacity(index == 0 ? 0.35 : 1)

                        Button {
                            movePopoverWidget(kind, offset: 1)
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .buttonStyle(.plain)
                        .disabled(index == ordered.count - 1)
                        .opacity(index == ordered.count - 1 ? 0.35 : 1)

                        Button {
                            togglePopoverWidget(kind)
                        } label: {
                            Image(systemName: isVisible ? "eye.fill" : "eye.slash")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(isVisible ? palette.primaryForeground : palette.mutedForeground)
                                .frame(width: 26, height: 22)
                                .background(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(isVisible ? palette.primary : palette.muted)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: NudgeMetrics.controlRadius, style: .continuous)
                            .fill(palette.muted.opacity(0.65))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: NudgeMetrics.controlRadius, style: .continuous)
                            .strokeBorder(palette.border, lineWidth: 1)
                    )
                    .draggable(kind.rawValue)
                    .dropDestination(for: String.self) { items, _ in
                        guard let raw = items.first,
                              let source = PopoverWidgetKind(rawValue: raw) else { return false }
                        reorderPopoverWidget(source, before: kind)
                        return true
                    }
                }
            }
        }
    }

    // MARK: - Reorder Helpers

    private func toggleMenuBarComponent(_ comp: MenuBarComponent) {
        manager.updateConfig { cfg in
            if let idx = cfg.menuBarComponents.firstIndex(of: comp) {
                guard cfg.menuBarComponents.count > 1 else { return }
                cfg.menuBarComponents.remove(at: idx)
            } else {
                cfg.menuBarComponents.append(comp)
            }
        }
    }

    private func moveMenuBarItem(_ comp: MenuBarComponent, offset: Int) {
        var items = manager.config.menuBarComponents
        guard let idx = items.firstIndex(of: comp) else { return }
        let target = idx + offset
        guard target >= 0 && target < items.count else { return }
        withAnimation(.easeInOut(duration: 0.16)) {
            items.swapAt(idx, target)
            manager.updateConfig { $0.menuBarComponents = items }
        }
    }

    private func reorderMenuBarItem(_ source: MenuBarComponent, before target: MenuBarComponent) {
        guard source != target else { return }
        var items = manager.config.menuBarComponents
        guard let fromIdx = items.firstIndex(of: source),
              let toIdx = items.firstIndex(of: target) else { return }
        withAnimation(.easeInOut(duration: 0.16)) {
            let moved = items.remove(at: fromIdx)
            items.insert(moved, at: toIdx)
            manager.updateConfig { $0.menuBarComponents = items }
        }
    }

    private func togglePopoverWidget(_ kind: PopoverWidgetKind) {
        manager.updateConfig { cfg in
            if let idx = cfg.hiddenPopoverWidgets.firstIndex(of: kind) {
                cfg.hiddenPopoverWidgets.remove(at: idx)
            } else {
                cfg.hiddenPopoverWidgets.append(kind)
            }
        }
    }

    private func movePopoverWidget(_ kind: PopoverWidgetKind, offset: Int) {
        var order = orderedPopoverWidgets
        guard let idx = order.firstIndex(of: kind) else { return }
        let target = idx + offset
        guard target >= 0 && target < order.count else { return }
        withAnimation(.easeInOut(duration: 0.16)) {
            order.swapAt(idx, target)
            manager.updateConfig { $0.popoverWidgetOrder = order }
        }
    }

    private func reorderPopoverWidget(_ source: PopoverWidgetKind, before target: PopoverWidgetKind) {
        guard source != target else { return }
        var order = orderedPopoverWidgets
        guard let fromIdx = order.firstIndex(of: source),
              let toIdx = order.firstIndex(of: target) else { return }
        withAnimation(.easeInOut(duration: 0.16)) {
            let moved = order.remove(at: fromIdx)
            order.insert(moved, at: toIdx)
            manager.updateConfig { $0.popoverWidgetOrder = order }
        }
    }
}
