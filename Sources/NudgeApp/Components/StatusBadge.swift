import SwiftUI
import NudgeCore

public struct ChargingStateBadge: View {
    @Environment(\.nudgePalette) private var palette
    let state: ChargingState
    var compact: Bool = false

    public init(state: ChargingState, compact: Bool = false) {
        self.state = state
        self.compact = compact
    }

    public var body: some View {
        let colors = state.badgeColors(in: palette)
        HStack(spacing: 5) {
            Circle()
                .fill(colors.dot)
                .frame(width: 6, height: 6)
            Text(state.displayTitle)
                .font(.system(size: compact ? 10.5 : 11, weight: .semibold))
                .tracking(NudgeMetrics.tightTracking)
        }
        .foregroundStyle(colors.foreground)
        .padding(.horizontal, compact ? 8 : 9)
        .padding(.vertical, compact ? 3.5 : 4.5)
        .background(
            Capsule(style: .continuous)
                .fill(colors.background)
        )
    }
}

public struct NudgeTagPill: View {
    @Environment(\.nudgePalette) private var palette

    let text: String
    var symbol: String? = nil
    var style: Style = .muted

    public enum Style {
        case primary
        case accent
        case muted
        case warning
        case destructive
    }

    public init(_ text: String, symbol: String? = nil, style: Style = .muted) {
        self.text = text
        self.symbol = symbol
        self.style = style
    }

    public var body: some View {
        let (bg, fg) = resolvedColors
        HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .semibold))
            }
            Text(text)
                .font(.system(size: 10.5, weight: .semibold))
                .monospacedDigit()
                .tracking(NudgeMetrics.tightTracking)
        }
        .foregroundStyle(fg)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(bg)
        )
    }

    private var resolvedColors: (Color, Color) {
        switch style {
        case .primary:
            return (palette.primary, palette.primaryForeground)
        case .accent:
            return (palette.accent, palette.accentForeground)
        case .muted:
            return (palette.muted, palette.mutedForeground)
        case .warning:
            return (palette.warningSoft, palette.isDark ? palette.warning : Color(hex: 0x92400E))
        case .destructive:
            return (palette.destructive, palette.destructiveForeground)
        }
    }
}

public struct NudgeBrandBadge: View {
    @Environment(\.nudgePalette) private var palette
    var size: CGFloat = 26

    public init(size: CGFloat = 26) {
        self.size = size
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                .fill(palette.primary)
                .frame(width: size, height: size)
            Image(systemName: "bolt.fill")
                .font(.system(size: size * 0.52, weight: .bold))
                .foregroundStyle(palette.primaryForeground)
        }
    }
}
