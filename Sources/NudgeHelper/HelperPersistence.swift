import Foundation
import NudgeCore

/// Persisted daemon state that survives Fast User Switching, app termination, and LaunchDaemon restarts.
struct HelperDaemonState: Codable, Sendable, Equatable {
    var chargeLimit: Int = 80
    var sailingDeadband: Int = 5
    var inhibitCharging: Bool = false
    var forceDischarge: Bool = false
    var magSafeLEDModeRaw: String = MagSafeLEDState.systemDefault.rawValue
    var stopChargingWhenClosed: Bool = true
    var lastUpdated: Date = Date()

    var magSafeLEDState: MagSafeLEDState {
        MagSafeLEDState(rawValue: magSafeLEDModeRaw) ?? .systemDefault
    }
}

/// Atomic file-backed persistence for the privileged helper daemon.
/// Uses `/Library/Application Support/Nudge/` when running as root (shared across Fast User Switching),
/// and falls back to `~/Library/Application Support/Nudge/` in unprivileged `--foreground` test mode.
final class HelperStateStore: @unchecked Sendable {
    let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(foreground: Bool) {
        let baseDirectory: URL
        if !foreground && geteuid() == 0 {
            baseDirectory = URL(fileURLWithPath: "/Library/Application Support/Nudge", isDirectory: true)
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            baseDirectory = appSupport.appendingPathComponent("Nudge", isDirectory: true)
        }

        self.fileURL = baseDirectory.appendingPathComponent("helper-state.json", isDirectory: false)

        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        self.encoder = enc

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec
    }

    func load() -> HelperDaemonState {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return HelperDaemonState()
        }
        do {
            let data = try Data(contentsOf: fileURL)
            var state = try decoder.decode(HelperDaemonState.self, from: data)
            state.chargeLimit = max(20, min(100, state.chargeLimit))
            state.sailingDeadband = max(1, min(20, state.sailingDeadband))
            return state
        } catch {
            return HelperDaemonState()
        }
    }

    func save(_ state: HelperDaemonState) {
        do {
            let dir = fileURL.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: dir.path) {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            let data = try encoder.encode(state)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            fputs("[NudgeHelper] Warning: failed to persist daemon state to \(fileURL.path): \(error.localizedDescription)\n", stderr)
        }
    }
}
