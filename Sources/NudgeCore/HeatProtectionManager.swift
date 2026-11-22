import Foundation

public final class HeatProtectionManager: @unchecked Sendable {
    public let thresholdCelsius: Double
    public let hysteresisCooldownSeconds: TimeInterval

    private var isOverheated: Bool = false
    private var overheatedTimestamp: Date?
    private let lock = NSLock()

    public init(thresholdCelsius: Double = 35.0, hysteresisCooldownSeconds: TimeInterval = 300.0) {
        self.thresholdCelsius = thresholdCelsius
        self.hysteresisCooldownSeconds = hysteresisCooldownSeconds
    }

    /// Evaluates current temperature and returns whether charging must be inhibited due to heat.
    public func evaluateTemperature(_ currentTempCelsius: Double, now: Date = Date()) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        if currentTempCelsius >= thresholdCelsius {
            isOverheated = true
            overheatedTimestamp = now
            return true
        }

        if isOverheated {
            if let timestamp = overheatedTimestamp {
                let elapsed = now.timeIntervalSince(timestamp)
                if elapsed < hysteresisCooldownSeconds {
                    // Still in hysteresis cooldown window
                    return true
                }
            }
            // Cooldown period elapsed and temperature is below threshold
            isOverheated = false
            overheatedTimestamp = nil
            return false
        }

        return false
    }

    public var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isOverheated
    }
}
