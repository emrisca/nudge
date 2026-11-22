import Foundation

public enum CalibrationPhase: String, Codable, Sendable {
    case idle
    case chargeToFull         // Phase 1: Charge to 100%
    case dischargeToLow       // Phase 2: Discharge to 10%
    case rechargeToFull       // Phase 3: Charge back to 100%
    case returnToTargetLimit  // Phase 4: Settle back to user limit
}

public final class CalibrationEngine: @unchecked Sendable {
    public private(set) var currentPhase: CalibrationPhase = .idle
    public let userTargetLimit: Int
    private let lock = NSLock()

    public init(userTargetLimit: Int = 80) {
        self.userTargetLimit = userTargetLimit
    }

    public func startCalibration() {
        lock.lock()
        defer { lock.unlock() }
        currentPhase = .chargeToFull
    }

    public func cancelCalibration() {
        lock.lock()
        defer { lock.unlock() }
        currentPhase = .idle
    }

    public func processTick(currentPercentage: Int, isPluggedIn: Bool) -> CalibrationPhase {
        lock.lock()
        defer { lock.unlock() }

        switch currentPhase {
        case .idle:
            break
        case .chargeToFull:
            if currentPercentage >= 100 {
                currentPhase = .dischargeToLow
            }
        case .dischargeToLow:
            if currentPercentage <= 10 {
                currentPhase = .rechargeToFull
            }
        case .rechargeToFull:
            if currentPercentage >= 100 {
                currentPhase = .returnToTargetLimit
            }
        case .returnToTargetLimit:
            if currentPercentage <= userTargetLimit {
                currentPhase = .idle
            }
        }

        return currentPhase
    }
}
