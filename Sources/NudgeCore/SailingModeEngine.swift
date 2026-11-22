import Foundation

public final class SailingModeEngine: @unchecked Sendable {
    public var targetLimit: Int
    public var deadbandPercentage: Int // e.g. 5% means sail between (target - 5) and target

    public private(set) var isSailing: Bool = false
    private let lock = NSLock()

    public init(targetLimit: Int = 80, deadbandPercentage: Int = 5) {
        self.targetLimit = targetLimit
        self.deadbandPercentage = deadbandPercentage
    }

    /// Evaluates whether charging should be allowed or paused
    /// Returns true if charging should be inhibited (paused/sailing)
    public func evaluateCharging(currentPercentage: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        let lowerBound = max(10, targetLimit - deadbandPercentage)

        if currentPercentage >= targetLimit {
            // Reached or exceeded ceiling -> enter sailing mode (stop charging)
            isSailing = true
            return true
        } else if currentPercentage <= lowerBound {
            // Dropped to or below lower bound -> exit sailing mode (resume charging)
            isSailing = false
            return false
        } else {
            // Within deadband: maintain current state
            return isSailing
        }
    }
}
