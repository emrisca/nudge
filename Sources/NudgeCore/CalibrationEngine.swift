import Foundation

/// Four-phase full-cycle battery calibration state machine.
public enum CalibrationPhase: String, Codable, Sendable, CaseIterable {
    case idle
    case chargeToFull         // Phase 1: Charge to 100%
    case dischargeToLow       // Phase 2: Discharge to 10%
    case rechargeToFull       // Phase 3: Charge back to 100%
    case returnToTargetLimit  // Phase 4: Settle back to user limit

    public var displayTitle: String {
        switch self {
        case .idle:
            return "Idle"
        case .chargeToFull:
            return "Charging to 100%"
        case .dischargeToLow:
            return "Discharging to 10%"
        case .rechargeToFull:
            return "Recharging to 100%"
        case .returnToTargetLimit:
            return "Returning to Charge Limit"
        }
    }

    public var stepIndex: Int {
        switch self {
        case .idle:                return 0
        case .chargeToFull:        return 1
        case .dischargeToLow:      return 2
        case .rechargeToFull:      return 3
        case .returnToTargetLimit: return 4
        }
    }

    public var progressFraction: Double {
        switch self {
        case .idle:                return 0.0
        case .chargeToFull:        return 0.25
        case .dischargeToLow:      return 0.50
        case .rechargeToFull:      return 0.75
        case .returnToTargetLimit: return 0.90
        }
    }
}

/// Orchestrates the 4-phase battery calibration cycle (`100% -> 10% -> 100% -> targetLimit`),
/// explicitly bypassing Heat Protection while calibration is active.
public final class CalibrationEngine: @unchecked Sendable {
    private var _currentPhase: CalibrationPhase = .idle
    private var _userTargetLimit: Int
    private var _startedAt: Date?
    private let lock = NSLock()

    public init(userTargetLimit: Int = 80) {
        self._userTargetLimit = max(20, min(100, userTargetLimit))
    }

    public var currentPhase: CalibrationPhase {
        lock.lock()
        defer { lock.unlock() }
        return _currentPhase
    }

    public var userTargetLimit: Int {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _userTargetLimit
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _userTargetLimit = max(20, min(100, newValue))
        }
    }

    public var isActive: Bool {
        currentPhase != .idle
    }

    /// Calibration intentionally bypasses Heat Protection so the full cycle completes uninterrupted.
    public var bypassesHeatProtection: Bool {
        isActive
    }

    public var startedAt: Date? {
        lock.lock()
        defer { lock.unlock() }
        return _startedAt
    }

    public func startCalibration() {
        lock.lock()
        defer { lock.unlock() }
        _currentPhase = .chargeToFull
        _startedAt = Date()
    }

    public func cancelCalibration() {
        lock.lock()
        defer { lock.unlock() }
        _currentPhase = .idle
        _startedAt = nil
    }

    @discardableResult
    public func processTick(currentPercentage: Int, isPluggedIn: Bool) -> CalibrationPhase {
        lock.lock()
        defer { lock.unlock() }

        switch _currentPhase {
        case .idle:
            break
        case .chargeToFull:
            if currentPercentage >= 100 {
                _currentPhase = .dischargeToLow
            }
        case .dischargeToLow:
            if currentPercentage <= 10 {
                _currentPhase = .rechargeToFull
            }
        case .rechargeToFull:
            if currentPercentage >= 100 {
                _currentPhase = .returnToTargetLimit
            }
        case .returnToTargetLimit:
            if currentPercentage <= _userTargetLimit {
                _currentPhase = .idle
                _startedAt = nil
            }
        }

        return _currentPhase
    }

    /// Maps a calibration phase into hardware charge-inhibit and force-discharge commands.
    public func hardwareDirectives(for phase: CalibrationPhase) -> (inhibitCharging: Bool, forceDischarge: Bool) {
        switch phase {
        case .idle:
            return (false, false)
        case .chargeToFull, .rechargeToFull:
            return (false, false)
        case .dischargeToLow, .returnToTargetLimit:
            return (true, true)
        }
    }
}
