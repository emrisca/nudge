import Foundation

/// Protects battery longevity by pausing charging when cell temperature exceeds a threshold,
/// using a hysteresis cooldown window (default 300s / 5 minutes) to prevent toggle thrashing.
public final class HeatProtectionManager: @unchecked Sendable {
    private var _thresholdCelsius: Double
    private var _hysteresisCooldownSeconds: TimeInterval

    private var isOverheated: Bool = false
    private var overheatedTimestamp: Date?
    private let lock = NSLock()

    public init(thresholdCelsius: Double = 35.0, hysteresisCooldownSeconds: TimeInterval = 300.0) {
        self._thresholdCelsius = thresholdCelsius
        self._hysteresisCooldownSeconds = max(0, hysteresisCooldownSeconds)
    }

    public var thresholdCelsius: Double {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _thresholdCelsius
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _thresholdCelsius = max(25.0, min(60.0, newValue))
        }
    }

    public var hysteresisCooldownSeconds: TimeInterval {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _hysteresisCooldownSeconds
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _hysteresisCooldownSeconds = max(0, newValue)
        }
    }

    /// Evaluates current battery temperature and returns `true` when charging must be inhibited due to heat.
    public func evaluateTemperature(_ currentTempCelsius: Double, now: Date = Date()) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        if currentTempCelsius >= _thresholdCelsius {
            isOverheated = true
            overheatedTimestamp = now
            return true
        }

        if isOverheated {
            if let timestamp = overheatedTimestamp {
                let elapsed = now.timeIntervalSince(timestamp)
                if elapsed < _hysteresisCooldownSeconds {
                    return true
                }
            }
            isOverheated = false
            overheatedTimestamp = nil
            return false
        }

        return false
    }

    /// Returns the number of seconds remaining in the hysteresis cooldown window (0 when inactive/expired).
    public func remainingCooldownSeconds(now: Date = Date()) -> TimeInterval {
        lock.lock()
        defer { lock.unlock() }

        guard isOverheated, let timestamp = overheatedTimestamp else {
            return 0
        }
        let elapsed = max(0, now.timeIntervalSince(timestamp))
        return max(0, _hysteresisCooldownSeconds - elapsed)
    }

    /// Whether heat protection is currently inhibiting charging.
    public var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isOverheated
    }

    /// Resets overheat latch and cooldown state.
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        isOverheated = false
        overheatedTimestamp = nil
    }
}
