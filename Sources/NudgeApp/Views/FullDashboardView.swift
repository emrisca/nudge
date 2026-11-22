import SwiftUI
import AppKit
import NudgeCore

public enum DashboardSection: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case powerAndCharts = "Power Flow & Charts"
    case controlsAndModes = "Controls & Modes"
    case scheduleAndShortcuts = "Schedule & Shortcuts"
    case layoutCustomizer = "Layout Customizer"
    case settings = "System & Settings"

    public var id: String { rawValue }

    public var symbol: String {
        switch self {
        case .overview: return "square.grid.2x2.fill"
        case .powerAndCharts: return "bolt.horizontal.fill"
        case .controlsAndModes: return "slider.horizontal.3"
        case .scheduleAndShortcuts: return "calendar.badge.clock"
        case .layoutCustomizer: return "menubar.rectangle"
        case .settings: return "gearshape.fill"
        }
    }

    public var subtitle: String {
        switch self {
        case .overview: return "Live battery charge control, power distribution, and cell health"
        case .powerAndCharts: return "Real-time wattage telemetry, historical Swift Charts, and high-energy processes"
        case .controlsAndModes: return "Charge limit, sailing deadband, sleep assertions, calibration, and MagSafe LED"
        case .scheduleAndShortcuts: return "Automated routines, wake catch-up, and Apple Shortcuts AppIntents"
        case .layoutCustomizer: return "Drag-and-drop customization for your macOS Menu Bar and Popover Dashboard"
        case .settings: return "Privileged background helper daemon, appearance, and hardware thresholds"
        }
    }
}

public struct FullDashboardView: View {
    @Environment(\.nudgePalette) private var palette
    @ObservedObject var manager: BatteryManager
    @ObservedObject var navigation: NudgeNavigationController
    @ObservedObject private var updater = UpdateManager.shared

    @MainActor
    public init(manager: BatteryManager) {
        self.manager = manager
        self.navigation = .shared
    }

    public init(manager: BatteryManager, navigation: NudgeNavigationController) {
        self.manager = manager
        self.navigation = navigation
    }

    private var snapshot: BatterySnapshot { manager.latestSnapshot }
    private var selectedSection: DashboardSection { navigation.selectedSection }

    public var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle()
                .fill(palette.sidebarBorder)
                .frame(width: 1)
            mainContent
        }
        .background(palette.background)
        .frame(minWidth: 920, minHeight: 640)
    }

    // MARK: - Sidebar (Moss tweakcn sidebar tokens)

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Brand Header
            HStack(spacing: 10) {
                NudgeBrandBadge(size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Nudge")
                        .nudgeHeadingFont(size: 16, weight: .bold)
                        .foregroundStyle(palette.sidebarForeground)
                    Text("Battery Intelligence")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(palette.mutedForeground)
                }
                Spacer()
            }
            .padding(.horizontal, 4)

            // Live Mini Battery Summary Tile
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(snapshot.displayPercentage)%")
                        .nudgeMetricFont(size: 26, weight: .bold)
                        .foregroundStyle(palette.cardForeground)
                    Spacer()
                    ChargingStateBadge(state: snapshot.state, compact: true)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule(style: .continuous).fill(palette.muted)
                        Capsule(style: .continuous)
                            .fill(palette.primary)
                            .frame(width: max(6, geo.size.width * CGFloat(snapshot.displayPercentage) / 100.0))
                    }
                }
                .frame(height: 6)

                HStack {
                    Text("Limit \(manager.config.chargeLimit)%")
                    Spacer()
                    Text(String(format: "%.1f°C · %+.1fW", snapshot.temperatureCelsius, snapshot.powerFlow.batteryWatts))
                }
                .font(.system(size: 10, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(palette.mutedForeground)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: NudgeMetrics.controlRadius, style: .continuous)
                    .fill(palette.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: NudgeMetrics.controlRadius, style: .continuous)
                    .strokeBorder(palette.sidebarBorder, lineWidth: 1)
            )

            // Navigation Links
            VStack(alignment: .leading, spacing: 4) {
                Text("NAVIGATION")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(palette.mutedForeground)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 2)

                ForEach(DashboardSection.allCases) { section in
                    let isSelected = selectedSection == section
                    Button {
                        withAnimation(.easeInOut(duration: 0.14)) {
                            navigation.selectedSection = section
                        }
                    } label: {
                        HStack(spacing: 9) {
                            Image(systemName: section.symbol)
                                .font(.system(size: 12, weight: .semibold))
                                .frame(width: 18)
                            Text(section.rawValue)
                                .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                                .tracking(NudgeMetrics.tightTracking)
                            Spacer()
                        }
                        .foregroundStyle(isSelected ? palette.sidebarAccentForeground : palette.sidebarForeground)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: NudgeMetrics.controlRadius, style: .continuous)
                                .fill(isSelected ? palette.sidebarAccent : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: NudgeMetrics.controlRadius, style: .continuous)
                                .strokeBorder(isSelected ? palette.sidebarRing.opacity(0.45) : Color.clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            // Quick Theme Switcher & Updater Indicator in Sidebar Footer
            VStack(alignment: .leading, spacing: 8) {
                if updater.hasUnignoredUpdate, let release = updater.availableRelease {
                    Button {
                        withAnimation(.easeInOut(duration: 0.14)) {
                            navigation.selectedSection = .settings
                        }
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Update \(release.displayVersion)")
                                .font(.system(size: 11.5, weight: .semibold))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9.5, weight: .bold))
                        }
                        .foregroundStyle(palette.primaryForeground)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: NudgeMetrics.controlRadius, style: .continuous)
                                .fill(palette.primary)
                        )
                    }
                    .buttonStyle(.plain)
                    .help("Open Software Updates in Settings")
                }
                HStack(spacing: 4) {
                    ForEach(NudgeAppearance.allCases) { mode in
                        let isSelected = NudgeAppearance.from(manager.config.appearancePreference) == mode
                        Button {
                            manager.updateConfig { $0.appearancePreference = mode.rawValue }
                        } label: {
                            Image(systemName: mode.symbol)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(isSelected ? palette.sidebarPrimaryForeground : palette.mutedForeground)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(isSelected ? palette.sidebarPrimary : Color.clear)
                                )
                        }
                        .buttonStyle(.plain)
                        .help("\(mode.label) Appearance")
                    }
                }
                .padding(3)
                .background(
                    RoundedRectangle(cornerRadius: NudgeMetrics.controlRadius, style: .continuous)
                        .fill(palette.isDark ? palette.muted : palette.sidebarAccent)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: NudgeMetrics.controlRadius, style: .continuous)
                        .strokeBorder(palette.sidebarBorder, lineWidth: 1)
                )

                HStack(spacing: 6) {
                    Circle()
                        .fill(manager.daemonStatus.isConnected ? palette.statusPositive : palette.warning)
                        .frame(width: 7, height: 7)
                    Text(manager.daemonStatus.isConnected ? "Helper Connected" : "Helper Offline")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(palette.mutedForeground)
                    Spacer()
                    Text("v\(updater.currentVersionString) · \(snapshot.architecture == .appleSilicon ? "ARM64" : "x86_64")")
                        .nudgeMetricFont(size: 10, weight: .semibold)
                        .foregroundStyle(palette.mutedForeground)
                }
                .padding(.horizontal, 4)
            }
        }
        .padding(16)
        .frame(width: 240)
        .background(palette.sidebar)
    }

    // MARK: - Main Content Area

    private var mainContent: some View {
        VStack(spacing: 0) {
            // Top bar
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedSection.rawValue)
                        .nudgeHeadingFont(size: 20, weight: .bold)
                        .foregroundStyle(palette.foreground)
                    Text(selectedSection.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(palette.mutedForeground)
                }

                Spacer()

                HStack(spacing: 8) {
                    NudgeTagPill(
                        manager.currentPowerMode.rawValue,
                        symbol: "bolt.circle",
                        style: .secondary
                    )

                    Button {
                        _ = manager.tick()
                        manager.refreshHighEnergyApps()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(NudgeSecondaryButtonStyle(compact: true))
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(palette.card)

            NudgeSectionDivider()

            ScrollView(.vertical, showsIndicators: true) {
                Group {
                    switch selectedSection {
                    case .overview:
                        overviewContent
                    case .powerAndCharts:
                        powerAndChartsContent
                    case .controlsAndModes:
                        controlsAndModesContent
                    case .scheduleAndShortcuts:
                        scheduleAndShortcutsContent
                    case .layoutCustomizer:
                        LayoutCustomizerView(manager: manager)
                    case .settings:
                        SettingsView(manager: manager)
                    }
                }
                .padding(24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Section Views

    private var overviewContent: some View {
        VStack(spacing: 16) {
            // 4 KPI Hero Row
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ],
                spacing: 12
            ) {
                kpiTile(
                    title: "Battery Charge",
                    value: "\(snapshot.displayPercentage)%",
                    detail: String(format: "Raw HW %.1f%% · Limit %d%%", snapshot.rawHardwarePercentage, manager.config.chargeLimit),
                    symbol: "bolt.batteryblock.fill",
                    accent: true
                )
                kpiTile(
                    title: "Net Power Flow",
                    value: String(format: "%+.1fW", snapshot.powerFlow.batteryWatts),
                    detail: String(format: "Adapter %.1fW · Load %.1fW", snapshot.powerFlow.chargerInputWatts, snapshot.powerFlow.systemLoadWatts),
                    symbol: "bolt.horizontal.fill"
                )
                kpiTile(
                    title: "Cell Temperature",
                    value: String(format: "%.1f°C", snapshot.temperatureCelsius),
                    detail: manager.latestTick.heatProtectionActive ? "Heat Protection Engaged" : "Limit \(Int(manager.config.heatThresholdCelsius))°C",
                    symbol: "thermometer.medium"
                )
                kpiTile(
                    title: "Health & Cycles",
                    value: String(format: "%.1f%%", snapshot.healthPercentage),
                    detail: "\(snapshot.cycleCount) cycles · \(snapshot.maxCapacityMah) mAh",
                    symbol: "heart.fill"
                )
            }

            // 2-Column Main Cards
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 16) {
                    ChargeControlWidget(manager: manager)
                    PowerFlowWidget(manager: manager)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 16) {
                    HistoricalChartsWidget(manager: manager, chartHeight: 195)
                    BatterySpecsWidget(manager: manager)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var powerAndChartsContent: some View {
        VStack(spacing: 16) {
            HistoricalChartsWidget(manager: manager, chartHeight: 240)

            HStack(alignment: .top, spacing: 16) {
                PowerFlowWidget(manager: manager)
                    .frame(maxWidth: .infinity)
                HighEnergyAppsWidget(manager: manager, maxVisibleCount: 10)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var controlsAndModesContent: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 16) {
                ChargeControlWidget(manager: manager)
                CalibrationAndLEDWidget(manager: manager)
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 16) {
                SleepAndPowerModeWidget(manager: manager)
                BatterySpecsWidget(manager: manager)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var scheduleAndShortcutsContent: some View {
        HStack(alignment: .top, spacing: 16) {
            ScheduleWidget(manager: manager)
                .frame(maxWidth: .infinity)

            shortcutsDirectoryCard
                .frame(maxWidth: .infinity)
        }
    }

    private var shortcutsDirectoryCard: some View {
        let actions: [(title: String, phrase: String, desc: String, symbol: String)] = [
            ("Battery Status", "\"Check battery status in Nudge\"", "Returns macOS %, Hardware %, temperature, state & power flow", "battery.75percent"),
            ("Get Charge Limit", "\"What is my charge limit in Nudge\"", "Reads the currently enforced hardware SMC ceiling", "gauge.with.dots.needle.67percent"),
            ("Set Charge Limit", "\"Set charge limit in Nudge\"", "Configures battery charge ceiling between 20% and 100%", "slider.horizontal.3"),
            ("Top Up to 100%", "\"Top up my battery in Nudge\"", "Temporarily charges to 100% until physical unplug", "bolt.batteryblock.fill"),
            ("Start Discharge", "\"Start battery discharge in Nudge\"", "Forces battery drain while connected to AC power", "battery.25percent"),
            ("Stop Discharge", "\"Resume normal charging in Nudge\"", "Halts manual discharge and restores target limit", "battery.100percent.bolt"),
            ("Battery Temperature", "\"Check battery temperature in Nudge\"", "Queries live IOKit cell thermal telemetry in °C", "thermometer.medium"),
            ("Calibrate Battery", "\"Start battery calibration in Nudge\"", "Starts automated 100% → 10% → 100% → Limit cycle", "arrow.triangle.2.circlepath"),
            ("Set Power Mode", "\"Set power mode in Nudge\"", "Switches macOS Low Power, Automatic, or High Power mode", "bolt.circle"),
            ("Keep Mac Awake", "\"Keep my Mac awake in Nudge\"", "Enables timed wake assertion with battery fallback safety", "cup.and.saucer.fill")
        ]

        return NudgeCard(
            title: "Apple Shortcuts & AppIntents",
            subtitle: "10 native macOS Shortcuts & Siri actions via NudgeShortcutsProvider",
            symbol: "square.stack.3d.up.fill",
            headerTrailing: {
                Button {
                    if let url = URL(string: "shortcuts://") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("Open Shortcuts", systemImage: "arrow.up.right")
                }
                .buttonStyle(NudgePrimaryButtonStyle(compact: true))
            }
        ) {
            VStack(spacing: 7) {
                ForEach(actions, id: \.title) { item in
                    HStack(spacing: 10) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(palette.accentForeground)
                            .frame(width: 26, height: 26)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(palette.accent)
                            )

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(item.title)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(palette.foreground)
                                Text(item.phrase)
                                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                    .foregroundStyle(palette.mutedForeground)
                                    .lineLimit(1)
                            }
                            Text(item.desc)
                                .font(.system(size: 10.5))
                                .foregroundStyle(palette.mutedForeground)
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: NudgeMetrics.controlRadius, style: .continuous)
                            .fill(palette.muted.opacity(0.65))
                    )
                }
            }
        }
    }

    private func kpiTile(title: String, value: String, detail: String, symbol: String, accent: Bool = false) -> some View {
        NudgeCard(padding: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.mutedForeground)
                    Spacer()
                    Image(systemName: symbol)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(accent ? palette.primaryForeground : palette.accentForeground)
                        .frame(width: 26, height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(accent ? palette.primary : palette.accent)
                        )
                }

                Text(value)
                    .nudgeMetricFont(size: 24, weight: .bold)
                    .foregroundStyle(palette.cardForeground)

                Text(detail)
                    .font(.system(size: 10.5, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(palette.mutedForeground)
                    .lineLimit(1)
            }
        }
    }
}
