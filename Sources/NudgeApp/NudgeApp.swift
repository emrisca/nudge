import SwiftUI
import AppKit
import NudgeCore
import NudgeIntents

/// Coordinates dashboard window presentation and section routing while keeping Nudge strictly
/// menu-bar-only (`.accessory` activation policy with no macOS Dock icon).
@MainActor
public final class NudgeNavigationController: ObservableObject {
    public static let shared = NudgeNavigationController()

    @Published public var selectedSection: DashboardSection = .overview
    private(set) var hasUserOpenedDashboard: Bool = false

    private init() {}

    public func openDashboard(
        using openWindow: OpenWindowAction,
        section: DashboardSection? = nil
    ) {
        hasUserOpenedDashboard = true
        if let section {
            selectedSection = section
        }

        // Keep activation policy strictly .accessory so the Dock icon never appears.
        NSApp.setActivationPolicy(.accessory)
        openWindow(id: "dashboard")
        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.accessory)
            for window in NSApp.windows where Self.isDashboardOrAuxWindow(window) {
                window.isRestorable = false
                window.makeKeyAndOrderFront(nil)
            }
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    public func enforceAccessoryPolicy() {
        if NSApp.activationPolicy() != .accessory {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    public func suppressAutoOpenedWindowsIfNeeded() {
        enforceAccessoryPolicy()
        guard !hasUserOpenedDashboard else { return }

        for window in NSApp.windows where Self.isDashboardOrAuxWindow(window) {
            window.isRestorable = false
            window.orderOut(nil)
            window.close()
        }
    }

    /// Distinguishes regular app windows (such as `"dashboard"`) from MenuBarExtra status item / popover windows.
    static func isDashboardOrAuxWindow(_ window: NSWindow) -> Bool {
        if let rawId = window.identifier?.rawValue,
           rawId.localizedCaseInsensitiveContains("dashboard") {
            return true
        }
        let className = NSStringFromClass(type(of: window))
        if className.contains("StatusBar") || className.contains("MenuBarExtra") || className.contains("Popover") {
            return false
        }
        if window is NSPanel {
            return false
        }
        return window.styleMask.contains(.titled) && window.level == .normal
    }
}

final class NudgeAppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        if let idx = CommandLine.arguments.firstIndex(of: "--render-screenshots"),
           idx + 1 < CommandLine.arguments.count {
            let outDir = CommandLine.arguments[idx + 1]
            Task { @MainActor in
                NudgeScreenshotRenderer.renderAll(to: outDir)
                NSApp.terminate(nil)
            }
            return
        }

        Task { @MainActor in
            NudgeNavigationController.shared.suppressAutoOpenedWindowsIfNeeded()
        }
        DispatchQueue.main.async {
            Task { @MainActor in
                NudgeNavigationController.shared.suppressAutoOpenedWindowsIfNeeded()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            Task { @MainActor in
                NudgeNavigationController.shared.suppressAutoOpenedWindowsIfNeeded()
            }
        }

        BatteryManager.shared.startMonitoring()
        DispatchQueue.global(qos: .utility).async {
            BatteryManager.shared.refreshHighEnergyApps()
        }
        NudgeShortcutsProvider.updateAppShortcutParameters()

        Task { @MainActor in
            UpdateManager.shared.onRequestAppTermination = {
                NSApp.terminate(nil)
            }
            UpdateManager.shared.startBackgroundChecks()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep Nudge MenuBarExtra alive even when the full dashboard window closes.
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        BatteryManager.shared.stopMonitoring()
        MainActor.assumeIsolated {
            UpdateManager.shared.stopBackgroundChecks()
        }
    }
}

@main
struct NudgeApp: App {
    @NSApplicationDelegateAdaptor(NudgeAppDelegate.self) private var appDelegate
    @StateObject private var manager = BatteryManager.shared
    @StateObject private var navigation = NudgeNavigationController.shared

    var body: some Scene {
        // Primary macOS Menu Bar Popover Dashboard (always-on menu bar utility)
        MenuBarExtra {
            PopoverDashboardView(manager: manager, navigation: navigation)
                .nudgeThemed(appearance: manager.config.appearancePreference)
        } label: {
            MenuBarLabelView(manager: manager)
        }
        .menuBarExtraStyle(.window)

        // Full Resizable Application Dashboard Window (opened on demand, Dock stays hidden)
        Window("Nudge", id: "dashboard") {
            FullDashboardView(manager: manager, navigation: navigation)
                .nudgeThemed(appearance: manager.config.appearancePreference)
                .onAppear {
                    navigation.enforceAccessoryPolicy()
                    if !navigation.hasUserOpenedDashboard {
                        navigation.suppressAutoOpenedWindowsIfNeeded()
                    }
                }
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
            .onAppear {
                navigation.enforceAccessoryPolicy()
            }
        }
    }
}
