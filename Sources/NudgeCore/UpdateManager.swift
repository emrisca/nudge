import Foundation
import CryptoKit

// MARK: - Version & Repository Metadata

public enum NudgeVersion {
    public static let fallbackVersion = "1.1.0"
    public static let repositoryOwner = "emrisca"
    public static let repositoryName = "nudge"
    public static let bundleIdentifier = "com.emrisca.nudge"

    public static var releasesPageURL: URL {
        URL(string: "https://github.com/\(repositoryOwner)/\(repositoryName)/releases")!
    }

    public static var latestReleaseAPIURL: URL {
        URL(string: "https://api.github.com/repos/\(repositoryOwner)/\(repositoryName)/releases/latest")!
    }

    public static var allReleasesAPIURL: URL {
        URL(string: "https://api.github.com/repos/\(repositoryOwner)/\(repositoryName)/releases?per_page=15")!
    }

    public static var current: String {
        if let infoVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
           !infoVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return infoVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return fallbackVersion
    }

    public static var currentArchitecture: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "universal"
        #endif
    }
}

// MARK: - Semantic Versioning (SemVer 2.0.0)

public struct SemanticVersion: Comparable, Codable, Sendable, Hashable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let prerelease: [String]

    public init(major: Int, minor: Int, patch: Int, prerelease: [String] = []) {
        self.major = max(0, major)
        self.minor = max(0, minor)
        self.patch = max(0, patch)
        self.prerelease = prerelease
    }

    /// Parses version strings such as `"v1.2.3"`, `"1.2.3"`, `"1.2"`, `"v2.0.0-beta.1"`, or `"1.0.0+build.5"`.
    public init?(parsing raw: String) {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("v") || cleaned.hasPrefix("V") {
            cleaned.removeFirst()
        }
        guard !cleaned.isEmpty else { return nil }

        // Strip build metadata (+...)
        if let plusIdx = cleaned.firstIndex(of: "+") {
            cleaned = String(cleaned[..<plusIdx])
        }

        // Split prerelease (-...)
        let mainPart: String
        let prereleaseIdentifiers: [String]
        if let dashIdx = cleaned.firstIndex(of: "-") {
            mainPart = String(cleaned[..<dashIdx])
            let preString = String(cleaned[cleaned.index(after: dashIdx)...])
            prereleaseIdentifiers = preString
                .split(separator: ".")
                .map(String.init)
                .filter { !$0.isEmpty }
        } else {
            mainPart = cleaned
            prereleaseIdentifiers = []
        }

        let numericParts = mainPart.split(separator: ".").map(String.init)
        guard !numericParts.isEmpty && numericParts.count <= 3 else { return nil }

        var nums: [Int] = []
        for part in numericParts {
            guard let n = Int(part), n >= 0 else { return nil }
            nums.append(n)
        }

        self.major = nums[0]
        self.minor = nums.count > 1 ? nums[1] : 0
        self.patch = nums.count > 2 ? nums[2] : 0
        self.prerelease = prereleaseIdentifiers
    }

    public var isPrerelease: Bool {
        !prerelease.isEmpty
    }

    public var description: String {
        let core = "\(major).\(minor).\(patch)"
        if prerelease.isEmpty {
            return core
        }
        return "\(core)-\(prerelease.joined(separator: "."))"
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }

        // SemVer 2.0.0: a normal version has higher precedence than a pre-release version
        switch (lhs.prerelease.isEmpty, rhs.prerelease.isEmpty) {
        case (true, true):
            return false
        case (false, true):
            return true
        case (true, false):
            return false
        case (false, false):
            let count = max(lhs.prerelease.count, rhs.prerelease.count)
            for idx in 0..<count {
                if idx >= lhs.prerelease.count { return true }
                if idx >= rhs.prerelease.count { return false }
                let a = lhs.prerelease[idx]
                let b = rhs.prerelease[idx]
                if a == b { continue }
                if let ai = Int(a), let bi = Int(b) {
                    return ai < bi
                }
                // Numeric identifiers always have lower precedence than non-numeric identifiers
                if Int(a) != nil { return true }
                if Int(b) != nil { return false }
                return a < b
            }
            return false
        }
    }
}

// MARK: - GitHub Releases API Models

public struct GitHubReleaseAsset: Codable, Sendable, Equatable, Identifiable {
    public let id: Int
    public let name: String
    public let size: Int64
    public let browserDownloadURL: URL
    public let contentType: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case size
        case browserDownloadURL = "browser_download_url"
        case contentType = "content_type"
    }

    public init(id: Int, name: String, size: Int64, browserDownloadURL: URL, contentType: String? = nil) {
        self.id = id
        self.name = name
        self.size = size
        self.browserDownloadURL = browserDownloadURL
        self.contentType = contentType
    }
}

public struct GitHubRelease: Codable, Sendable, Equatable, Identifiable {
    public let id: Int
    public let tagName: String
    public let name: String
    public let body: String
    public let htmlURL: URL
    public let draft: Bool
    public let prerelease: Bool
    public let publishedAt: Date?
    public let assets: [GitHubReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case id
        case tagName = "tag_name"
        case name
        case body
        case htmlURL = "html_url"
        case draft
        case prerelease
        case publishedAt = "published_at"
        case assets
    }

    public init(
        id: Int,
        tagName: String,
        name: String,
        body: String,
        htmlURL: URL,
        draft: Bool = false,
        prerelease: Bool = false,
        publishedAt: Date? = nil,
        assets: [GitHubReleaseAsset] = []
    ) {
        self.id = id
        self.tagName = tagName
        self.name = name
        self.body = body
        self.htmlURL = htmlURL
        self.draft = draft
        self.prerelease = prerelease
        self.publishedAt = publishedAt
        self.assets = assets
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(Int.self, forKey: .id)
        self.tagName = try container.decode(String.self, forKey: .tagName)
        self.name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? tagName
        self.body = (try? container.decodeIfPresent(String.self, forKey: .body)) ?? ""
        self.htmlURL = try container.decode(URL.self, forKey: .htmlURL)
        self.draft = (try? container.decodeIfPresent(Bool.self, forKey: .draft)) ?? false
        self.prerelease = (try? container.decodeIfPresent(Bool.self, forKey: .prerelease)) ?? false
        self.publishedAt = try? container.decodeIfPresent(Date.self, forKey: .publishedAt)
        self.assets = (try? container.decodeIfPresent([GitHubReleaseAsset].self, forKey: .assets)) ?? []
    }

    public var semanticVersion: SemanticVersion? {
        SemanticVersion(parsing: tagName)
    }

    public var displayVersion: String {
        if tagName.hasPrefix("v") || tagName.hasPrefix("V") {
            return tagName
        }
        return "v\(tagName)"
    }

    /// Selects the optimal macOS installer asset for the given architecture.
    /// Prefers `.zip` (for seamless in-place update) over `.dmg`, and matching architecture or `universal`.
    public func preferredAsset(forArchitecture arch: String = NudgeVersion.currentArchitecture) -> GitHubReleaseAsset? {
        let candidates = assets.filter { asset in
            let lower = asset.name.lowercased()
            return lower.hasSuffix(".zip") || lower.hasSuffix(".dmg")
        }
        guard !candidates.isEmpty else { return nil }

        let targetArch = arch.lowercased()
        let oppositeArch = targetArch == "arm64" ? "x86_64" : "arm64"

        func score(_ asset: GitHubReleaseAsset) -> Int {
            let lower = asset.name.lowercased()
            var points = 0

            // Architecture match
            if lower.contains(targetArch) {
                points += 100
            } else if lower.contains("universal") {
                points += 80
            } else if lower.contains(oppositeArch) {
                points -= 200
            } else {
                points += 40
            }

            // Prefer .zip for one-click in-place extraction via ditto, .dmg as fallback
            if lower.hasSuffix(".zip") {
                points += 20
            } else if lower.hasSuffix(".dmg") {
                points += 10
            }

            // Prefer macOS-labeled artifacts
            if lower.contains("macos") || lower.contains("darwin") {
                points += 5
            }

            return points
        }

        let ranked = candidates.sorted { score($0) > score($1) }
        guard let best = ranked.first, score(best) > -100 else {
            return nil
        }
        return best
    }

    public var checksumAsset: GitHubReleaseAsset? {
        assets.first { asset in
            let lower = asset.name.lowercased()
            return lower == "sha256sums.txt" || lower.contains("sha256")
        }
    }
}

// MARK: - SHA-256 Checksum Parsing & Verification

public enum ChecksumVerifier {
    /// Parses standard `shasum -a 256` output lines (`<64-hex>  <filename>` or `<64-hex> *<filename>`).
    public static func parseChecksums(_ contents: String) -> [String: String] {
        var result: [String: String] = [:]
        for rawLine in contents.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            let parts = line.split(maxSplits: 1, whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count == 2 else { continue }
            let hash = String(parts[0]).lowercased()
            guard hash.count == 64, hash.allSatisfy({ $0.isHexDigit }) else { continue }
            var filename = String(parts[1]).trimmingCharacters(in: .whitespaces)
            if filename.hasPrefix("*") {
                filename.removeFirst()
            }
            if let base = filename.split(separator: "/").last {
                result[String(base)] = hash
            }
            result[filename] = hash
        }
        return result
    }

    public static func sha256Hex(forFileAt url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while autoreleasepool(invoking: {
            let chunk = handle.readData(ofLength: 65_536)
            guard !chunk.isEmpty else { return false }
            hasher.update(data: chunk)
            return true
        }) {}

        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Updater State & Errors

public enum UpdateState: Equatable, Sendable {
    case idle
    case checking
    case upToDate(checkedAt: Date)
    case updateAvailable(GitHubRelease)
    case downloading(release: GitHubRelease, progress: Double, receivedBytes: Int64, totalBytes: Int64)
    case verifying(release: GitHubRelease)
    case installing(release: GitHubRelease)
    case readyToRelaunch(release: GitHubRelease)
    case downloadedInstaller(release: GitHubRelease, fileURL: URL)
    case failed(message: String)

    public var isBusy: Bool {
        switch self {
        case .checking, .downloading, .verifying, .installing:
            return true
        default:
            return false
        }
    }

    public var availableRelease: GitHubRelease? {
        switch self {
        case .updateAvailable(let rel),
             .downloading(let rel, _, _, _),
             .verifying(let rel),
             .installing(let rel),
             .readyToRelaunch(let rel),
             .downloadedInstaller(let rel, _):
            return rel
        default:
            return nil
        }
    }
}

public enum UpdateError: LocalizedError, Sendable {
    case httpError(statusCode: Int, message: String)
    case rateLimited
    case noReleasesFound
    case noCompatibleAsset(arch: String)
    case checksumMismatch(expected: String, actual: String)
    case extractionFailed(String)
    case invalidAppBundle(String)
    case installScriptFailed(String)

    public var errorDescription: String? {
        switch self {
        case .httpError(let code, let message):
            return "GitHub returned HTTP \(code): \(message)"
        case .rateLimited:
            return "GitHub API rate limit reached. Try again in a few minutes."
        case .noReleasesFound:
            return "No published GitHub releases were found for \(NudgeVersion.repositoryOwner)/\(NudgeVersion.repositoryName)."
        case .noCompatibleAsset(let arch):
            return "No compatible macOS (\(arch)) installer asset was found on this release."
        case .checksumMismatch(let expected, let actual):
            return "SHA-256 verification failed (expected \(expected.prefix(12))…, got \(actual.prefix(12))…)."
        case .extractionFailed(let detail):
            return "Could not extract the downloaded update: \(detail)"
        case .invalidAppBundle(let detail):
            return "Downloaded update bundle failed validation: \(detail)"
        case .installScriptFailed(let detail):
            return "Could not launch the update installer: \(detail)"
        }
    }
}

// MARK: - GitHub Releases Update Manager

@MainActor
public final class UpdateManager: ObservableObject {
    public static let shared = UpdateManager()

    private enum DefaultsKey {
        static let automaticChecks = "nudge.updater.automaticChecks"
        static let checkIntervalHours = "nudge.updater.checkIntervalHours"
        static let includePrereleases = "nudge.updater.includePrereleases"
        static let skippedVersion = "nudge.updater.skippedVersion"
        static let lastCheckedAt = "nudge.updater.lastCheckedAt"
    }

    // MARK: - Published State

    @Published public private(set) var state: UpdateState = .idle
    @Published public private(set) var lastCheckedAt: Date?
    @Published public private(set) var latestKnownRelease: GitHubRelease?

    @Published public var automaticChecksEnabled: Bool {
        didSet {
            defaults.set(automaticChecksEnabled, forKey: DefaultsKey.automaticChecks)
            rescheduleBackgroundChecksIfActive()
        }
    }

    @Published public var checkIntervalHours: Int {
        didSet {
            let clamped = max(1, checkIntervalHours)
            if clamped != checkIntervalHours {
                checkIntervalHours = clamped
                return
            }
            defaults.set(clamped, forKey: DefaultsKey.checkIntervalHours)
            rescheduleBackgroundChecksIfActive()
        }
    }

    @Published public var includePrereleases: Bool {
        didSet {
            defaults.set(includePrereleases, forKey: DefaultsKey.includePrereleases)
        }
    }

    @Published public private(set) var skippedVersion: String? {
        didSet {
            if let skippedVersion {
                defaults.set(skippedVersion, forKey: DefaultsKey.skippedVersion)
            } else {
                defaults.removeObject(forKey: DefaultsKey.skippedVersion)
            }
        }
    }

    // MARK: - Configuration & Dependencies

    public let currentVersionString: String
    private let defaults: UserDefaults
    private let session: URLSession
    private var backgroundTask: Task<Void, Never>?
    private var isBackgroundLoopActive: Bool = false

    /// Hook invoked when the updater has staged the replacement bundle and wants the app to exit.
    public var onRequestAppTermination: (@MainActor () -> Void)?

    public init(
        currentVersion: String = NudgeVersion.current,
        defaults: UserDefaults = .standard,
        session: URLSession = .shared
    ) {
        self.currentVersionString = currentVersion
        self.defaults = defaults
        self.session = session

        if defaults.object(forKey: DefaultsKey.automaticChecks) == nil {
            self.automaticChecksEnabled = true
        } else {
            self.automaticChecksEnabled = defaults.bool(forKey: DefaultsKey.automaticChecks)
        }

        let storedInterval = defaults.integer(forKey: DefaultsKey.checkIntervalHours)
        self.checkIntervalHours = storedInterval > 0 ? storedInterval : 24
        self.includePrereleases = defaults.bool(forKey: DefaultsKey.includePrereleases)
        self.skippedVersion = defaults.string(forKey: DefaultsKey.skippedVersion)
        self.lastCheckedAt = defaults.object(forKey: DefaultsKey.lastCheckedAt) as? Date
    }

    public var currentSemanticVersion: SemanticVersion {
        SemanticVersion(parsing: currentVersionString) ?? SemanticVersion(major: 1, minor: 0, patch: 0)
    }

    public var hasUnignoredUpdate: Bool {
        guard case .updateAvailable(let release) = state else { return false }
        return skippedVersion != release.tagName
    }

    public var availableRelease: GitHubRelease? {
        state.availableRelease
    }

    // MARK: - Automatic Background Checks

    public func startBackgroundChecks() {
        isBackgroundLoopActive = true
        rescheduleBackgroundChecksIfActive()
    }

    public func stopBackgroundChecks() {
        isBackgroundLoopActive = false
        backgroundTask?.cancel()
        backgroundTask = nil
    }

    private func rescheduleBackgroundChecksIfActive() {
        backgroundTask?.cancel()
        backgroundTask = nil

        guard isBackgroundLoopActive, automaticChecksEnabled else { return }

        backgroundTask = Task { [weak self] in
            // Wait briefly after app launch so startup stays instant and quiet
            try? await Task.sleep(nanoseconds: 8_000_000_000)

            while !Task.isCancelled {
                guard let self else { return }
                let intervalSeconds = TimeInterval(self.checkIntervalHours * 3600)
                let shouldCheckNow: Bool
                if let last = self.lastCheckedAt {
                    shouldCheckNow = Date().timeIntervalSince(last) >= intervalSeconds
                } else {
                    shouldCheckNow = true
                }

                if shouldCheckNow && !self.state.isBusy {
                    _ = await self.checkForUpdates(userInitiated: false)
                }

                let sleepInterval = max(300.0, min(intervalSeconds, 3600.0 * 6))
                try? await Task.sleep(nanoseconds: UInt64(sleepInterval * 1_000_000_000))
            }
        }
    }

    // MARK: - Check GitHub Releases

    @discardableResult
    public func checkForUpdates(userInitiated: Bool = true) async -> UpdateState {
        if state.isBusy {
            return state
        }

        state = .checking

        do {
            let release = try await fetchLatestRelease(includePrereleases: includePrereleases)
            let now = Date()
            lastCheckedAt = now
            defaults.set(now, forKey: DefaultsKey.lastCheckedAt)
            latestKnownRelease = release

            if let remoteVersion = release.semanticVersion, remoteVersion > currentSemanticVersion {
                if !userInitiated && skippedVersion == release.tagName {
                    state = .upToDate(checkedAt: now)
                } else {
                    if userInitiated && skippedVersion == release.tagName {
                        skippedVersion = nil
                    }
                    state = .updateAvailable(release)
                }
            } else {
                state = .upToDate(checkedAt: now)
            }
        } catch {
            if userInitiated {
                state = .failed(message: error.localizedDescription)
            } else {
                // Keep quiet on passive background errors if offline
                if let last = lastCheckedAt {
                    state = .upToDate(checkedAt: last)
                } else {
                    state = .idle
                }
            }
        }

        return state
    }

    public func skipVersion(_ tagName: String) {
        skippedVersion = tagName
        if case .updateAvailable(let rel) = state, rel.tagName == tagName {
            state = .upToDate(checkedAt: lastCheckedAt ?? Date())
        }
    }

    public func clearSkippedVersion() {
        skippedVersion = nil
    }

    // MARK: - GitHub API Fetching

    public func fetchLatestRelease(includePrereleases: Bool) async throws -> GitHubRelease {
        let url = includePrereleases ? NudgeVersion.allReleasesAPIURL : NudgeVersion.latestReleaseAPIURL
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Nudge/\(currentVersionString) (macOS)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UpdateError.httpError(statusCode: 0, message: "Invalid network response.")
        }

        if http.statusCode == 403,
           http.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0" {
            throw UpdateError.rateLimited
        }

        if http.statusCode == 404 {
            throw UpdateError.noReleasesFound
        }

        guard (200...299).contains(http.statusCode) else {
            let bodySnippet = String(data: data.prefix(200), encoding: .utf8) ?? "Request failed"
            throw UpdateError.httpError(statusCode: http.statusCode, message: bodySnippet)
        }

        let decoder = Self.makeGitHubDecoder()

        if includePrereleases {
            let releases = try decoder.decode([GitHubRelease].self, from: data)
            let eligible = releases.filter { !$0.draft && $0.semanticVersion != nil }
            guard let best = eligible.max(by: { ($0.semanticVersion!) < ($1.semanticVersion!) }) else {
                throw UpdateError.noReleasesFound
            }
            return best
        } else {
            let release = try decoder.decode(GitHubRelease.self, from: data)
            guard !release.draft else {
                throw UpdateError.noReleasesFound
            }
            return release
        }
    }

    nonisolated public static func makeGitHubDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let str = try container.decode(String.self)
            let isoWithFraction = ISO8601DateFormatter()
            isoWithFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = isoWithFraction.date(from: str) {
                return date
            }
            let isoPlain = ISO8601DateFormatter()
            isoPlain.formatOptions = [.withInternetDateTime]
            if let date = isoPlain.date(from: str) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO8601 date: \(str)"
            )
        }
        return decoder
    }

    // MARK: - Download, Verify & Install

    public func downloadAndInstallUpdate(_ explicitRelease: GitHubRelease? = nil) async {
        guard let release = explicitRelease ?? state.availableRelease ?? latestKnownRelease else {
            state = .failed(message: "No release selected to install.")
            return
        }

        let arch = NudgeVersion.currentArchitecture
        guard let asset = release.preferredAsset(forArchitecture: arch) else {
            state = .failed(message: UpdateError.noCompatibleAsset(arch: arch).localizedDescription)
            return
        }

        state = .downloading(release: release, progress: 0, receivedBytes: 0, totalBytes: asset.size)

        let stagingRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("nudge-update-\(UUID().uuidString)", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
            let downloadedFile = stagingRoot.appendingPathComponent(asset.name)

            try await downloadAsset(asset, to: downloadedFile, release: release)

            // Verify SHA-256 against SHA256SUMS.txt if present on the release
            state = .verifying(release: release)
            if let checksumAsset = release.checksumAsset {
                try await verifyChecksum(
                    of: downloadedFile,
                    assetName: asset.name,
                    checksumAsset: checksumAsset
                )
            }

            // If we're not running inside a writable .app bundle (e.g. swift run or read-only directory),
            // copy the verified installer to ~/Downloads so the user can open it cleanly.
            guard let targetBundleURL = currentWritableAppBundleURL() else {
                let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                    ?? FileManager.default.temporaryDirectory
                let destURL = downloadsDir.appendingPathComponent(asset.name)
                if FileManager.default.fileExists(atPath: destURL.path) {
                    try? FileManager.default.removeItem(at: destURL)
                }
                try FileManager.default.copyItem(at: downloadedFile, to: destURL)
                try? FileManager.default.removeItem(at: stagingRoot)
                state = .downloadedInstaller(release: release, fileURL: destURL)
                return
            }

            state = .installing(release: release)

            // Extract and validate Nudge.app inside stagingRoot
            let extractedApp = try await extractAppBundle(from: downloadedFile, in: stagingRoot)
            try validateExtractedAppBundle(at: extractedApp)

            // Clear quarantine xattr on the staged ad-hoc signed bundle
            _ = try? await runProcess("/usr/bin/xattr", arguments: ["-cr", extractedApp.path])

            // Launch detached atomic swap + relaunch script
            try launchSwapAndRelaunchScript(
                stagedApp: extractedApp,
                targetApp: targetBundleURL,
                stagingRoot: stagingRoot,
                currentPID: ProcessInfo.processInfo.processIdentifier
            )

            state = .readyToRelaunch(release: release)

            // Trigger graceful app termination so the swap script can replace & relaunch Nudge.app
            if let terminator = onRequestAppTermination {
                terminator()
            }
        } catch {
            try? FileManager.default.removeItem(at: stagingRoot)
            state = .failed(message: error.localizedDescription)
        }
    }

    private func downloadAsset(
        _ asset: GitHubReleaseAsset,
        to destination: URL,
        release: GitHubRelease
    ) async throws {
        var request = URLRequest(url: asset.browserDownloadURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 300)
        request.setValue("Nudge/\(currentVersionString) (macOS)", forHTTPHeaderField: "User-Agent")

        let (asyncBytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw UpdateError.httpError(statusCode: code, message: "Failed to download \(asset.name).")
        }

        let expectedBytes = http.expectedContentLength > 0 ? http.expectedContentLength : asset.size
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }

        var buffer = Data()
        buffer.reserveCapacity(65_536)
        var received: Int64 = 0
        var lastReportedBytes: Int64 = 0

        for try await byte in asyncBytes {
            buffer.append(byte)
            received += 1

            if buffer.count >= 65_536 {
                try handle.write(contentsOf: buffer)
                buffer.removeAll(keepingCapacity: true)

                if received - lastReportedBytes >= 65_536 || received == expectedBytes {
                    lastReportedBytes = received
                    let progress = expectedBytes > 0 ? min(1.0, Double(received) / Double(expectedBytes)) : 0
                    state = .downloading(
                        release: release,
                        progress: progress,
                        receivedBytes: received,
                        totalBytes: expectedBytes
                    )
                }
            }
        }

        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
        }

        state = .downloading(
            release: release,
            progress: 1.0,
            receivedBytes: received,
            totalBytes: max(expectedBytes, received)
        )
    }

    private func verifyChecksum(
        of fileURL: URL,
        assetName: String,
        checksumAsset: GitHubReleaseAsset
    ) async throws {
        var request = URLRequest(url: checksumAsset.browserDownloadURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("Nudge/\(currentVersionString) (macOS)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let text = String(data: data, encoding: .utf8) else {
            return
        }

        let checksums = ChecksumVerifier.parseChecksums(text)
        guard let expected = checksums[assetName] else {
            return
        }

        let actual = try await Task.detached(priority: .userInitiated) {
            try ChecksumVerifier.sha256Hex(forFileAt: fileURL)
        }.value

        if actual.lowercased() != expected.lowercased() {
            throw UpdateError.checksumMismatch(expected: expected, actual: actual)
        }
    }

    private func currentWritableAppBundleURL() -> URL? {
        let bundleURL = Bundle.main.bundleURL
        guard bundleURL.pathExtension.lowercased() == "app" else {
            return nil
        }
        let parentDir = bundleURL.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parentDir.path),
              FileManager.default.isWritableFile(atPath: bundleURL.path) else {
            return nil
        }
        return bundleURL
    }

    private func extractAppBundle(from archiveURL: URL, in stagingRoot: URL) async throws -> URL {
        let ext = archiveURL.pathExtension.lowercased()
        let extractDir = stagingRoot.appendingPathComponent("extracted", isDirectory: true)
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)

        if ext == "zip" {
            let output = try await runProcess("/usr/bin/ditto", arguments: ["-x", "-k", archiveURL.path, extractDir.path])
            guard output.exitCode == 0 else {
                throw UpdateError.extractionFailed(output.stderr.isEmpty ? "ditto exited \(output.exitCode)" : output.stderr)
            }
            if let found = findAppBundle(in: extractDir) {
                return found
            }
            throw UpdateError.extractionFailed("Nudge.app was not found inside the downloaded archive.")
        } else if ext == "dmg" {
            let mountDir = stagingRoot.appendingPathComponent("dmg-mount", isDirectory: true)
            try FileManager.default.createDirectory(at: mountDir, withIntermediateDirectories: true)

            let attach = try await runProcess(
                "/usr/bin/hdiutil",
                arguments: ["attach", "-nobrowse", "-noautoopen", "-readonly", "-mountpoint", mountDir.path, archiveURL.path]
            )
            guard attach.exitCode == 0 else {
                throw UpdateError.extractionFailed(attach.stderr.isEmpty ? "hdiutil attach failed" : attach.stderr)
            }
            defer {
                let detach = Process()
                detach.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
                detach.arguments = ["detach", mountDir.path, "-quiet", "-force"]
                try? detach.run()
                detach.waitUntilExit()
            }

            guard let mountedApp = findAppBundle(in: mountDir) else {
                throw UpdateError.extractionFailed("Nudge.app was not found inside the mounted DMG.")
            }

            let copiedApp = extractDir.appendingPathComponent(mountedApp.lastPathComponent)
            let copyRes = try await runProcess("/usr/bin/ditto", arguments: [mountedApp.path, copiedApp.path])
            guard copyRes.exitCode == 0 else {
                throw UpdateError.extractionFailed(copyRes.stderr)
            }
            return copiedApp
        } else {
            throw UpdateError.extractionFailed("Unsupported archive format: .\(ext)")
        }
    }

    private func findAppBundle(in directory: URL) -> URL? {
        let fm = FileManager.default
        if let direct = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            if let exact = direct.first(where: { $0.lastPathComponent == "Nudge.app" }) {
                return exact
            }
            if let anyApp = direct.first(where: { $0.pathExtension.lowercased() == "app" }) {
                return anyApp
            }
        }
        return nil
    }

    private func validateExtractedAppBundle(at appURL: URL) throws {
        let infoPlistURL = appURL.appendingPathComponent("Contents/Info.plist")
        let executableURL = appURL.appendingPathComponent("Contents/MacOS/Nudge")

        guard FileManager.default.fileExists(atPath: infoPlistURL.path) else {
            throw UpdateError.invalidAppBundle("Missing Contents/Info.plist.")
        }
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw UpdateError.invalidAppBundle("Missing executable Contents/MacOS/Nudge.")
        }
        guard let dict = NSDictionary(contentsOf: infoPlistURL),
              let bundleID = dict["CFBundleIdentifier"] as? String,
              bundleID == NudgeVersion.bundleIdentifier else {
            throw UpdateError.invalidAppBundle("Bundle identifier does not match \(NudgeVersion.bundleIdentifier).")
        }
    }

    private func launchSwapAndRelaunchScript(
        stagedApp: URL,
        targetApp: URL,
        stagingRoot: URL,
        currentPID: Int32
    ) throws {
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("nudge-apply-update-\(UUID().uuidString).sh")

        let script = """
        #!/bin/bash
        set -euo pipefail
        OLD_PID="$1"
        STAGED_APP="$2"
        TARGET_APP="$3"
        STAGING_ROOT="$4"
        BACKUP_APP="${TARGET_APP}.nudge-backup.$$"

        # Wait up to 15 seconds for the running Nudge instance to exit cleanly
        for _ in $(seq 1 60); do
            if ! kill -0 "$OLD_PID" 2>/dev/null; then
                break
            fi
            sleep 0.25
        done

        # Atomic swap with rollback on failure
        if [ -d "$TARGET_APP" ]; then
            mv "$TARGET_APP" "$BACKUP_APP"
        fi

        if mv "$STAGED_APP" "$TARGET_APP"; then
            /usr/bin/xattr -cr "$TARGET_APP" 2>/dev/null || true
            rm -rf "$BACKUP_APP" "$STAGING_ROOT" "$0" 2>/dev/null || true
            /usr/bin/open -n "$TARGET_APP" >/dev/null 2>&1 || /usr/bin/open "$TARGET_APP" >/dev/null 2>&1 || true
        else
            if [ -d "$BACKUP_APP" ]; then
                mv "$BACKUP_APP" "$TARGET_APP" 2>/dev/null || true
            fi
            rm -rf "$STAGING_ROOT" "$0" 2>/dev/null || true
            exit 1
        fi
        """

        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/bash")
        proc.arguments = [scriptURL.path, String(currentPID), stagedApp.path, targetApp.path, stagingRoot.path]
        proc.standardInput = FileHandle.nullDevice
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice

        do {
            try proc.run()
        } catch {
            throw UpdateError.installScriptFailed(error.localizedDescription)
        }
    }

    private struct ProcessOutput: Sendable {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    private func runProcess(_ path: String, arguments: [String]) async throws -> ProcessOutput {
        try await Task.detached(priority: .userInitiated) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: path)
            proc.arguments = arguments

            let outPipe = Pipe()
            let errPipe = Pipe()
            proc.standardOutput = outPipe
            proc.standardError = errPipe

            try proc.run()
            proc.waitUntilExit()

            let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()

            return ProcessOutput(
                exitCode: proc.terminationStatus,
                stdout: String(data: outData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                stderr: String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            )
        }.value
    }
}
