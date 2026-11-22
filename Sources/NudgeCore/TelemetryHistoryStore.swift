import Foundation

/// Lightweight ring-buffer and JSON persistence store for battery telemetry history (up to 720 samples / 24h)
/// powering Swift Charts visualizations.
public final class TelemetryHistoryStore: @unchecked Sendable {
    public static var defaultStorageURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return appSupport
            .appendingPathComponent("Nudge", isDirectory: true)
            .appendingPathComponent("history.json", isDirectory: false)
    }

    public let maxPoints: Int
    private let storageURL: URL
    private let lock = NSLock()
    private var _points: [BatteryHistoryPoint] = []
    private var lastDiskFlush: Date = .distantPast

    public init(maxPoints: Int = 720, storageURL: URL? = nil) {
        self.maxPoints = max(1, maxPoints)
        self.storageURL = storageURL ?? Self.defaultStorageURL
        self._points = Self.loadFromDisk(url: self.storageURL, maxPoints: self.maxPoints)
    }

    public var points: [BatteryHistoryPoint] {
        lock.lock()
        defer { lock.unlock() }
        return _points
    }

    /// Seeds the history buffer with an initial live sample if empty (first run).
    @discardableResult
    public func seedIfEmpty(with snapshot: BatterySnapshot) -> [BatteryHistoryPoint] {
        lock.lock()
        guard _points.isEmpty else {
            let existing = _points
            lock.unlock()
            return existing
        }
        let point = Self.makePoint(from: snapshot)
        _points.append(point)
        let snapshotCopy = _points
        lastDiskFlush = snapshot.timestamp
        lock.unlock()

        persist(snapshotCopy)
        return snapshotCopy
    }

    /// Records a telemetry snapshot if empty, if `minSampleInterval` has elapsed, or if percentage/temp shifted noticeably.
    @discardableResult
    public func record(
        snapshot: BatterySnapshot,
        minSampleInterval: TimeInterval = 120.0,
        force: Bool = false
    ) -> [BatteryHistoryPoint] {
        lock.lock()

        var shouldRecord = force || _points.isEmpty
        if !shouldRecord, let last = _points.last {
            let elapsed = snapshot.timestamp.timeIntervalSince(last.timestamp)
            let pctChanged = abs(snapshot.displayPercentage - last.displayPercentage) >= 1
            let tempChanged = abs(snapshot.temperatureCelsius - last.temperatureCelsius) >= 1.5
            let powerChanged = abs(snapshot.powerFlow.chargerInputWatts - last.chargerWatts) >= 5.0
            shouldRecord = elapsed >= minSampleInterval || pctChanged || tempChanged || powerChanged
        }

        guard shouldRecord else {
            let existing = _points
            lock.unlock()
            return existing
        }

        let point = Self.makePoint(from: snapshot)
        _points.append(point)
        if _points.count > maxPoints {
            _points.removeFirst(_points.count - maxPoints)
        }

        let shouldFlush = force || _points.count <= 2 || snapshot.timestamp.timeIntervalSince(lastDiskFlush) >= 60.0
        if shouldFlush {
            lastDiskFlush = snapshot.timestamp
        }
        let copy = _points
        lock.unlock()

        if shouldFlush {
            persist(copy)
        }
        return copy
    }

    /// Appends a pre-constructed `BatteryHistoryPoint` directly into the ring buffer.
    @discardableResult
    public func append(_ point: BatteryHistoryPoint, persistImmediately: Bool = true) -> [BatteryHistoryPoint] {
        lock.lock()
        _points.append(point)
        if _points.count > maxPoints {
            _points.removeFirst(_points.count - maxPoints)
        }
        let copy = _points
        if persistImmediately {
            lastDiskFlush = Date()
        }
        lock.unlock()

        if persistImmediately {
            persist(copy)
        }
        return copy
    }

    public func points(since cutoff: Date) -> [BatteryHistoryPoint] {
        lock.lock()
        defer { lock.unlock() }
        return _points.filter { $0.timestamp >= cutoff }
    }

    public func clear() {
        lock.lock()
        _points.removeAll()
        lastDiskFlush = Date()
        lock.unlock()
        persist([])
    }

    public func flushToDisk() {
        lock.lock()
        let copy = _points
        lastDiskFlush = Date()
        lock.unlock()
        persist(copy)
    }

    // MARK: - Helpers

    private static func makePoint(from snapshot: BatterySnapshot) -> BatteryHistoryPoint {
        BatteryHistoryPoint(
            timestamp: snapshot.timestamp,
            displayPercentage: snapshot.displayPercentage,
            hardwarePercentage: snapshot.rawHardwarePercentage,
            temperatureCelsius: snapshot.temperatureCelsius,
            chargerWatts: snapshot.powerFlow.chargerInputWatts,
            batteryWatts: snapshot.powerFlow.batteryWatts,
            systemWatts: snapshot.powerFlow.systemLoadWatts
        )
    }

    private func persist(_ items: [BatteryHistoryPoint]) {
        do {
            let dir = storageURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(items)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            // Non-fatal persistence failure; keep in-memory ring buffer active.
        }
    }

    private static func loadFromDisk(url: URL, maxPoints: Int) -> [BatteryHistoryPoint] {
        guard let data = try? Data(contentsOf: url) else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let decoded = try? decoder.decode([BatteryHistoryPoint].self, from: data) else {
            return []
        }
        if decoded.count > maxPoints {
            return Array(decoded.suffix(maxPoints))
        }
        return decoded
    }
}
