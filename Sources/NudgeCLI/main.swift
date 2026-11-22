import Foundation
import NudgeCore

print("⚡ Nudge - macOS Battery Management CLI")
let manager = BatteryManager.shared
let status = manager.tick()
print("----------------------------------------")
print("Battery State:      \(status.snapshot.state.rawValue.capitalized)")
print("Display Percentage: \(status.snapshot.displayPercentage)%")
print("Raw Percentage:     \(String(format: "%.1f", status.snapshot.rawPercentage))%")
print("Temperature:        \(String(format: "%.1f", status.snapshot.temperatureCelsius))°C")
print("Cycle Count:        \(status.snapshot.cycleCount)")
print("Power Flow:         Charger: \(status.snapshot.chargerWattage)W | Batt: \(status.snapshot.batteryWattage)W | Sys: \(status.snapshot.systemWattage)W")
print("Inhibit Charging:   \(status.chargingInhibited)")
print("Force Discharge:    \(status.forceDischarge)")
print("----------------------------------------")
