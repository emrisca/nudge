import Foundation

/// Prevents micro-cycling near the target charge limit by keeping charging paused
/// across a configurable deadband (typically 5–10%) below `targetLimit`.
public final class SailingModeEngine: @unchecked Sendable {
    private var _targetLimit: Int
    private var _deadbandPercentage: Int
    private var _isEnabled: Bool
    private var _isSailing: Bool = false
    private let lock = NSLock()

    public init(targetLimit: Int = 80, deadbandPercentage: Int = 5, isEnabled: Bool = true) {
        self._targetLimit = max(20, min(100, targetLimit))
        self._deadbandPercentage = max(1, min(20, deadbandPercentage))
        self._isEnabled = isEnabled
    }

    public var targetLimit: Int {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _targetLimit
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _targetLimit = max(20, min(100, newValue))
        }
    }

    /// Configurable sailing deadband below `targetLimit` (typical range 5–10%, default 5%).
    public var deadbandPercentage: Int {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _deadbandPercentage
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _deadbandPercentage = max(1, min(20, newValue))
        }
    }

    public var isEnabled: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _isEnabled
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _isEnabled = newValue
            if !newValue {
                _isSailing = false
            }
        }
    }

    public var isSailing: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isSailing
    }

    /// The lower charge threshold at which charging resumes once sailing is active.
    public var lowerBound: Int {
        lock.lock()
        defer { lock.unlock() }
        return max(10, _targetLimit - _deadbandPercentage)
    }

    /// Evaluates whether charging should be inhibited (`true`) or permitted (`false`).
    public func evaluateCharging(currentPercentage: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard _isEnabled else {
            _isSailing = false
            return currentPercentage >= _targetLimit
        }

        let floor = max(10, _targetLimit - _deadbandPercentage)

        if currentPercentage >= _targetLimit {
            // Reached or exceeded ceiling -> enter sailing mode (stop charging)
            _isSailing = true
            return true
        } else if currentPercentage <= floor {
            // Dropped to or below lower bound -> exit sailing mode (resume charging)
            _isSailing = false
            return false
        } else {
            // Within deadband: hold current state to avoid micro-cycling
            return _isSailing
        }
    }

    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        _isSailing = false
    }
}
