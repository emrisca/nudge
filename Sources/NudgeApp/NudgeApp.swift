import SwiftUI
import AppKit
import NudgeCore
import NudgeIntents

final class NudgeAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        BatteryManager.shared.startMonitoring()
        DispatchQueue.global(qos: .utility).async {
            BatteryManager.shared.refreshHighEnergyApps()
        }
        NudgeShortcutsProvider.updateAppShortcutParameters()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep Nudge MenuBarExtra alive even when the full dashboard window closes.
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        BatteryManager.shared.stopMonitoring()
    }
}

@main
struct NudgeApp: App {
    @NSApplicationDelegateAdaptor(NudgeAppDelegate.self) private var appDelegate
    @StateObject private var manager = BatteryManager.shared

    var body: some Scene {
        // Primary macOS Menu Bar Popover Dashboard
        MenuBarExtra {
            PopoverDashboardView(manager: manager)
                .nudgeThemed(appearance: manager.config.appearancePreference)
        } label: {
            MenuBarLabelView(manager: manager)
        }
        .menuBarExtraStyle(.window)

        // Full Resizable Application Dashboard Window
        Window("Nudge", id: "dashboard") {
            FullDashboardView(manager: manager)
                .nudgeThemed(appearance: manager.config.appearancePreference)
        }
        .defaultSize(width: 1120, height: 760)
        .windowResizability(.contentMinSize)

        // Native macOS Settings Scene (Cmd+,)
        Settings {
            ScrollView {
                SettingsView(manager: manager)
                    .padding(20)
            }
            .frame(minWidth: 640, minHeight: 540)
            .nudgeThemed(appearance: manager.config.appearancePreference)
        }
    }
}
