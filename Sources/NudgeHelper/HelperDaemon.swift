import AppKit
import Darwin
import Foundation
import NudgeCore
import OSLog

/// Privileged background daemon enforcing SMC charge limits and discharge policy over XPC,
/// across macOS Fast User Switching, sleep/wake transitions, and when the main UI app is closed.
final class NudgeHelperDaemon: NSObject, NSXPCListenerDelegate, NudgeHelperProtocol, @unchecked Sendable {
    static let shared = NudgeHelperDaemon()

    static let daemonVersion = "1.0.0"
    static let defaultIntervalSeconds = 10
    static let defaultLeewaySeconds = 2

    private let logger = Logger(subsystem: kNudgeHelperMachServiceName, category: "daemon")
    private let stateQueue = DispatchQueue(label: "com.emrisca.nudge.helper.enforcement", qos: .utility)

    private var stateStore: HelperStateStore?
    private var state = HelperDaemonState()
    private var activeConnections: [ObjectIdentifier: NSXPCConnection] = [:]
    private var isForegroundMode = false
    private var isUserSessionActive = true
    private var isSystemSleeping = false
    private var isShuttingDown = false

    private var lastAppliedLimit: Int?
    private var lastAppliedInhibit: Bool?
    private var lastAppliedDischarge: Bool?
    private var lastAppliedLED: MagSafeLEDState?

    private var listener: NSXPCListener?
    private var enforcementTimer: DispatchSourceTimer?
    private var sigTermSource: DispatchSourceSignal?
    private var sigIntSource: DispatchSourceSignal?
    private var workspaceObservers: [NSObjectProtocol] = []

    private override init() {
        super.init()
    }

    // MARK: - Lifecycle

    func start(foreground: Bool, intervalSeconds: Int = NudgeHelperDaemon.defaultIntervalSeconds) {
        let clampedInterval = max(2, intervalSeconds)

        stateQueue.sync {
            self.isForegroundMode = foreground
            let store = HelperStateStore(foreground: foreground)
            self.stateStore = store
            self.state = store.load()
            self.syncBatteryManagerLocked()
        }

        let initial = currentStateSnapshot()
        log("Starting NudgeHelper v\(Self.daemonVersion) (mode=\(foreground ? "foreground" : "launchd"), interval=\(clampedInterval)s, limit=\(initial.chargeLimit)%, stopWhenClosed=\(initial.stopChargingWhenClosed))")

        configureSignalHandlers()
        configureWorkspaceObservers()
        configureXPCListener(foreground: foreground)
        startEnforcementTimer(intervalSeconds: clampedInterval)

        // Immediately enforce restored policy on startup
        stateQueue.async { [weak self] in
            self?.enforcePolicyLocked(reason: "startup", forceReapply: true)
        }
    }

    private func configureXPCListener(foreground: Bool) {
        let xpcListener: NSXPCListener
        if foreground {
            // Avoid root Mach service bootstrap failures in local developer/test runs
            xpcListener = NSXPCListener.anonymous()
            log("XPC listener initialized in foreground anonymous mode (Mach bootstrap bypassed)")
        } else {
            xpcListener = NSXPCListener(machServiceName: kNudgeHelperMachServiceName)
            log("XPC Mach service listener registered for \(kNudgeHelperMachServiceName)")
        }
        xpcListener.delegate = self
        self.listener = xpcListener
        xpcListener.resume()
    }

    private func startEnforcementTimer(intervalSeconds: Int) {
        let timer = DispatchSource.makeTimerSource(flags: [], queue: stateQueue)
        // 2-second leeway enables macOS timer coalescing for <0.5% idle CPU usage
        timer.schedule(
            deadline: .now() + .seconds(intervalSeconds),
            repeating: .seconds(intervalSeconds),
            leeway: .seconds(Self.defaultLeewaySeconds)
        )
        timer.setEventHandler { [weak self] in
            self?.enforcePolicyLocked(reason: "timer", forceReapply: false)
        }
        enforcementTimer = timer
        timer.resume()
    }

    private func configureWorkspaceObservers() {
        let center = NSWorkspace.shared.notificationCenter

        let resignObserver = center.addObserver(
            forName: NSWorkspace.sessionDidResignActiveNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.handleSessionResignedActive()
        }

        let becomeObserver = center.addObserver(
            forName: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.handleSessionBecameActive()
        }

        let sleepObserver = center.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.handleSystemWillSleep()
        }

        let wakeObserver = center.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.handleSystemDidWake()
        }

        workspaceObservers = [resignObserver, becomeObserver, sleepObserver, wakeObserver]
    }

    private func configureSignalHandlers() {
        signal(SIGTERM, SIG_IGN)
        signal(SIGINT, SIG_IGN)

        let termSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: stateQueue)
        termSource.setEventHandler { [weak self] in
            self?.handleShutdownSignalLocked(signalName: "SIGTERM")
        }
        termSource.resume()
        sigTermSource = termSource

        let intSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: stateQueue)
        intSource.setEventHandler { [weak self] in
            self?.handleShutdownSignalLocked(signalName: "SIGINT")
        }
        intSource.resume()
        sigIntSource = intSource
    }

    // MARK: - Fast User Switching & Power Events

    private func handleSessionResignedActive() {
        stateQueue.async { [weak self] in
            guard let self else { return }
            self.isUserSessionActive = false
            self.state.lastUpdated = Date()
            self.stateStore?.save(self.state)
            self.log("Fast User Switching: session resigned active; maintaining persisted limit (\(self.state.chargeLimit)%) in background")
            self.enforcePolicyLocked(reason: "session-resign", forceReapply: true)
        }
    }

    private func handleSessionBecameActive() {
        stateQueue.async { [weak self] in
            guard let self else { return }
            self.isUserSessionActive = true
            self.log("Fast User Switching: session became active; re-asserting charge limit (\(self.state.chargeLimit)%)")
            self.enforcePolicyLocked(reason: "session-active", forceReapply: true)
        }
    }

    private func handleSystemWillSleep() {
        stateQueue.async { [weak self] in
            guard let self else { return }
            self.isSystemSleeping = true
            self.state.lastUpdated = Date()
            self.stateStore?.save(self.state)

            if self.shouldEnforceLocked() && BatteryManager.shared.config.stopChargingWhenSleeping {
                self.log("System will sleep: asserting charge inhibit to prevent sleep-time overcharge")
                self.applySMCStateLocked(
                    limit: self.state.chargeLimit,
                    inhibit: true,
                    discharge: false,
                    led: self.state.magSafeLEDState,
                    forceReapply: true
                )
            }
        }
    }

    private func handleSystemDidWake() {
        stateQueue.async { [weak self] in
            guard let self else { return }
            self.isSystemSleeping = false
            self.log("System did wake: re-enforcing SMC charge policy")
            self.enforcePolicyLocked(reason: "wake", forceReapply: true)
        }
    }

    // MARK: - Clean Shutdown

    private func handleShutdownSignalLocked(signalName: String) {
        guard !isShuttingDown else { return }
        isShuttingDown = true

        log("Received \(signalName); shutting down cleanly (stopChargingWhenClosed=\(state.stopChargingWhenClosed))")

        enforcementTimer?.cancel()
        enforcementTimer = nil

        listener?.invalidate()
        listener = nil

        for connection in activeConnections.values {
            connection.invalidate()
        }
        activeConnections.removeAll()

        let center = NSWorkspace.shared.notificationCenter
        for observer in workspaceObservers {
            center.removeObserver(observer)
        }
        workspaceObservers.removeAll()

        state.lastUpdated = Date()
        stateStore?.save(state)

        if state.stopChargingWhenClosed {
            log("Preserving enforced SMC charge limit (\(state.chargeLimit)%) on exit per stopChargingWhenClosed=true")
        } else {
            log("Restoring safe default SMC charging state on exit per stopChargingWhenClosed=false")
            restoreSafeSMCStateLocked()
        }

        fflush(stdout)
        fflush(stderr)
        exit(EXIT_SUCCESS)
    }

    // MARK: - NSXPCListenerDelegate

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        let pid = newConnection.processIdentifier
        guard pid > 0 else {
            log("Rejected XPC connection with invalid PID \(pid)")
            return false
        }

        let exportedInterface = NSXPCInterface(with: NudgeHelperProtocol.self)
        newConnection.exportedInterface = exportedInterface
        newConnection.exportedObject = self

        let connectionID = ObjectIdentifier(newConnection)

        newConnection.interruptionHandler = { [weak self] in
            self?.stateQueue.async {
                self?.log("XPC client interrupted (pid=\(pid))")
                self?.removeClientConnectionLocked(connectionID)
            }
        }

        newConnection.invalidationHandler = { [weak self] in
            self?.stateQueue.async {
                self?.log("XPC client disconnected (pid=\(pid))")
                self?.removeClientConnectionLocked(connectionID)
            }
        }

        stateQueue.async { [weak self] in
            self?.activeConnections[connectionID] = newConnection
            self?.log("Accepted XPC client connection (pid=\(pid), activeClients=\(self?.activeConnections.count ?? 0))")
        }

        newConnection.resume()
        return true
    }

    private func removeClientConnectionLocked(_ id: ObjectIdentifier) {
        activeConnections.removeValue(forKey: id)
        guard activeConnections.isEmpty else { return }

        if state.stopChargingWhenClosed {
            log("All UI clients closed; continuing autonomous charge limit enforcement (\(state.chargeLimit)%)")
            enforcePolicyLocked(reason: "clients-closed-persist", forceReapply: false)
        } else {
            log("All UI clients closed and stopChargingWhenClosed=false; restoring default SMC charging behavior")
            restoreSafeSMCStateLocked()
        }
    }

    // MARK: - NudgeHelperProtocol

    func setChargeLimit(
        _ limit: Int,
        sailingDeadband: Int,
        inhibitCharging: Bool,
        forceDischarge: Bool,
        reply: @escaping (Bool) -> Void
    ) {
        stateQueue.async { [weak self] in
            guard let self else {
                reply(false)
                return
            }

            let clampedLimit = max(20, min(100, limit))
            let clampedDeadband = max(1, min(20, sailingDeadband))

            self.state.chargeLimit = clampedLimit
            self.state.sailingDeadband = clampedDeadband
            self.state.inhibitCharging = inhibitCharging
            self.state.forceDischarge = forceDischarge
            self.state.lastUpdated = Date()

            self.syncBatteryManagerLocked()
            self.stateStore?.save(self.state)

            let applied = self.applySMCStateLocked(
                limit: clampedLimit,
                inhibit: inhibitCharging,
                discharge: forceDischarge,
                led: self.state.magSafeLEDState,
                forceReapply: true
            )
            self.log("XPC setChargeLimit(limit=\(clampedLimit)%, deadband=\(clampedDeadband)%, inhibit=\(inhibitCharging), discharge=\(forceDischarge)) -> \(applied)")
            reply(applied)
        }
    }

    func setMagSafeLED(_ modeRaw: String, reply: @escaping (Bool) -> Void) {
        stateQueue.async { [weak self] in
            guard let self else {
                reply(false)
                return
            }

            let resolved = Self.parseMagSafeLED(modeRaw)
            self.state.magSafeLEDModeRaw = resolved.rawValue
            self.state.lastUpdated = Date()
            self.stateStore?.save(self.state)

            _ = SMCClient.shared.setMagSafeLED(resolved)
            BatteryManager.shared.setMagSafeLED(resolved)
            self.lastAppliedLED = resolved
            self.log("XPC setMagSafeLED(\(resolved.rawValue))")
            reply(true)
        }
    }

    func setStopChargingWhenClosed(_ enabled: Bool, reply: @escaping (Bool) -> Void) {
        stateQueue.async { [weak self] in
            guard let self else {
                reply(false)
                return
            }

            self.state.stopChargingWhenClosed = enabled
            self.state.lastUpdated = Date()
            self.syncBatteryManagerLocked()
            self.stateStore?.save(self.state)

            if !enabled && self.activeConnections.isEmpty {
                self.restoreSafeSMCStateLocked()
            }

            self.log("XPC setStopChargingWhenClosed(\(enabled))")
            reply(true)
        }
    }

    func getStatus(reply: @escaping (Int, Bool, Bool, String) -> Void) {
        stateQueue.async { [weak self] in
            guard let self else {
                reply(80, false, false, Self.daemonVersion)
                return
            }
            let effectiveInhibit = self.lastAppliedInhibit ?? self.state.inhibitCharging
            let effectiveDischarge = self.lastAppliedDischarge ?? self.state.forceDischarge
            reply(self.state.chargeLimit, effectiveInhibit, effectiveDischarge, Self.daemonVersion)
        }
    }

    // MARK: - Policy Enforcement

    private func shouldEnforceLocked() -> Bool {
        !activeConnections.isEmpty || state.stopChargingWhenClosed
    }

    private func syncBatteryManagerLocked() {
        let currentLimit = state.chargeLimit
        let currentDeadband = state.sailingDeadband
        let currentStopClosed = state.stopChargingWhenClosed
        let currentLED = state.magSafeLEDState

        BatteryManager.shared.updateConfig { config in
            config.chargeLimit = currentLimit
            config.sailingDeadband = currentDeadband
            config.stopChargingWhenAppClosed = currentStopClosed
            config.magSafeLEDMode = currentLED
        }
    }

    private func enforcePolicyLocked(reason: String, forceReapply: Bool) {
        guard !isShuttingDown else { return }

        guard shouldEnforceLocked() else {
            restoreSafeSMCStateLocked()
            return
        }

        let tick = BatteryManager.shared.tick()

        let desiredInhibit: Bool
        let desiredDischarge: Bool

        if !activeConnections.isEmpty {
            // While UI app is connected, honor explicit XPC policy plus protective manager signals
            desiredInhibit = state.inhibitCharging || tick.chargingInhibited
            desiredDischarge = state.forceDischarge || tick.forceDischarge
        } else {
            // Autonomous background mode (app closed or Fast User Switching)
            desiredInhibit = tick.chargingInhibited
            desiredDischarge = tick.forceDischarge
            state.inhibitCharging = desiredInhibit
            state.forceDischarge = desiredDischarge
        }

        _ = applySMCStateLocked(
            limit: state.chargeLimit,
            inhibit: desiredInhibit,
            discharge: desiredDischarge,
            led: tick.activeMagSafeLED,
            forceReapply: forceReapply
        )

        if isForegroundMode || forceReapply {
            log("Tick[\(reason)] pct=\(tick.snapshot.displayPercentage)% temp=\(String(format: "%.1f", tick.snapshot.temperatureCelsius))C limit=\(state.chargeLimit)% inhibit=\(desiredInhibit) discharge=\(desiredDischarge) sessionActive=\(isUserSessionActive)")
        }
    }

    @discardableResult
    private func applySMCStateLocked(
        limit: Int,
        inhibit: Bool,
        discharge: Bool,
        led: MagSafeLEDState,
        forceReapply: Bool
    ) -> Bool {
        var success = true

        if forceReapply || lastAppliedLimit != limit {
            _ = SMCClient.shared.setChargeLimit(limit)
            lastAppliedLimit = limit
        }

        if forceReapply || lastAppliedInhibit != inhibit {
            let ok = SMCClient.shared.setChargeInhibited(inhibit)
            lastAppliedInhibit = inhibit
            success = success && ok
        }

        if forceReapply || lastAppliedDischarge != discharge {
            let ok = SMCClient.shared.setForceDischarge(discharge)
            lastAppliedDischarge = discharge
            success = success && ok
        }

        if forceReapply || lastAppliedLED != led {
            _ = SMCClient.shared.setMagSafeLED(led)
            BatteryManager.shared.setMagSafeLED(led)
            lastAppliedLED = led
        }

        // In foreground/non-root testing without direct SMC privilege, SMC writes may return false
        // while daemon policy state is still validly tracked.
        return isForegroundMode ? true : success
    }

    private func restoreSafeSMCStateLocked() {
        if lastAppliedLimit != 100 {
            _ = SMCClient.shared.setChargeLimit(100)
            lastAppliedLimit = 100
        }
        if lastAppliedInhibit != false {
            _ = SMCClient.shared.setChargeInhibited(false)
            lastAppliedInhibit = false
        }
        if lastAppliedDischarge != false {
            _ = SMCClient.shared.setForceDischarge(false)
            lastAppliedDischarge = false
        }
        if lastAppliedLED != .systemDefault {
            _ = SMCClient.shared.setMagSafeLED(.systemDefault)
            BatteryManager.shared.setMagSafeLED(.systemDefault)
            lastAppliedLED = .systemDefault
        }
    }

    // MARK: - Helpers

    private func currentStateSnapshot() -> HelperDaemonState {
        stateQueue.sync { state }
    }

    private static func parseMagSafeLED(_ raw: String) -> MagSafeLEDState {
        if let exact = MagSafeLEDState(rawValue: raw) {
            return exact
        }
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "green": return .green
        case "orange": return .orange
        case "blink", "blinking", "blinking orange", "blinkingorange": return .blinkingOrange
        case "off": return .off
        default: return .systemDefault
        }
    }

    private func log(_ message: String) {
        logger.notice("\(message, privacy: .public)")
        if isForegroundMode {
            print("[NudgeHelper] \(message)")
            fflush(stdout)
        }
    }
}
