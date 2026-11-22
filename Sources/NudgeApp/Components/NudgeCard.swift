import SwiftUI
import NudgeCore

public struct NudgeCard<HeaderTrailing: View, Content: View>: View {
    @Environment(\.nudgePalette) private var palette

    let title: String?
    let subtitle: String?
    let symbol: String?
    let padding: CGFloat
    let headerTrailing: HeaderTrailing
    let content: Content

    public init(
        title: String? = nil,
        subtitle: String? = nil,
        symbol: String? = nil,
        padding: CGFloat = 15,
        @ViewBuilder headerTrailing: () -> HeaderTrailing = { EmptyView() },
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.padding = padding
        self.headerTrailing = headerTrailing()
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if title != nil || symbol != nil {
                HStack(alignment: .center, spacing: 9) {
                    if let symbol {
                        Image(systemName: symbol)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(palette.accentForeground)
                            .frame(width: 26, height: 26)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(palette.accent)
                            )
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        if let title {
                            Text(title)
                                .nudgeHeadingFont(size: 13, weight: .semibold)
                                .foregroundStyle(palette.cardForeground)
                        }
                        if let subtitle {
                            Text(subtitle)
                                .font(.system(size: 11, weight: .regular))
                                .foregroundStyle(palette.mutedForeground)
                        }
                    }

                    Spacer(minLength: 4)
                    headerTrailing
                }
            }

            content
        }
        .padding(padding)
        .background(
            RoundedRectangle(cornerRadius: NudgeMetrics.cardRadius, style: .continuous)
                .fill(palette.card)
                .shadow(
                    color: palette.shadowColor,
                    radius: palette.shadowRadius,
                    x: 0,
                    y: palette.shadowY
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: NudgeMetrics.cardRadius, style: .continuous)
                .strokeBorder(palette.border, lineWidth: NudgeMetrics.borderWidth)
        )
    }
}

public struct NudgeSectionDivider: View {
    @Environment(\.nudgePalette) private var palette

    public init() {}

    public var body: some View {
        Rectangle()
            .fill(palette.border)
            .frame(height: 1)
    }
}
