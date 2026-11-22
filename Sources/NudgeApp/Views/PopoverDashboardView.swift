import SwiftUI
import AppKit
import NudgeCore

/// Compact menu bar popover displaying only the Moss quick bar.
/// Clicking the 2x2 grid button closes the popover and opens the full Nudge app window.
public struct PopoverDashboardView: View {
    @Environment(\.nudgePalette) private var palette
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var manager: BatteryManager
    @ObservedObject var navigation: NudgeNavigationController

    @MainActor
    public init(manager: BatteryManager) {
        self.manager = manager
        self.navigation = .shared
    }

    public init(manager: BatteryManager, navigation: NudgeNavigationController) {
        self.manager = manager
        self.navigation = navigation
    }

    public var body: some View {
        CompactQuickBarView(manager: manager) {
            dismiss()
            navigation.openDashboard(using: openWindow, section: .overview)
        }
        .frame(width: NudgeMetrics.popoverWidth)
        .fixedSize(horizontal: false, vertical: true)
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
    }
}
