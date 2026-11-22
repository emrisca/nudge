import Foundation
import ServiceManagement

public let kNudgeHelperMachServiceName = "com.emrisca.nudge.helper"
public let kNudgeHelperPlistName = "com.emrisca.nudge.helper.plist"

/// XPC protocol exposed by the privileged `nudge-helper` launch daemon.
@objc public protocol NudgeHelperProtocol {
    func setChargeLimit(
        _ limit: Int,
        sailingDeadband: Int,
        inhibitCharging: Bool,
        forceDischarge: Bool,
        reply: @escaping (Bool) -> Void
    )
    func setMagSafeLED(_ modeRaw: String, reply: @escaping (Bool) -> Void)
    func setStopChargingWhenClosed(_ enabled: Bool, reply: @escaping (Bool) -> Void)
    func getStatus(reply: @escaping (Int, Bool, Bool, String) -> Void)
}

/// Manages NSXPCConnection communication and SMAppService registration state for the privileged helper daemon.
public final class HelperXPCClient: @unchecked Sendable {
    public static let shared = HelperXPCClient()

    private let lock = NSLock()
    private var connection: NSXPCConnection?
    private var cachedStatus: HelperDaemonStatus

    public init() {
        self.cachedStatus = HelperDaemonStatus(
            isInstalled: false,
            isConnected: false,
            version: "1.0.0",
            lastHeartbeat: nil,
            enforcedLimit: nil,
            fastUserSwitchingProtected: true
        )
        _ = refreshStatus(probeXPC: false)
    }

    deinit {
        disconnect()
    }

    public var status: HelperDaemonStatus {
        lock.lock()
        defer { lock.unlock() }
        return cachedStatus
    }

    public var isConnected: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cachedStatus.isConnected && connection != nil
    }

    /// Inspects SMAppService.daemon registration state and optionally probes the running XPC service.
    @discardableResult
    public func refreshStatus(probeXPC: Bool = true) -> HelperDaemonStatus {
        let installed = checkDaemonInstalled()

        if !installed || !probeXPC {
            lock.lock()
            let updated = HelperDaemonStatus(
                isInstalled: installed,
                isConnected: installed ? cachedStatus.isConnected : false,
                version: cachedStatus.version,
                lastHeartbeat: cachedStatus.lastHeartbeat,
                enforcedLimit: cachedStatus.enforcedLimit,
                fastUserSwitchingProtected: true
            )
            cachedStatus = updated
            lock.unlock()
            return updated
        }

        return probeConnection(isInstalled: installed)
    }

    /// Attempts to register the SMAppService daemon if needed and establish an XPC connection.
    @discardableResult
    public func installOrConnect() -> HelperDaemonStatus {
        let service = SMAppService.daemon(plistName: kNudgeHelperPlistName)
        if service.status == .notRegistered || service.status == .notFound {
            do {
                try service.register()
            } catch {
                // Registration fails gracefully in unsigned/dev builds or before user approves in Login Items.
            }
        }

        let installed = checkDaemonInstalled()
        return probeConnection(isInstalled: installed)
    }

    public func disconnect() {
        lock.lock()
        let existing = connection
        connection = nil
        cachedStatus = HelperDaemonStatus(
            isInstalled: cachedStatus.isInstalled,
            isConnected: false,
            version: cachedStatus.version,
            lastHeartbeat: cachedStatus.lastHeartbeat,
            enforcedLimit: cachedStatus.enforcedLimit,
            fastUserSwitchingProtected: cachedStatus.fastUserSwitchingProtected
        )
        lock.unlock()
        existing?.invalidate()
    }

    // MARK: - XPC Commands

    @discardableResult
    public func setChargeLimit(
        _ limit: Int,
        sailingDeadband: Int,
        inhibitCharging: Bool,
        forceDischarge: Bool,
        completion: (@Sendable (Bool) -> Void)? = nil
    ) -> Bool {
        guard let proxy = remoteProxy(onError: { completion?(false) }) else {
            completion?(false)
            return false
        }
        proxy.setChargeLimit(
            limit,
            sailingDeadband: sailingDeadband,
            inhibitCharging: inhibitCharging,
            forceDischarge: forceDischarge
        ) { [weak self] success in
            if success {
                self?.recordHeartbeat(enforcedLimit: limit)
            }
            completion?(success)
        }
        return true
    }

    @discardableResult
    public func setMagSafeLED(_ mode: MagSafeLEDState, completion: (@Sendable (Bool) -> Void)? = nil) -> Bool {
        guard let proxy = remoteProxy(onError: { completion?(false) }) else {
            completion?(false)
            return false
        }
        proxy.setMagSafeLED(mode.rawValue) { [weak self] success in
            if success {
                self?.recordHeartbeat(enforcedLimit: nil)
            }
            completion?(success)
        }
        return true
    }

    @discardableResult
    public func setStopChargingWhenClosed(_ enabled: Bool, completion: (@Sendable (Bool) -> Void)? = nil) -> Bool {
        guard let proxy = remoteProxy(onError: { completion?(false) }) else {
            completion?(false)
            return false
        }
        proxy.setStopChargingWhenClosed(enabled) { [weak self] success in
            if success {
                self?.recordHeartbeat(enforcedLimit: nil)
            }
            completion?(success)
        }
        return true
    }

    // MARK: - Internal Helpers

    private func checkDaemonInstalled() -> Bool {
        let service = SMAppService.daemon(plistName: kNudgeHelperPlistName)
        switch service.status {
        case .enabled:
            return true
        case .requiresApproval:
            return true
        case .notRegistered, .notFound:
            // Also check legacy SMJobBless LaunchDaemons plist location
            let legacyPath = "/Library/LaunchDaemons/\(kNudgeHelperPlistName)"
            return FileManager.default.fileExists(atPath: legacyPath)
        @unknown default:
            return false
        }
    }

    private func ensureConnectionLocked() -> NSXPCConnection {
        if let existing = connection {
            return existing
        }
        let conn = NSXPCConnection(machServiceName: kNudgeHelperMachServiceName, options: .privileged)
        conn.remoteObjectInterface = NSXPCInterface(with: NudgeHelperProtocol.self)
        conn.invalidationHandler = { [weak self] in
            self?.handleConnectionClosed()
        }
        conn.interruptionHandler = { [weak self] in
            self?.handleConnectionInterrupted()
        }
        conn.resume()
        connection = conn
        return conn
    }

    private func remoteProxy(onError: @escaping () -> Void) -> NudgeHelperProtocol? {
        lock.lock()
        guard cachedStatus.isInstalled || cachedStatus.isConnected else {
            lock.unlock()
            return nil
        }
        let conn = ensureConnectionLocked()
        lock.unlock()

        return conn.remoteObjectProxyWithErrorHandler { [weak self] _ in
            self?.handleConnectionInterrupted()
            onError()
        } as? NudgeHelperProtocol
    }

    private func probeConnection(isInstalled: Bool) -> HelperDaemonStatus {
        guard isInstalled else {
            lock.lock()
            let updated = HelperDaemonStatus(
                isInstalled: false,
                isConnected: false,
                version: cachedStatus.version,
                lastHeartbeat: cachedStatus.lastHeartbeat,
                enforcedLimit: cachedStatus.enforcedLimit,
                fastUserSwitchingProtected: true
            )
            cachedStatus = updated
            lock.unlock()
            return updated
        }

        lock.lock()
        let conn = ensureConnectionLocked()
        lock.unlock()

        let semaphore = DispatchSemaphore(value: 0)
        final class ProbeBox: @unchecked Sendable {
            var connected = false
            var limit: Int?
            var version = "1.0.0"
        }
        let box = ProbeBox()

        if let proxy = conn.remoteObjectProxyWithErrorHandler({ _ in
            semaphore.signal()
        }) as? NudgeHelperProtocol {
            proxy.getStatus { limit, _, _, version in
                box.connected = true
                box.limit = limit
                box.version = version.isEmpty ? "1.0.0" : version
                semaphore.signal()
            }
            _ = semaphore.wait(timeout: .now() + 0.35)
        }

        lock.lock()
        let updated = HelperDaemonStatus(
            isInstalled: isInstalled,
            isConnected: box.connected,
            version: box.version,
            lastHeartbeat: box.connected ? Date() : cachedStatus.lastHeartbeat,
            enforcedLimit: box.limit ?? cachedStatus.enforcedLimit,
            fastUserSwitchingProtected: true
        )
        cachedStatus = updated
        lock.unlock()
        return updated
    }

    private func recordHeartbeat(enforcedLimit: Int?) {
        lock.lock()
        defer { lock.unlock() }
        cachedStatus = HelperDaemonStatus(
            isInstalled: true,
            isConnected: true,
            version: cachedStatus.version,
            lastHeartbeat: Date(),
            enforcedLimit: enforcedLimit ?? cachedStatus.enforcedLimit,
            fastUserSwitchingProtected: true
        )
    }

    private func handleConnectionInterrupted() {
        lock.lock()
        defer { lock.unlock() }
        cachedStatus = HelperDaemonStatus(
            isInstalled: cachedStatus.isInstalled,
            isConnected: false,
            version: cachedStatus.version,
            lastHeartbeat: cachedStatus.lastHeartbeat,
            enforcedLimit: cachedStatus.enforcedLimit,
            fastUserSwitchingProtected: true
        )
    }

    private func handleConnectionClosed() {
        lock.lock()
        connection = nil
        cachedStatus = HelperDaemonStatus(
            isInstalled: cachedStatus.isInstalled,
            isConnected: false,
            version: cachedStatus.version,
            lastHeartbeat: cachedStatus.lastHeartbeat,
            enforcedLimit: cachedStatus.enforcedLimit,
            fastUserSwitchingProtected: true
        )
        lock.unlock()
    }
}
