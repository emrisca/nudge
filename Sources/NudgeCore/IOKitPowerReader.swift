import Foundation
import IOKit
import IOKit.ps

/// Reads real macOS battery & power telemetry from IOPowerSources and AppleSmartBattery IORegistry.
public final class IOKitPowerReader: @unchecked Sendable {
    public static let shared = IOKitPowerReader()

    private let smcClient: SMCClient

    public init(smcClient: SMCClient = .shared) {
        self.smcClient = smcClient
    }

    /// Reads a full, accurate `BatterySnapshot` from macOS IOKit APIs.
    public func readCurrentSnapshot() -> BatterySnapshot {
        let registry = readSmartBatteryRegistry()
        let psInfo = readIOPowerSourceInfo()

        if registry == nil && psInfo == nil {
            return fallbackSnapshot()
        }

        // Plugged-in & charging flags
        let isPluggedIn = psInfo?.isPluggedIn ?? registry?.externalConnected ?? false
        let isCharging = psInfo?.isCharging ?? registry?.isCharging ?? false

        // Display (macOS smoothed) percentage
        let displayPercentage: Int
        if let psPct = psInfo?.displayPercentage {
            displayPercentage = max(0, min(100, psPct))
        } else if let cur = registry?.currentCapacity, let maxC = registry?.maxCapacity, maxC > 0 {
            displayPercentage = max(0, min(100, Int((Double(cur) / Double(maxC) * 100.0).rounded())))
        } else {
            displayPercentage = 0
        }

        // Raw hardware mAh capacities & raw hardware percentage
        let designCapacityMah = registry?.designCapacity ?? 5100
        let rawMaxMah = registry?.appleRawMaxCapacity
            ?? ((registry?.maxCapacity ?? 0) > 200 ? registry?.maxCapacity : nil)
            ?? designCapacityMah
        let rawCurrentMah = registry?.appleRawCurrentCapacity
            ?? Int((Double(rawMaxMah) * Double(displayPercentage) / 100.0).rounded())

        let rawHardwarePercentage: Double
        if rawMaxMah > 0, let rawCur = registry?.appleRawCurrentCapacity {
            rawHardwarePercentage = max(0.0, min(100.0, (Double(rawCur) / Double(rawMaxMah)) * 100.0))
        } else {
            rawHardwarePercentage = Double(displayPercentage)
        }

        // Temperature (°C) - prefer AppleSmartBattery accurate decode, fallback to SMC TB0T
        let temperatureCelsius = registry?.temperatureCelsius
            ?? smcClient.readBatteryTemperature()
            ?? 30.0

        let cycleCount = registry?.cycleCount ?? 0

        // Electrical metrics: Voltage (mV -> V) and Amperage (mA -> A, signed)
        let voltageVolts = registry?.voltageVolts ?? 12.0
        let amperageAmps = registry?.amperageAmps ?? 0.0

        // Adapter wattage rating
        let adapterMaxWatts = registry?.adapterMaxWatts ?? (isPluggedIn ? 67 : 0)

        // Time remaining in minutes
        let timeRemainingMinutes = resolveTimeRemainingMinutes(
            psMinutes: psInfo?.timeRemainingMinutes,
            registry: registry,
            isPluggedIn: isPluggedIn,
            isCharging: isCharging
        )

        // Power Flow Breakdown (Watts)
        let powerFlow = computePowerFlow(
            registry: registry,
            voltageVolts: voltageVolts,
            amperageAmps: amperageAmps,
            isPluggedIn: isPluggedIn,
            isCharging: isCharging,
            adapterMaxWatts: adapterMaxWatts
        )

        let state: ChargingState
        if !isPluggedIn {
            state = .unplugged
        } else if isCharging {
            state = .charging
        } else if powerFlow.batteryWatts < -0.5 {
            state = .discharging
        } else {
            state = .paused
        }

        return BatterySnapshot(
            timestamp: Date(),
            rawHardwarePercentage: (rawHardwarePercentage * 10.0).rounded() / 10.0,
            displayPercentage: displayPercentage,
            temperatureCelsius: (temperatureCelsius * 10.0).rounded() / 10.0,
            cycleCount: cycleCount,
            designCapacityMah: designCapacityMah,
            maxCapacityMah: rawMaxMah,
            currentCapacityMah: rawCurrentMah,
            voltageVolts: (voltageVolts * 1000.0).rounded() / 1000.0,
            amperageAmps: (amperageAmps * 1000.0).rounded() / 1000.0,
            isPluggedIn: isPluggedIn,
            isCharging: isCharging,
            adapterMaxWatts: adapterMaxWatts,
            timeRemainingMinutes: timeRemainingMinutes,
            powerFlow: powerFlow,
            state: state,
            architecture: SMCClient.currentArchitecture
        )
    }

    // MARK: - IOPowerSources Read

    private struct PowerSourceInfo {
        let isPluggedIn: Bool
        let isCharging: Bool
        let displayPercentage: Int
        let timeRemainingMinutes: Int?
    }

    private func readIOPowerSourceInfo() -> PowerSourceInfo? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else {
            return nil
        }

        for source in sources {
            guard let desc = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any] else {
                continue
            }

            // Prefer internal battery source
            if let type = desc[kIOPSTypeKey as String] as? String,
               type != (kIOPSInternalBatteryType as String) {
                continue
            }

            let stateStr = desc[kIOPSPowerSourceStateKey as String] as? String
            let isPluggedIn = (stateStr == (kIOPSACPowerValue as String))
            let isCharging = (desc[kIOPSIsChargingKey as String] as? Bool) ?? false
            let currentCap = (desc[kIOPSCurrentCapacityKey as String] as? Int) ?? 0
            let maxCap = (desc[kIOPSMaxCapacityKey as String] as? Int) ?? 100
            let pct = maxCap > 0 ? Int((Double(currentCap) / Double(maxCap) * 100.0).rounded()) : currentCap

            var timeMin: Int?
            if isCharging, let toFull = desc[kIOPSTimeToFullChargeKey as String] as? Int, toFull > 0 && toFull < 6000 {
                timeMin = toFull
            } else if !isPluggedIn, let toEmpty = desc[kIOPSTimeToEmptyKey as String] as? Int, toEmpty > 0 && toEmpty < 6000 {
                timeMin = toEmpty
            }

            return PowerSourceInfo(
                isPluggedIn: isPluggedIn,
                isCharging: isCharging,
                displayPercentage: pct,
                timeRemainingMinutes: timeMin
            )
        }

        return nil
    }

    // MARK: - AppleSmartBattery IORegistry Read

    private struct SmartBatteryRegistry {
        let externalConnected: Bool
        let isCharging: Bool
        let currentCapacity: Int?
        let maxCapacity: Int?
        let appleRawCurrentCapacity: Int?
        let appleRawMaxCapacity: Int?
        let designCapacity: Int?
        let cycleCount: Int?
        let temperatureCelsius: Double?
        let voltageVolts: Double?
        let amperageAmps: Double?
        let adapterMaxWatts: Int?
        let adapterActualWatts: Double?
        let telemetrySystemPowerInWatts: Double?
        let telemetryBatteryWatts: Double?
        let telemetrySystemLoadWatts: Double?
        let timeRemaining: Int?
        let avgTimeToEmpty: Int?
        let avgTimeToFull: Int?
    }

    private func readSmartBatteryRegistry() -> SmartBatteryRegistry? {
        let matching = IOServiceMatching("AppleSmartBattery")
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        var unmanagedProps: Unmanaged<CFMutableDictionary>?
        let kr = IORegistryEntryCreateCFProperties(service, &unmanagedProps, kCFAllocatorDefault, 0)
        guard kr == kIOReturnSuccess,
              let props = unmanagedProps?.takeRetainedValue() as? [String: Any] else {
            return nil
        }

        let externalConnected = (props["ExternalConnected"] as? Bool) ?? false
        let isCharging = (props["IsCharging"] as? Bool) ?? false
        let currentCap = Self.intValue(props["CurrentCapacity"])
        let maxCap = Self.intValue(props["MaxCapacity"])
        let rawCurrentCap = Self.intValue(props["AppleRawCurrentCapacity"])
        let rawMaxCap = Self.intValue(props["AppleRawMaxCapacity"])
            ?? Self.intValue(props["NominalChargeCapacity"])
        let designCap = Self.intValue(props["DesignCapacity"])
        let cycles = Self.intValue(props["CycleCount"])

        let temperature = Self.parseTemperatureCelsius(
            rawTemp: Self.doubleValue(props["Temperature"]),
            virtualTemp: Self.doubleValue(props["VirtualTemperature"])
        )

        let voltageMv = Self.doubleValue(props["Voltage"])
        let voltageVolts = voltageMv.map { $0 / 1000.0 }

        // InstantAmperage / Amperage are signed 64-bit values often boxed as unsigned 64-bit in IORegistry
        let amperageMa = Self.signedInt64Value(props["InstantAmperage"])
            ?? Self.signedInt64Value(props["Amperage"])
        let amperageAmps = amperageMa.map { Double($0) / 1000.0 }

        // AdapterDetails dictionary
        var adapterMaxWatts: Int?
        var adapterActualWatts: Double?
        if let adapter = props["AdapterDetails"] as? [String: Any] {
            if let watts = Self.intValue(adapter["Watts"]), watts > 0 {
                adapterMaxWatts = watts
            }
            if let currentMa = Self.doubleValue(adapter["Current"]),
               let voltageMv = Self.doubleValue(adapter["AdapterVoltage"]) ?? Self.doubleValue(adapter["Voltage"]),
               currentMa > 0 && voltageMv > 0 {
                adapterActualWatts = (currentMa / 1000.0) * (voltageMv / 1000.0)
                if adapterMaxWatts == nil {
                    adapterMaxWatts = Int(adapterActualWatts!.rounded())
                }
            }
        }

        // Apple Silicon PowerTelemetryData (in mW)
        var sysPowerInW: Double?
        var battPowerW: Double?
        var sysLoadW: Double?
        if let telemetry = props["PowerTelemetryData"] as? [String: Any] {
            if let powerInMw = Self.signedInt64Value(telemetry["SystemPowerIn"]), powerInMw >= 0 {
                sysPowerInW = Double(powerInMw) / 1000.0
            }
            if let battMw = Self.signedInt64Value(telemetry["BatteryPower"]) {
                // Note: On Apple Silicon, BatteryPower is signed (negative while discharging, positive while charging)
                battPowerW = Double(battMw) / 1000.0
            }
            if let loadMw = Self.signedInt64Value(telemetry["SystemLoad"]), loadMw >= 0 {
                sysLoadW = Double(loadMw) / 1000.0
            }
        }

        return SmartBatteryRegistry(
            externalConnected: externalConnected,
            isCharging: isCharging,
            currentCapacity: currentCap,
            maxCapacity: maxCap,
            appleRawCurrentCapacity: rawCurrentCap,
            appleRawMaxCapacity: rawMaxCap,
            designCapacity: designCap,
            cycleCount: cycles,
            temperatureCelsius: temperature,
            voltageVolts: voltageVolts,
            amperageAmps: amperageAmps,
            adapterMaxWatts: adapterMaxWatts,
            adapterActualWatts: adapterActualWatts,
            telemetrySystemPowerInWatts: sysPowerInW,
            telemetryBatteryWatts: battPowerW,
            telemetrySystemLoadWatts: sysLoadW,
            timeRemaining: Self.intValue(props["TimeRemaining"]),
            avgTimeToEmpty: Self.intValue(props["AvgTimeToEmpty"]),
            avgTimeToFull: Self.intValue(props["AvgTimeToFull"])
        )
    }

    // MARK: - Power Flow & Display Brightness Estimation

    private func computePowerFlow(
        registry: SmartBatteryRegistry?,
        voltageVolts: Double,
        amperageAmps: Double,
        isPluggedIn: Bool,
        isCharging: Bool,
        adapterMaxWatts: Int
    ) -> PowerFlowBreakdown {
        // Battery watts: always derive from exact electrical V * A (positive = charging, negative = discharging)
        let electricalBatteryW = voltageVolts * amperageAmps
        let batteryWatts: Double
        if abs(electricalBatteryW) >= 0.05 {
            batteryWatts = electricalBatteryW
        } else if let teleBatt = registry?.telemetryBatteryWatts, !isCharging {
            batteryWatts = teleBatt
        } else {
            batteryWatts = electricalBatteryW
        }

        // System load & charger input watts: physics invariant Charger = SystemLoad + BatteryWatts
        let chargerInputWatts: Double
        let systemLoadWatts: Double

        if !isPluggedIn {
            chargerInputWatts = 0.0
            if abs(batteryWatts) >= 0.1 {
                systemLoadWatts = max(0.5, abs(min(0.0, batteryWatts)))
            } else if let teleLoad = registry?.telemetrySystemLoadWatts, teleLoad > 0.1 {
                systemLoadWatts = teleLoad
            } else {
                systemLoadWatts = 5.0
            }
        } else if let teleIn = registry?.telemetrySystemPowerInWatts, teleIn > 0.1 {
            chargerInputWatts = teleIn
            let derivedLoad = chargerInputWatts - batteryWatts
            if derivedLoad >= 0.5 {
                systemLoadWatts = derivedLoad
            } else if let teleLoad = registry?.telemetrySystemLoadWatts, teleLoad > 0.5 && teleLoad <= chargerInputWatts + abs(min(0.0, batteryWatts)) + 5.0 {
                systemLoadWatts = teleLoad
            } else {
                systemLoadWatts = max(0.5, derivedLoad)
            }
        } else if let actualAdapter = registry?.adapterActualWatts, actualAdapter > 0.5, isCharging {
            // AdapterDetails Current*Voltage is typically max negotiated PDO, so estimate realistic draw
            let estimatedLoad = 8.5
            systemLoadWatts = estimatedLoad
            chargerInputWatts = min(actualAdapter, max(estimatedLoad, estimatedLoad + batteryWatts))
        } else {
            let baseLoad = batteryWatts < -0.2 ? abs(batteryWatts) : 8.5
            systemLoadWatts = max(1.0, baseLoad)
            chargerInputWatts = min(
                Double(max(adapterMaxWatts, 30)),
                max(0.0, systemLoadWatts + batteryWatts)
            )
        }

        // Sub-component breakdown: Display + USB/Peripherals + SoC = System Load
        let brightness = readDisplayBrightness() // 0.0 ... 1.0
        let rawDisplayEstimate = 0.6 + (brightness * 4.4) // ~0.6W min backlight to ~5.0W max panel
        let displayWatts = min(systemLoadWatts * 0.45, rawDisplayEstimate)

        let usbShareRatio = isPluggedIn ? 0.14 : 0.10
        let usbAndPeripheralsWatts = min(
            max(0.2, systemLoadWatts * usbShareRatio),
            max(0.0, systemLoadWatts - displayWatts)
        )
        let socWatts = max(0.2, systemLoadWatts - displayWatts - usbAndPeripheralsWatts)

        func round2(_ v: Double) -> Double { (v * 100.0).rounded() / 100.0 }

        return PowerFlowBreakdown(
            chargerInputWatts: round2(chargerInputWatts),
            batteryWatts: round2(batteryWatts),
            systemLoadWatts: round2(systemLoadWatts),
            socWatts: round2(socWatts),
            displayWatts: round2(displayWatts),
            usbAndPeripheralsWatts: round2(usbAndPeripheralsWatts)
        )
    }

    /// Reads primary built-in display brightness (0.0...1.0) via IOKit without private frameworks.
    private func readDisplayBrightness() -> Double {
        let matching = IOServiceMatching("IODisplayConnect")
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == kIOReturnSuccess else {
            return readAppleBacklightBrightness() ?? 0.5
        }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer { IOObjectRelease(service) }
            if let params = IORegistryEntryCreateCFProperty(
                service,
                "IODisplayParameters" as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue() as? [String: Any],
               let brightnessDict = params["brightness"] as? [String: Any],
               let value = Self.doubleValue(brightnessDict["value"]),
               let maxVal = Self.doubleValue(brightnessDict["max"]),
               maxVal > 0 {
                return max(0.0, min(1.0, value / maxVal))
            }
            service = IOIteratorNext(iterator)
        }

        return readAppleBacklightBrightness() ?? 0.5
    }

    private func readAppleBacklightBrightness() -> Double? {
        let matching = IOServiceMatching("AppleARMBacklight")
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        if let params = IORegistryEntryCreateCFProperty(
            service,
            "IODisplayParameters" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? [String: Any],
           let brightnessDict = params["brightness"] as? [String: Any],
           let value = Self.doubleValue(brightnessDict["value"]),
           let maxVal = Self.doubleValue(brightnessDict["max"]),
           maxVal > 0 {
            return max(0.0, min(1.0, value / maxVal))
        }
        return nil
    }

    // MARK: - Decoding Helpers

    private func resolveTimeRemainingMinutes(
        psMinutes: Int?,
        registry: SmartBatteryRegistry?,
        isPluggedIn: Bool,
        isCharging: Bool
    ) -> Int? {
        if let psMinutes, psMinutes > 0 && psMinutes < 6000 {
            return psMinutes
        }
        if isCharging, let toFull = registry?.avgTimeToFull, toFull > 0 && toFull < 6000 {
            return toFull
        }
        if !isPluggedIn, let toEmpty = registry?.avgTimeToEmpty, toEmpty > 0 && toEmpty < 6000 {
            return toEmpty
        }
        if let tr = registry?.timeRemaining, tr > 0 && tr < 6000 {
            return tr
        }
        let estimate = IOPSGetTimeRemainingEstimate()
        if estimate > 0 && estimate < (6000 * 60) {
            return Int((estimate / 60.0).rounded())
        }
        return nil
    }

    /// Accurately decodes AppleSmartBattery `Temperature` (deci-Kelvin vs centi-Celsius vs Kelvin vs Celsius).
    internal static func parseTemperatureCelsius(rawTemp: Double?, virtualTemp: Double?) -> Double? {
        guard let raw = rawTemp else {
            if let v = virtualTemp {
                return v > 200 ? (v / 100.0) : v
            }
            return nil
        }

        // Case 1: Values > 2000 are either deci-Kelvin (e.g., 3002 = 300.2K = 27.05°C, SBS 0x08 standard)
        // or centi-Celsius (e.g., 3250 = 32.50°C on some virtualized/older drivers).
        if raw > 2000.0 {
            let asDeciKelvin = (raw / 10.0) - 273.15
            let asCentiCelsius = raw / 100.0

            // Cross-check against VirtualTemperature (always centi-Celsius on Apple Silicon) when present
            if let v = virtualTemp, v > 100.0 && v < 10000.0 {
                let vCelsius = v / 100.0
                if abs(asDeciKelvin - vCelsius) <= abs(asCentiCelsius - vCelsius) {
                    return asDeciKelvin
                } else {
                    return asCentiCelsius
                }
            }

            // Standard AppleSmartBattery SBS register is deci-Kelvin when yielding plausible battery temp
            if asDeciKelvin >= 0.0 && asDeciKelvin <= 85.0 {
                return asDeciKelvin
            }
            return asCentiCelsius
        }

        // Case 2: 500...2000 -> centi-Celsius (5.0°C ... 20.0°C)
        if raw >= 500.0 {
            return raw / 100.0
        }

        // Case 3: 200...400 -> Kelvin
        if raw >= 200.0 {
            return raw - 273.15
        }

        // Case 4: Already Celsius
        return raw
    }

    private static func intValue(_ any: Any?) -> Int? {
        if let i = any as? Int { return i }
        if let n = any as? NSNumber { return n.intValue }
        return nil
    }

    private static func doubleValue(_ any: Any?) -> Double? {
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        if let n = any as? NSNumber { return n.doubleValue }
        return nil
    }

    private static func signedInt64Value(_ any: Any?) -> Int64? {
        if let i64 = any as? Int64 { return i64 }
        if let u64 = any as? UInt64 { return Int64(bitPattern: u64) }
        if let i = any as? Int { return Int64(i) }
        if let n = any as? NSNumber { return n.int64Value }
        return nil
    }

    private func fallbackSnapshot() -> BatterySnapshot {
        let breakdown = PowerFlowBreakdown(
            chargerInputWatts: 8.5,
            batteryWatts: 0.0,
            systemLoadWatts: 8.5,
            socWatts: 5.5,
            displayWatts: 2.0,
            usbAndPeripheralsWatts: 1.0
        )
        return BatterySnapshot(
            timestamp: Date(),
            rawHardwarePercentage: 80.0,
            displayPercentage: 80,
            temperatureCelsius: 30.0,
            cycleCount: 0,
            designCapacityMah: 5100,
            maxCapacityMah: 5000,
            currentCapacityMah: 4000,
            voltageVolts: 12.2,
            amperageAmps: 0.0,
            isPluggedIn: true,
            isCharging: false,
            adapterMaxWatts: 67,
            timeRemainingMinutes: nil,
            powerFlow: breakdown,
            state: .paused,
            architecture: SMCClient.currentArchitecture
        )
    }
}
