import Foundation
import ServiceManagement

/// Describes how Nudge is currently registered to start automatically at macOS login.
public enum LaunchAtLoginBackend: String, Codable, Sendable, Equatable {
    case disabled = "Disabled"
    case smAppService = "macOS Login Item"
    case launchAgent = "LaunchAgent"
    case requiresApproval = "Requires Approval in System Settings"
}

public struct LaunchAtLoginStatus: Sendable, Equatable {
    public let isEnabled: Bool
    public let backend: LaunchAtLoginBackend
    public let targetBundlePath: String?
    public let lastError: String?

    public init(
        isEnabled: Bool,
        backend: LaunchAtLoginBackend,
        targetBundlePath: String? = nil,
        lastError: String? = nil
    ) {
        self.isEnabled = isEnabled
        self.backend = backend
        self.targetBundlePath = targetBundlePath
        self.lastError = lastError
    }
}

/// Manages starting Nudge automatically at macOS login.
/// Uses `SMAppService.mainApp` when available and falls back seamlessly to a per-user
/// LaunchAgent (`~/Library/LaunchAgents/com.emrisca.nudge.launcher.plist`) for ad-hoc signed builds.
@MainActor
public final class LaunchAtLoginManager: ObservableObject {
    public static let shared = LaunchAtLoginManager()

    public nonisolated static let launchAgentLabel = "com.emrisca.nudge.launcher"

    private enum DefaultsKey {
        static let launchAtLogin = "nudge.startup.launchAtLogin"
    }

    @Published public private(set) var isEnabled: Bool
    @Published public private(set) var status: LaunchAtLoginStatus

    private let defaults: UserDefaults
    private let launchAgentsDirectory: URL
    private let bundleURLProvider: () -> URL
    private let useSMAppService: Bool

    public init(
        defaults: UserDefaults = .standard,
        launchAgentsDirectory: URL? = nil,
        bundleURLProvider: @escaping () -> URL = { Bundle.main.bundleURL },
        useSMAppService: Bool = true
    ) {
        self.defaults = defaults
        let homeAgents = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
        self.launchAgentsDirectory = launchAgentsDirectory ?? homeAgents
        self.bundleURLProvider = bundleURLProvider
        self.useSMAppService = useSMAppService

        let storedEnabled: Bool
        if defaults.object(forKey: DefaultsKey.launchAtLogin) == nil {
            storedEnabled = true
        } else {
            storedEnabled = defaults.bool(forKey: DefaultsKey.launchAtLogin)
        }
        self.isEnabled = storedEnabled
        self.status = LaunchAtLoginStatus(
            isEnabled: storedEnabled,
            backend: storedEnabled ? .launchAgent : .disabled
        )
        refreshStatus()
    }

    public var launchAgentPlistURL: URL {
        launchAgentsDirectory.appendingPathComponent("\(Self.launchAgentLabel).plist", isDirectory: false)
    }

    /// Synchronizes the OS registration with the user's saved preference when Nudge launches.
    public func syncOnLaunch() {
        setEnabled(isEnabled)
    }

    /// Enables or disables starting Nudge automatically at macOS login.
    @discardableResult
    public func setEnabled(_ enabled: Bool) -> LaunchAtLoginStatus {
        defaults.set(enabled, forKey: DefaultsKey.launchAtLogin)
        isEnabled = enabled

        if enabled {
            return enableLoginStartup()
        } else {
            return disableLoginStartup()
        }
    }

    /// Refreshes live OS registration status without mutating preferences.
    public func refreshStatus() {
        let agentPath = readLaunchAgentBundlePath()

        if useSMAppService, isRunningInsideAppBundle {
            switch SMAppService.mainApp.status {
            case .enabled:
                status = LaunchAtLoginStatus(
                    isEnabled: true,
                    backend: .smAppService,
                    targetBundlePath: bundleURLProvider().path
                )
                return
            case .requiresApproval:
                if let agentPath {
                    status = LaunchAtLoginStatus(
                        isEnabled: true,
                        backend: .launchAgent,
                        targetBundlePath: agentPath
                    )
                } else {
                    status = LaunchAtLoginStatus(
                        isEnabled: isEnabled,
                        backend: .requiresApproval,
                        targetBundlePath: bundleURLProvider().path
                    )
                }
                return
            default:
                break
            }
        }

        if let agentPath {
            status = LaunchAtLoginStatus(
                isEnabled: true,
                backend: .launchAgent,
                targetBundlePath: agentPath
            )
        } else {
            status = LaunchAtLoginStatus(
                isEnabled: false,
                backend: .disabled,
                targetBundlePath: nil
            )
        }
    }

    // MARK: - Registration Implementations

    private var isRunningInsideAppBundle: Bool {
        bundleURLProvider().pathExtension.lowercased() == "app"
    }

    private func resolvedTargetBundlePath() -> String? {
        let current = bundleURLProvider()
        if current.pathExtension.lowercased() == "app" {
            return current.path
        }
        let applicationsApp = "/Applications/Nudge.app"
        if FileManager.default.fileExists(atPath: applicationsApp) {
            return applicationsApp
        }
        return nil
    }

    private func enableLoginStartup() -> LaunchAtLoginStatus {
        var smError: String?

        // 1. Try native SMAppService.mainApp when running inside a real .app bundle
        if useSMAppService, isRunningInsideAppBundle {
            let service = SMAppService.mainApp
            do {
                if service.status != .enabled {
                    try service.register()
                }
                if service.status == .enabled {
                    removeLaunchAgentPlist()
                    status = LaunchAtLoginStatus(
                        isEnabled: true,
                        backend: .smAppService,
                        targetBundlePath: bundleURLProvider().path
                    )
                    return status
                }
            } catch {
                smError = error.localizedDescription
            }
        }

        // 2. Fallback to per-user LaunchAgent (reliable for ad-hoc signed builds and custom locations)
        guard let targetBundlePath = resolvedTargetBundlePath() else {
            status = LaunchAtLoginStatus(
                isEnabled: false,
                backend: .disabled,
                targetBundlePath: nil,
                lastError: smError ?? "Run Nudge from Nudge.app to enable Launch at Login."
            )
            return status
        }

        do {
            try writeLaunchAgentPlist(forAppBundlePath: targetBundlePath)
            status = LaunchAtLoginStatus(
                isEnabled: true,
                backend: .launchAgent,
                targetBundlePath: targetBundlePath
            )
        } catch {
            status = LaunchAtLoginStatus(
                isEnabled: false,
                backend: .disabled,
                targetBundlePath: nil,
                lastError: error.localizedDescription
            )
        }

        return status
    }

    private func disableLoginStartup() -> LaunchAtLoginStatus {
        var unregisterError: String?

        if useSMAppService, isRunningInsideAppBundle {
            let service = SMAppService.mainApp
            if service.status == .enabled || service.status == .requiresApproval {
                do {
                    try service.unregister()
                } catch {
                    unregisterError = error.localizedDescription
                }
            }
        }

        removeLaunchAgentPlist()

        status = LaunchAtLoginStatus(
            isEnabled: false,
            backend: .disabled,
            targetBundlePath: nil,
            lastError: unregisterError
        )
        return status
    }

    // MARK: - LaunchAgent Plist Helpers

    public nonisolated static func buildLaunchAgentDictionary(appBundlePath: String) -> [String: Any] {
        [
            "Label": launchAgentLabel,
            "ProgramArguments": ["/usr/bin/open", "-g", appBundlePath],
            "RunAtLoad": true,
            "KeepAlive": false,
            "LimitLoadToSessionType": "Aqua"
        ]
    }

    private func writeLaunchAgentPlist(forAppBundlePath appBundlePath: String) throws {
        try FileManager.default.createDirectory(at: launchAgentsDirectory, withIntermediateDirectories: true)
        let dict = Self.buildLaunchAgentDictionary(appBundlePath: appBundlePath)
        let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        try data.write(to: launchAgentPlistURL, options: .atomic)
    }

    private func removeLaunchAgentPlist() {
        let fm = FileManager.default
        if fm.fileExists(atPath: launchAgentPlistURL.path) {
            try? fm.removeItem(at: launchAgentPlistURL)
        }
    }

    private func readLaunchAgentBundlePath() -> String? {
        guard FileManager.default.fileExists(atPath: launchAgentPlistURL.path),
              let data = try? Data(contentsOf: launchAgentPlistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let args = plist["ProgramArguments"] as? [String],
              let path = args.last,
              path.hasSuffix(".app") else {
            return nil
        }
        return path
    }
}
