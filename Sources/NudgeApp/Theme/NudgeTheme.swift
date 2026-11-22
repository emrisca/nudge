import SwiftUI
import NudgeCore

// MARK: - Hex Color Support

public extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

// MARK: - Appearance Mode

public enum NudgeAppearance: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    public var symbol: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    public var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    public static func from(_ raw: String) -> NudgeAppearance {
        NudgeAppearance(rawValue: raw.lowercased()) ?? .system
    }
}

// MARK: - Light Green tweakcn Design System Palette

public struct NudgePalette: Sendable {
    public let isDark: Bool

    public let background: Color
    public let foreground: Color
    public let card: Color
    public let popover: Color
    public let primary: Color
    public let primaryForeground: Color
    public let secondary: Color
    public let secondaryForeground: Color
    public let muted: Color
    public let mutedForeground: Color
    public let accent: Color
    public let accentForeground: Color
    public let destructive: Color
    public let destructiveForeground: Color
    public let border: Color
    public let input: Color
    public let ring: Color

    public let chart1: Color
    public let chart2: Color
    public let chart3: Color
    public let chart4: Color
    public let chart5: Color

    public let warning: Color
    public let warningSoft: Color

    public let shadowColor: Color
    public let shadowRadius: CGFloat
    public let shadowY: CGFloat

    public static let light = NudgePalette(
        isDark: false,
        background: Color(hex: 0xFBFCF8),
        foreground: Color(hex: 0x0F172A),
        card: Color(hex: 0xFFFFFF),
        popover: Color(hex: 0xFFFFFF),
        primary: Color(hex: 0xAFF33E),
        primaryForeground: Color(hex: 0x000000),
        secondary: Color(hex: 0x334155),
        secondaryForeground: Color(hex: 0xF8FAFC),
        muted: Color(hex: 0xF1F5F9),
        mutedForeground: Color(hex: 0x64748B),
        accent: Color(hex: 0xF0FDF4),
        accentForeground: Color(hex: 0x166534),
        destructive: Color(hex: 0xEF4444),
        destructiveForeground: Color(hex: 0xFFFFFF),
        border: Color(hex: 0xE2E8F0),
        input: Color(hex: 0xE2E8F0),
        ring: Color(hex: 0xAFF33E),
        chart1: Color(hex: 0xAFF33E),
        chart2: Color(hex: 0x334155),
        chart3: Color(hex: 0x22C55E),
        chart4: Color(hex: 0x64748B),
        chart5: Color(hex: 0x94A3B8),
        warning: Color(hex: 0xF59E0B),
        warningSoft: Color(hex: 0xFEF3C7),
        shadowColor: Color.black.opacity(0.05),
        shadowRadius: 20,
        shadowY: 8
    )

    public static let dark = NudgePalette(
        isDark: true,
        background: Color(hex: 0x020617),
        foreground: Color(hex: 0xF8FAFC),
        card: Color(hex: 0x0F172A),
        popover: Color(hex: 0x0F172A),
        primary: Color(hex: 0xAFF33E),
        primaryForeground: Color(hex: 0x000000),
        secondary: Color(hex: 0x1E293B),
        secondaryForeground: Color(hex: 0xF8FAFC),
        muted: Color(hex: 0x1E293B),
        mutedForeground: Color(hex: 0x94A3B8),
        accent: Color(hex: 0x14532D),
        accentForeground: Color(hex: 0xAFF33E),
        destructive: Color(hex: 0x991B1B),
        destructiveForeground: Color(hex: 0xFFFFFF),
        border: Color(hex: 0x1E293B),
        input: Color(hex: 0x1E293B),
        ring: Color(hex: 0xAFF33E),
        chart1: Color(hex: 0xAFF33E),
        chart2: Color(hex: 0x3B82F6),
        chart3: Color(hex: 0x22C55E),
        chart4: Color(hex: 0xA855F7),
        chart5: Color(hex: 0xF59E0B),
        warning: Color(hex: 0xF59E0B),
        warningSoft: Color(hex: 0x451A03),
        shadowColor: Color.black.opacity(0.40),
        shadowRadius: 25,
        shadowY: 10
    )

    public static func forScheme(_ scheme: ColorScheme) -> NudgePalette {
        scheme == .dark ? .dark : .light
    }
}

// MARK: - Geometry & Typography Constants

public enum NudgeMetrics {
    public static let cardRadius: CGFloat = 16
    public static let controlRadius: CGFloat = 10
    public static let pillRadius: CGFloat = 999
    public static let borderWidth: CGFloat = 1
    public static let tightTracking: CGFloat = -0.2
    public static let popoverWidth: CGFloat = 420
}

// MARK: - Environment Key

private struct NudgePaletteKey: EnvironmentKey {
    static let defaultValue: NudgePalette = .light
}

public extension EnvironmentValues {
    var nudgePalette: NudgePalette {
        get { self[NudgePaletteKey.self] }
        set { self[NudgePaletteKey.self] = newValue }
    }
}

// MARK: - Theme Container Modifier

public struct NudgeThemedContainer: ViewModifier {
    @Environment(\.colorScheme) private var systemScheme
    let appearancePreference: String

    private var resolvedAppearance: NudgeAppearance {
        NudgeAppearance.from(appearancePreference)
    }

    private var effectiveScheme: ColorScheme {
        resolvedAppearance.colorScheme ?? systemScheme
    }

    public func body(content: Content) -> some View {
        let palette = NudgePalette.forScheme(effectiveScheme)
        content
            .environment(\.nudgePalette, palette)
            .preferredColorScheme(resolvedAppearance.colorScheme)
            .tint(palette.primary)
            .foregroundStyle(palette.foreground)
    }
}

public extension View {
    func nudgeThemed(appearance: String) -> some View {
        modifier(NudgeThemedContainer(appearancePreference: appearance))
    }

    func nudgeMetricFont(size: CGFloat, weight: Font.Weight = .semibold) -> some View {
        self
            .font(.system(size: size, weight: weight, design: .default))
            .monospacedDigit()
            .tracking(NudgeMetrics.tightTracking)
    }

    func nudgeHeadingFont(size: CGFloat, weight: Font.Weight = .semibold) -> some View {
        self
            .font(.system(size: size, weight: weight, design: .default))
            .tracking(NudgeMetrics.tightTracking)
    }
}

// MARK: - Shadcn-Style Button & Toggle Styles

public struct NudgePrimaryButtonStyle: ButtonStyle {
    @Environment(\.nudgePalette) private var palette
    var compact: Bool = false

    public init(compact: Bool = false) {
        self.compact = compact
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 11.5 : 12.5, weight: .semibold))
            .tracking(NudgeMetrics.tightTracking)
            .foregroundStyle(palette.primaryForeground)
            .padding(.horizontal, compact ? 10 : 14)
            .padding(.vertical, compact ? 6 : 8)
            .background(
                RoundedRectangle(cornerRadius: NudgeMetrics.controlRadius, style: .continuous)
                    .fill(palette.primary.opacity(configuration.isPressed ? 0.85 : 1.0))
            )
            .overlay(
                RoundedRectangle(cornerRadius: NudgeMetrics.controlRadius, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

public struct NudgeSecondaryButtonStyle: ButtonStyle {
    @Environment(\.nudgePalette) private var palette
    var compact: Bool = false

    public init(compact: Bool = false) {
        self.compact = compact
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 11.5 : 12.5, weight: .medium))
            .tracking(NudgeMetrics.tightTracking)
            .foregroundStyle(palette.foreground)
            .padding(.horizontal, compact ? 10 : 12)
            .padding(.vertical, compact ? 6 : 8)
            .background(
                RoundedRectangle(cornerRadius: NudgeMetrics.controlRadius, style: .continuous)
                    .fill(configuration.isPressed ? palette.muted.opacity(0.8) : palette.muted)
            )
            .overlay(
                RoundedRectangle(cornerRadius: NudgeMetrics.controlRadius, style: .continuous)
                    .strokeBorder(palette.border, lineWidth: NudgeMetrics.borderWidth)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

public struct NudgePillToggleButtonStyle: ButtonStyle {
    @Environment(\.nudgePalette) private var palette
    let isActive: Bool
    var activeFill: Color? = nil
    var activeForeground: Color? = nil

    public init(isActive: Bool, activeFill: Color? = nil, activeForeground: Color? = nil) {
        self.isActive = isActive
        self.activeFill = activeFill
        self.activeForeground = activeForeground
    }

    public func makeBody(configuration: Configuration) -> some View {
        let fill = isActive ? (activeFill ?? palette.primary) : palette.muted
        let fg = isActive ? (activeForeground ?? palette.primaryForeground) : palette.foreground
        let stroke = isActive ? (activeFill ?? palette.primary).opacity(0.6) : palette.border

        return configuration.label
            .font(.system(size: 11.5, weight: isActive ? .semibold : .medium))
            .tracking(NudgeMetrics.tightTracking)
            .foregroundStyle(fg)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: NudgeMetrics.controlRadius, style: .continuous)
                    .fill(fill.opacity(configuration.isPressed ? 0.85 : 1.0))
            )
            .overlay(
                RoundedRectangle(cornerRadius: NudgeMetrics.controlRadius, style: .continuous)
                    .strokeBorder(stroke, lineWidth: NudgeMetrics.borderWidth)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.16), value: isActive)
    }
}

public struct NudgeDestructiveButtonStyle: ButtonStyle {
    @Environment(\.nudgePalette) private var palette
    var compact: Bool = true

    public init(compact: Bool = true) {
        self.compact = compact
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 11 : 12.5, weight: .semibold))
            .foregroundStyle(palette.destructiveForeground)
            .padding(.horizontal, compact ? 8 : 12)
            .padding(.vertical, compact ? 5 : 7)
            .background(
                RoundedRectangle(cornerRadius: NudgeMetrics.controlRadius, style: .continuous)
                    .fill(palette.destructive.opacity(configuration.isPressed ? 0.8 : 1.0))
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

public struct NudgeIconButtonStyle: ButtonStyle {
    @Environment(\.nudgePalette) private var palette
    var isActive: Bool = false

    public init(isActive: Bool = false) {
        self.isActive = isActive
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(isActive ? palette.primaryForeground : palette.mutedForeground)
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        isActive
                            ? palette.primary
                            : (configuration.isPressed ? palette.muted : Color.clear)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isActive ? palette.primary : palette.border.opacity(0.8), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

public struct NudgeSwitchToggleStyle: ToggleStyle {
    @Environment(\.nudgePalette) private var palette

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer(minLength: 8)
            Button {
                withAnimation(.spring(response: 0.22, dampingFraction: 0.78)) {
                    configuration.isOn.toggle()
                }
            } label: {
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule(style: .continuous)
                        .fill(configuration.isOn ? palette.primary : palette.muted)
                        .frame(width: 36, height: 20)
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(
                                    configuration.isOn ? palette.primary.opacity(0.6) : palette.border,
                                    lineWidth: 1
                                )
                        )

                    Circle()
                        .fill(configuration.isOn ? palette.primaryForeground : palette.card)
                        .frame(width: 14, height: 14)
                        .shadow(color: Color.black.opacity(0.14), radius: 2, y: 1)
                        .padding(3)
                }
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isButton)
        }
    }
}

// MARK: - ChargingState Display Helpers

public extension ChargingState {
    var displayTitle: String {
        switch self {
        case .charging: return "Charging"
        case .discharging: return "Discharging"
        case .paused: return "Charge Paused"
        case .sailing: return "Sailing"
        case .overheated: return "Overheated"
        case .calibrating: return "Calibrating"
        case .unplugged: return "On Battery"
        case .unknown: return "Standby"
        }
    }

    var symbolName: String {
        switch self {
        case .charging: return "bolt.fill"
        case .discharging: return "arrow.down.circle.fill"
        case .paused: return "pause.circle.fill"
        case .sailing: return "wind"
        case .overheated: return "thermometer.sun.fill"
        case .calibrating: return "arrow.triangle.2.circlepath"
        case .unplugged: return "battery.75percent"
        case .unknown: return "questionmark.circle"
        }
    }

    func badgeColors(in palette: NudgePalette) -> (background: Color, foreground: Color, dot: Color) {
        switch self {
        case .charging:
            return (palette.primary, palette.primaryForeground, palette.primaryForeground)
        case .sailing, .paused:
            return (palette.accent, palette.accentForeground, palette.chart3)
        case .discharging:
            return (palette.warningSoft, palette.isDark ? palette.warning : Color(hex: 0x92400E), palette.warning)
        case .overheated:
            return (palette.destructive.opacity(palette.isDark ? 0.85 : 0.14), palette.isDark ? palette.destructiveForeground : palette.destructive, palette.destructive)
        case .calibrating:
            return (palette.chart2.opacity(0.16), palette.isDark ? Color(hex: 0x93C5FD) : palette.secondary, palette.chart2)
        case .unplugged, .unknown:
            return (palette.muted, palette.mutedForeground, palette.mutedForeground)
        }
    }
}

public extension PopoverWidgetKind {
    var symbolName: String {
        switch self {
        case .chargeControl: return "bolt.batteryblock.fill"
        case .powerFlow: return "arrow.left.arrow.right.circle.fill"
        case .historicalCharts: return "chart.xyaxis.line"
        case .batterySpecs: return "cpu.fill"
        case .highEnergyApps: return "flame.fill"
        case .sleepAndPowerMode: return "moon.stars.fill"
        case .schedule: return "calendar.badge.clock"
        case .calibrationAndLED: return "gauge.with.dots.needle.67percent"
        }
    }

    var shortTitle: String {
        switch self {
        case .chargeControl: return "Charge Control"
        case .powerFlow: return "Power Flow"
        case .historicalCharts: return "History"
        case .batterySpecs: return "Hardware Specs"
        case .highEnergyApps: return "Energy Apps"
        case .sleepAndPowerMode: return "Sleep & Power"
        case .schedule: return "Schedule"
        case .calibrationAndLED: return "Calibration & LED"
        }
    }
}

public extension MenuBarComponent {
    var symbolName: String {
        switch self {
        case .liveIcon: return "bolt.batteryblock"
        case .displayPercentage: return "percent"
        case .hardwarePercentage: return "cpu"
        case .temperature: return "thermometer.medium"
        case .powerFlow: return "bolt.horizontal.fill"
        case .cycles: return "arrow.2.squarepath"
        case .maxCapacity: return "heart.fill"
        }
    }
}
