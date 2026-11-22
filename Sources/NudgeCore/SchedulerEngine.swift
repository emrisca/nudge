import Foundation

/// Cron-like recurring scheduler for `ScheduledTask` items with JSON persistence
/// and "Catch Up on Missed Tasks" detection across sleep/wake and app relaunch.
public final class SchedulerEngine: @unchecked Sendable {
    public static var defaultStorageURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return appSupport
            .appendingPathComponent("Nudge", isDirectory: true)
            .appendingPathComponent("schedules.json", isDirectory: false)
    }

    private let lock = NSLock()
    private let storageURL: URL
    private let calendar: Calendar
    private var _tasks: [ScheduledTask] = []
    private var lastEvaluationDate: Date?

    public init(storageURL: URL? = nil, calendar: Calendar = .current) {
        self.storageURL = storageURL ?? Self.defaultStorageURL
        self.calendar = calendar
        self._tasks = Self.loadFromDisk(url: self.storageURL)
    }

    public var tasks: [ScheduledTask] {
        lock.lock()
        defer { lock.unlock() }
        return _tasks
    }

    // MARK: - CRUD

    public func addTask(_ task: ScheduledTask) {
        lock.lock()
        var sanitized = task
        sanitized.hour = max(0, min(23, task.hour))
        sanitized.minute = max(0, min(59, task.minute))
        sanitized.weekdays = Array(Set(task.weekdays.filter { (1...7).contains($0) })).sorted()
        _tasks.append(sanitized)
        let snapshot = _tasks
        lock.unlock()
        persist(snapshot)
    }

    public func updateTask(_ task: ScheduledTask) {
        lock.lock()
        if let idx = _tasks.firstIndex(where: { $0.id == task.id }) {
            var sanitized = task
            sanitized.hour = max(0, min(23, task.hour))
            sanitized.minute = max(0, min(59, task.minute))
            sanitized.weekdays = Array(Set(task.weekdays.filter { (1...7).contains($0) })).sorted()
            _tasks[idx] = sanitized
        }
        let snapshot = _tasks
        lock.unlock()
        persist(snapshot)
    }

    public func removeTask(id: UUID) {
        lock.lock()
        _tasks.removeAll { $0.id == id }
        let snapshot = _tasks
        lock.unlock()
        persist(snapshot)
    }

    // MARK: - Evaluation & Catch-Up

    /// Evaluates tasks due at `now`. When `includeMissed` is true (e.g. on wake or launch),
    /// any enabled task with `catchUpIfMissed == true` whose most recent scheduled slot occurred
    /// after `lastExecutedAt` (within the past 24 hours) is executed in chronological order.
    @discardableResult
    public func evaluateDueTasks(
        now: Date = Date(),
        includeMissed: Bool = false,
        catchUpWindowSeconds: TimeInterval = 86_400,
        executor: (ScheduledTask) -> Void
    ) -> [ScheduledTask] {
        lock.lock()
        let currentTasks = _tasks
        let prevEval = lastEvaluationDate
        lastEvaluationDate = now
        lock.unlock()

        var dueWithSlot: [(task: ScheduledTask, slot: Date)] = []

        for task in currentTasks where task.isEnabled {
            guard let slot = mostRecentScheduledDate(for: task, atOrBefore: now) else {
                continue
            }

            // Already executed for this slot?
            if let lastRun = task.lastExecutedAt, lastRun >= slot {
                continue
            }

            let age = now.timeIntervalSince(slot)
            let isCurrentlyDue = (age >= 0 && age < 60.0)

            let isMissedCatchUp: Bool
            if includeMissed && task.catchUpIfMissed && age >= 60.0 && age <= catchUpWindowSeconds {
                if let lastRun = task.lastExecutedAt {
                    isMissedCatchUp = slot > lastRun
                } else if let prevEval {
                    isMissedCatchUp = slot > prevEval
                } else {
                    // App launched or explicit catch-up run on a persisted task with no prior run recorded
                    isMissedCatchUp = true
                }
            } else {
                isMissedCatchUp = false
            }

            if isCurrentlyDue || isMissedCatchUp {
                dueWithSlot.append((task, slot))
            }
        }

        // Execute oldest missed slot first so later schedules win naturally
        dueWithSlot.sort { $0.slot < $1.slot }

        var executed: [ScheduledTask] = []
        for entry in dueWithSlot {
            executor(entry.task)
            executed.append(entry.task)
        }

        if !executed.isEmpty {
            let executedIDs = Set(executed.map(\.id))
            lock.lock()
            for i in _tasks.indices where executedIDs.contains(_tasks[i].id) {
                _tasks[i].lastExecutedAt = now
            }
            let updatedSnapshot = _tasks
            lock.unlock()
            persist(updatedSnapshot)
        }

        return executed
    }

    /// Computes the most recent scheduled firing timestamp at or before `date`.
    public func mostRecentScheduledDate(for task: ScheduledTask, atOrBefore date: Date) -> Date? {
        let validWeekdays = Set(task.weekdays.filter { (1...7).contains($0) })

        for dayOffset in 0...7 {
            guard let candidateDay = calendar.date(byAdding: .day, value: -dayOffset, to: date) else {
                continue
            }
            let weekday = calendar.component(.weekday, from: candidateDay)
            if !validWeekdays.isEmpty && !validWeekdays.contains(weekday) {
                continue
            }
            var comps = calendar.dateComponents([.year, .month, .day], from: candidateDay)
            comps.hour = task.hour
            comps.minute = task.minute
            comps.second = 0

            guard let candidateDate = calendar.date(from: comps) else { continue }
            if candidateDate <= date {
                return candidateDate
            }
        }
        return nil
    }

    /// Computes the next upcoming scheduled firing timestamp after `date`.
    public func nextScheduledDate(for task: ScheduledTask, after date: Date = Date()) -> Date? {
        let validWeekdays = Set(task.weekdays.filter { (1...7).contains($0) })

        for dayOffset in 0...8 {
            guard let candidateDay = calendar.date(byAdding: .day, value: dayOffset, to: date) else {
                continue
            }
            let weekday = calendar.component(.weekday, from: candidateDay)
            if !validWeekdays.isEmpty && !validWeekdays.contains(weekday) {
                continue
            }
            var comps = calendar.dateComponents([.year, .month, .day], from: candidateDay)
            comps.hour = task.hour
            comps.minute = task.minute
            comps.second = 0

            guard let candidateDate = calendar.date(from: comps) else { continue }
            if candidateDate > date {
                return candidateDate
            }
        }
        return nil
    }

    // MARK: - Persistence

    private func persist(_ items: [ScheduledTask]) {
        do {
            let dir = storageURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(items)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            // Non-fatal persistence failure; keep in-memory schedule operational.
        }
    }

    private static func loadFromDisk(url: URL) -> [ScheduledTask] {
        guard let data = try? Data(contentsOf: url) else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([ScheduledTask].self, from: data)) ?? []
    }
}
