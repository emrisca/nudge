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

// MARK: - Moss tweakcn Design System Palette

public struct NudgePalette: Sendable {
    public let isDark: Bool

    public let background: Color
    public let foreground: Color
    public let card: Color
    public let cardForeground: Color
    public let popover: Color
    public let popoverForeground: Color
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

    public let sidebar: Color
    public let sidebarForeground: Color
    public let sidebarPrimary: Color
    public let sidebarPrimaryForeground: Color
    public let sidebarAccent: Color
    public let sidebarAccentForeground: Color
    public let sidebarBorder: Color
    public let sidebarRing: Color

    public let chart1: Color
    public let chart2: Color
    public let chart3: Color
    public let chart4: Color
    public let chart5: Color

    public let warning: Color
    public let warningSoft: Color
    public let statusPositive: Color
    public let highlightText: Color

    public let shadowColor: Color
    public let shadowRadius: CGFloat
    public let shadowY: CGFloat

    public static let light = NudgePalette(
        isDark: false,
        background: Color(hex: 0xFDFDFD),
        foreground: Color(hex: 0x000000),
        card: Color(hex: 0xFDFDFD),
        cardForeground: Color(hex: 0x000000),
        popover: Color(hex: 0xFCFCFC),
        popoverForeground: Color(hex: 0x000000),
        primary: Color(hex: 0x7F956A),
        primaryForeground: Color(hex: 0xFAFAF9),
        secondary: Color(hex: 0xD4D9D0),
        secondaryForeground: Color(hex: 0x080808),
        muted: Color(hex: 0xF5F5F5),
        mutedForeground: Color(hex: 0x878787),
        accent: Color(hex: 0x495940),
        accentForeground: Color(hex: 0xFFFFFF),
        destructive: Color(hex: 0xB3191F),
        destructiveForeground: Color(hex: 0xFFFFFF),
        border: Color(hex: 0xE7E7EE),
        input: Color(hex: 0xEBEBEB),
        ring: Color(hex: 0xAFBEA5),
        sidebar: Color(hex: 0xF5F8FB),
        sidebarForeground: Color(hex: 0x000000),
        sidebarPrimary: Color(hex: 0x000000),
        sidebarPrimaryForeground: Color(hex: 0xFFFFFF),
        sidebarAccent: Color(hex: 0xE4EAE1),
        sidebarAccentForeground: Color(hex: 0x000000),
        sidebarBorder: Color(hex: 0xEBEBEB),
        sidebarRing: Color(hex: 0xAFBEA5),
        chart1: Color(hex: 0x5EA500),
        chart2: Color(hex: 0xF29F9B),
        chart3: Color(hex: 0xFFDA1A),
        chart4: Color(hex: 0x0051BA),
        chart5: Color(hex: 0xA6A09B),
        warning: Color(hex: 0xC27803),
        warningSoft: Color(hex: 0xFEF3C7),
        statusPositive: Color(hex: 0x5EA500),
        highlightText: Color(hex: 0x495940),
        shadowColor: Color(hex: 0x000000, alpha: 0.16),
        shadowRadius: 3,
        shadowY: 2
    )

    public static let dark = NudgePalette(
        isDark: true,
        background: Color(hex: 0x070503),
        foreground: Color(hex: 0xF9F8F7),
        card: Color(hex: 0x100D08),
        cardForeground: Color(hex: 0xF9F8F7),
        popover: Color(hex: 0x0B0905),
        popoverForeground: Color(hex: 0xF9F8F7),
        primary: Color(hex: 0xAFBEA5),
        primaryForeground: Color(hex: 0x040302),
        secondary: Color(hex: 0x26211A),
        secondaryForeground: Color(hex: 0xE7E4DF),
        muted: Color(hex: 0x1E1A14),
        mutedForeground: Color(hex: 0x928F8A),
        accent: Color(hex: 0x495940),
        accentForeground: Color(hex: 0xFFFFFF),
        destructive: Color(hex: 0xB3191F),
        destructiveForeground: Color(hex: 0xF9F8F7),
        border: Color(hex: 0x2F281B),
        input: Color(hex: 0x1A150E),
        ring: Color(hex: 0xAFBEA5),
        sidebar: Color(hex: 0x040302),
        sidebarForeground: Color(hex: 0xF0EEEB),
        sidebarPrimary: Color(hex: 0xAFBEA5),
        sidebarPrimaryForeground: Color(hex: 0x040302),
        sidebarAccent: Color(hex: 0x495940),
        sidebarAccentForeground: Color(hex: 0xFFFFFF),
        sidebarBorder: Color(hex: 0x272117),
        sidebarRing: Color(hex: 0xAFBEA5),
        chart1: Color(hex: 0x408A0F),
        chart2: Color(hex: 0x59A626),
        chart3: Color(hex: 0x73BD42),
        chart4: Color(hex: 0xA9E382),
        chart5: Color(hex: 0xAFBEA5),
        warning: Color(hex: 0xF59E0B),
        warningSoft: Color(hex: 0x2F220B),
        statusPositive: Color(hex: 0x73BD42),
        highlightText: Color(hex: 0xAFBEA5),
        shadowColor: Color(hex: 0x000000, alpha: 0.35),
        shadowRadius: 12,
        shadowY: 2
    )

    public static func forScheme(_ scheme: ColorScheme) -> NudgePalette {
        scheme == .dark ? .dark : .light
    }
}

// MARK: - Geometry & Typography Constants

public enum NudgeMetrics {
    public static let cardRadius: CGFloat = 20
    public static let controlRadius: CGFloat = 12
    public static let pillRadius: CGFloat = 999
    public static let borderWidth: CGFloat = 1
    public static let tightTracking: CGFloat = -0.3
    public static let popoverWidth: CGFloat = 444
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
            .padding(.horizontal, compact ? 11 : 14)
            .padding(.vertical, compact ? 6 : 8)
            .background(
                RoundedRectangle(cornerRadius: NudgeMetrics.controlRadius, style: .continuous)
                    .fill(palette.primary.opacity(configuration.isPressed ? 0.85 : 1.0))
            )
            .overlay(
                RoundedRectangle(cornerRadius: NudgeMetrics.controlRadius, style: .continuous)
                    .strokeBorder(palette.ring.opacity(0.4), lineWidth: 1)
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
            .foregroundStyle(palette.secondaryForeground)
            .padding(.horizontal, compact ? 10 : 12)
            .padding(.vertical, compact ? 6 : 8)
            .background(
                RoundedRectangle(cornerRadius: NudgeMetrics.controlRadius, style: .continuous)
                    .fill(configuration.isPressed ? palette.secondary.opacity(0.8) : palette.secondary)
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
        let stroke = isActive ? (activeFill ?? palette.ring).opacity(0.7) : palette.border

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
            .tracking(NudgeMetrics.tightTracking)
            .foregroundStyle(palette.destructiveForeground)
            .padding(.horizontal, compact ? 9 : 12)
            .padding(.vertical, compact ? 5 : 7)
            .background(
                RoundedRectangle(cornerRadius: NudgeMetrics.controlRadius, style: .continuous)
                    .fill(palette.destructive.opacity(configuration.isPressed ? 0.82 : 1.0))
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
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(
                        isActive
                            ? palette.primary
                            : (configuration.isPressed ? palette.secondary : Color.clear)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(isActive ? palette.ring : palette.border.opacity(0.85), lineWidth: 1)
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
                        .fill(configuration.isOn ? palette.primary : palette.input)
                        .frame(width: 36, height: 20)
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(
                                    configuration.isOn ? palette.ring.opacity(0.75) : palette.border,
                                    lineWidth: 1
                                )
                        )

                    Circle()
                        .fill(
                            configuration.isOn
                                ? palette.primaryForeground
                                : (palette.isDark ? palette.secondaryForeground : palette.card)
                        )
                        .frame(width: 14, height: 14)
                        .shadow(color: palette.shadowColor, radius: 2, y: 1)
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
            return (palette.accent, palette.accentForeground, palette.ring)
        case .discharging:
            return (palette.warningSoft, palette.isDark ? palette.warning : Color(hex: 0x78350F), palette.warning)
        case .overheated:
            return (
                palette.destructive.opacity(palette.isDark ? 0.92 : 0.12),
                palette.isDark ? palette.destructiveForeground : palette.destructive,
                palette.isDark ? palette.destructiveForeground : palette.destructive
            )
        case .calibrating:
            return (palette.secondary, palette.secondaryForeground, palette.highlightText)
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
