import Foundation
import IOKit.pwr_mgt
import AppKit

/// Manages macOS IOPM power assertions (preventing display/system sleep) and
/// intercepts `NSWorkspace` sleep/wake notifications for "Stop Charging when Sleeping" and wake catch-up.
public final class SleepController: @unchecked Sendable {
    private let lock = NSLock()
    private var _state: SleepControlState
    private var displayAssertionID: IOPMAssertionID = 0
    private var systemAssertionID: IOPMAssertionID = 0
    private var isAssertionHeld: Bool = false

    private var willSleepObserver: NSObjectProtocol?
    private var didWakeObserver: NSObjectProtocol?

    private var _onWillSleep: (@Sendable () -> Void)?
    private var _onDidWake: (@Sendable () -> Void)?

    public init(initialState: SleepControlState = SleepControlState()) {
        self._state = initialState
        registerWorkspaceNotifications()
    }

    deinit {
        unregisterWorkspaceNotifications()
        releaseAssertions()
    }

    public var state: SleepControlState {
        lock.lock()
        defer { lock.unlock() }
        return _state
    }

    public var isAssertionActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isAssertionHeld
    }

    public var onWillSleep: (@Sendable () -> Void)? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _onWillSleep
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _onWillSleep = newValue
        }
    }

    public var onDidWake: (@Sendable () -> Void)? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _onDidWake
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _onDidWake = newValue
        }
    }

    // MARK: - Controls

    /// Enables manual or timed keep-awake with optional battery % and unplug fallback triggers.
    @discardableResult
    public func enableTimedKeepAwake(
        minutes: Int?,
        fallbackBatteryPercent: Int? = nil,
        reenableOnUnplug: Bool? = nil,
        now: Date = Date()
    ) -> SleepControlState {
        lock.lock()
        _state.keepAwakeActive = true
        if let minutes, minutes > 0 {
            _state.expiresAt = now.addingTimeInterval(TimeInterval(minutes * 60))
        } else {
            _state.expiresAt = nil
        }
        if let fallback = fallbackBatteryPercent {
            _state.fallbackBatteryPercent = max(5, min(95, fallback))
        }
        if let onUnplug = reenableOnUnplug {
            _state.reenableOnUnplug = onUnplug
        }
        let updated = _state
        lock.unlock()

        acquireAssertions(reason: "Nudge Keep-Awake Active")
        return updated
    }

    /// Disables manual/timed keep-awake (keeps assertion only if `disableSleepUntilChargeLimit` still requires it on next evaluate).
    @discardableResult
    public func disableKeepAwake() -> SleepControlState {
        lock.lock()
        _state.keepAwakeActive = false
        _state.expiresAt = nil
        let shouldRelease = !_state.disableSleepUntilChargeLimit
        let updated = _state
        lock.unlock()

        if shouldRelease {
            releaseAssertions()
        }
        return updated
    }

    /// Configures "Disable Sleep until Charge Limit is Reached" and fallback preferences.
    @discardableResult
    public func configure(
        disableSleepUntilChargeLimit: Bool,
        fallbackBatteryPercent: Int,
        reenableOnUnplug: Bool
    ) -> SleepControlState {
        lock.lock()
        _state.disableSleepUntilChargeLimit = disableSleepUntilChargeLimit
        _state.fallbackBatteryPercent = max(5, min(95, fallbackBatteryPercent))
        _state.reenableOnUnplug = reenableOnUnplug
        let updated = _state
        lock.unlock()
        return updated
    }

    /// Evaluates active keep-awake triggers, timer expiry, unplug fallback, and low-battery fallback,
    /// acquiring or releasing `IOPMAssertion`s cleanly.
    @discardableResult
    public func evaluate(
        snapshot: BatterySnapshot,
        chargeLimit: Int,
        now: Date = Date()
    ) -> (state: SleepControlState, assertionActive: Bool) {
        lock.lock()
        var s = _state

        // 1. Evaluate manual/timed keep-awake expiry & fallback triggers
        if s.keepAwakeActive {
            var shouldCancel = false

            if let expiry = s.expiresAt, now >= expiry {
                shouldCancel = true
            }
            if s.reenableOnUnplug && !snapshot.isPluggedIn {
                shouldCancel = true
            }
            if !snapshot.isPluggedIn && snapshot.displayPercentage <= s.fallbackBatteryPercent {
                shouldCancel = true
            }

            if shouldCancel {
                s.keepAwakeActive = false
                s.expiresAt = nil
            }
        }

        // 2. Evaluate "Disable Sleep until Charge Limit"
        let chargingTowardLimit = s.disableSleepUntilChargeLimit
            && snapshot.isPluggedIn
            && snapshot.displayPercentage < chargeLimit

        let shouldHoldAssertion = s.keepAwakeActive || chargingTowardLimit
        _state = s
        let alreadyHeld = isAssertionHeld
        lock.unlock()

        if shouldHoldAssertion && !alreadyHeld {
            let reason = s.keepAwakeActive
                ? "Nudge Timed Keep-Awake"
                : "Nudge Preventing Sleep Until \(chargeLimit)% Charge Limit"
            acquireAssertions(reason: reason)
        } else if !shouldHoldAssertion && alreadyHeld {
            releaseAssertions()
        }

        lock.lock()
        let finalState = _state
        let finalHeld = isAssertionHeld
        lock.unlock()

        return (finalState, finalHeld)
    }

    // MARK: - IOPMAssertion Management

    private func acquireAssertions(reason: String) {
        lock.lock()
        defer { lock.unlock() }

        guard !isAssertionHeld else { return }

        var newDisplayID: IOPMAssertionID = 0
        var newSystemID: IOPMAssertionID = 0

        let displayStatus = IOPMAssertionCreateWithName(
            kIOPMAssertionTypeNoDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &newDisplayID
        )

        let systemStatus = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &newSystemID
        )

        if displayStatus == kIOReturnSuccess {
            displayAssertionID = newDisplayID
        }
        if systemStatus == kIOReturnSuccess {
            systemAssertionID = newSystemID
        }

        isAssertionHeld = (displayAssertionID != 0 || systemAssertionID != 0)
    }

    private func releaseAssertions() {
        lock.lock()
        let dID = displayAssertionID
        let sID = systemAssertionID
        displayAssertionID = 0
        systemAssertionID = 0
        isAssertionHeld = false
        lock.unlock()

        if dID != 0 {
            IOPMAssertionRelease(dID)
        }
        if sID != 0 {
            IOPMAssertionRelease(sID)
        }
    }

    // MARK: - NSWorkspace Sleep / Wake Observers

    private func registerWorkspaceNotifications() {
        let center = NSWorkspace.shared.notificationCenter

        willSleepObserver = center.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            self.onWillSleep?()
        }

        didWakeObserver = center.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            self.onDidWake?()
        }
    }

    private func unregisterWorkspaceNotifications() {
        let center = NSWorkspace.shared.notificationCenter
        if let obs = willSleepObserver {
            center.removeObserver(obs)
            willSleepObserver = nil
        }
        if let obs = didWakeObserver {
            center.removeObserver(obs)
            didWakeObserver = nil
        }
    }
}
