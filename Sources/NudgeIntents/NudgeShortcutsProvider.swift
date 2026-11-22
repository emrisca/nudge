import AppIntents
import Foundation

/// Registers Nudge battery management phrases with Siri and Apple Shortcuts.
public struct NudgeShortcutsProvider: AppShortcutsProvider {
    public static var shortcutTileColor: ShortcutTileColor { .teal }

    @AppShortcutsBuilder
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GetBatteryStatusIntent(),
            phrases: [
                "Check battery status in \(.applicationName)",
                "Get battery status with \(.applicationName)",
                "How is my battery in \(.applicationName)"
            ],
            shortTitle: "Battery Status",
            systemImageName: "battery.75percent"
        )

        AppShortcut(
            intent: GetChargeLimitIntent(),
            phrases: [
                "Get charge limit in \(.applicationName)",
                "What is my charge limit in \(.applicationName)"
            ],
            shortTitle: "Get Charge Limit",
            systemImageName: "gauge.with.dots.needle.67percent"
        )

        AppShortcut(
            intent: SetChargeLimitIntent(),
            phrases: [
                "Set charge limit in \(.applicationName)",
                "Change battery limit in \(.applicationName)"
            ],
            shortTitle: "Set Charge Limit",
            systemImageName: "slider.horizontal.3"
        )

        AppShortcut(
            intent: StartTopUpIntent(),
            phrases: [
                "Top up my battery in \(.applicationName)",
                "Start top up in \(.applicationName)",
                "Charge to 100 percent in \(.applicationName)"
            ],
            shortTitle: "Top Up to 100%",
            systemImageName: "bolt.batteryblock.fill"
        )

        AppShortcut(
            intent: StartDischargeIntent(),
            phrases: [
                "Start battery discharge in \(.applicationName)",
                "Discharge battery with \(.applicationName)"
            ],
            shortTitle: "Start Discharge",
            systemImageName: "battery.25percent"
        )

        AppShortcut(
            intent: StopDischargeIntent(),
            phrases: [
                "Stop battery discharge in \(.applicationName)",
                "Resume normal charging in \(.applicationName)"
            ],
            shortTitle: "Stop Discharge",
            systemImageName: "battery.100percent.bolt"
        )

        AppShortcut(
            intent: GetBatteryTemperatureIntent(),
            phrases: [
                "Check battery temperature in \(.applicationName)",
                "How hot is my battery in \(.applicationName)"
            ],
            shortTitle: "Battery Temperature",
            systemImageName: "thermometer.medium"
        )

        AppShortcut(
            intent: StartCalibrationIntent(),
            phrases: [
                "Start battery calibration in \(.applicationName)",
                "Calibrate battery with \(.applicationName)"
            ],
            shortTitle: "Calibrate Battery",
            systemImageName: "arrow.triangle.2.circlepath"
        )

        AppShortcut(
            intent: SetPowerModeIntent(),
            phrases: [
                "Set power mode in \(.applicationName)",
                "Switch to \(\.$mode) mode in \(.applicationName)"
            ],
            shortTitle: "Set Power Mode",
            systemImageName: "bolt.circle"
        )

        AppShortcut(
            intent: KeepAwakeIntent(),
            phrases: [
                "Keep my Mac awake in \(.applicationName)",
                "Prevent sleep with \(.applicationName)"
            ],
            shortTitle: "Keep Mac Awake",
            systemImageName: "cup.and.saucer.fill"
        )
    }
}
