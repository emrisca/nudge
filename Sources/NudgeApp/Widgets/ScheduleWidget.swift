import SwiftUI
import NudgeCore

public struct ScheduleWidget: View {
    @Environment(\.nudgePalette) private var palette
    @ObservedObject var manager: BatteryManager

    @State private var showingAddForm: Bool = false
    @State private var newName: String = ""
    @State private var newAction: ScheduledActionType = .setChargeLimit
    @State private var newTargetValue: Int = 80
    @State private var newHour: Int = 8
    @State private var newMinute: Int = 0
    @State private var newWeekdays: Set<Int> = []
    @State private var newCatchUp: Bool = true

    private let weekdayLabels: [(Int, String)] = [
        (1, "S"), (2, "M"), (3, "T"), (4, "W"), (5, "T"), (6, "F"), (7, "S")
    ]

    public init(manager: BatteryManager) {
        self.manager = manager
    }

    public var body: some View {
        NudgeCard(
            title: "Schedule & Automations",
            subtitle: "\(manager.scheduledTasks.filter(\.isEnabled).count) active routines",
            symbol: "calendar.badge.clock",
            headerTrailing: {
                HStack(spacing: 5) {
                    Button {
                        manager.runMissedScheduledTasksIfNeeded()
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .buttonStyle(NudgeIconButtonStyle())
                    .help("Run Missed Scheduled Tasks")

                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            showingAddForm.toggle()
                        }
                    } label: {
                        Image(systemName: showingAddForm ? "xmark" : "plus")
                    }
                    .buttonStyle(NudgeIconButtonStyle(isActive: showingAddForm))
                    .help("Add Scheduled Task")
                }
            }
        ) {
            VStack(alignment: .leading, spacing: 10) {
                // Global Catch-Up Toggle
                Toggle(
                    isOn: Binding(
                        get: { manager.config.catchUpMissedTasks },
                        set: { val in manager.updateConfig { $0.catchUpMissedTasks = val } }
                    )
                ) {
                    Text("Catch Up on Missed Tasks after Wake")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(palette.foreground)
                }
                .toggleStyle(NudgeSwitchToggleStyle())

                // Inline Add Form (popover-safe, avoids sheet dismissal bugs in MenuBarExtra)
                if showingAddForm {
                    addTaskForm
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if manager.scheduledTasks.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "calendar")
                            .foregroundStyle(palette.mutedForeground)
                        Text("No scheduled battery routines yet.")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(palette.mutedForeground)
                        Spacer()
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: NudgeMetrics.controlRadius, style: .continuous)
                            .fill(palette.muted.opacity(0.65))
                    )
                } else {
                    VStack(spacing: 6) {
                        ForEach(manager.scheduledTasks) { task in
                            taskRow(task)
                        }
                    }
                }
            }
        }
    }

    private func taskRow(_ task: ScheduledTask) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(task.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(task.isEnabled ? palette.foreground : palette.mutedForeground)
                        .lineLimit(1)

                    if let target = task.targetValue, task.action == .setChargeLimit {
                        NudgeTagPill("\(target)%", style: .accent)
                    }
                }

                HStack(spacing: 5) {
                    Text(String(format: "%02d:%02d", task.hour, task.minute))
                        .nudgeMetricFont(size: 10.5, weight: .semibold)
                        .foregroundStyle(palette.foreground)
                    Text("·")
                        .foregroundStyle(palette.mutedForeground)
                    Text(weekdaysSummary(task.weekdays))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(palette.mutedForeground)
                    Text("·")
                        .foregroundStyle(palette.mutedForeground)
                    Text(task.action.rawValue)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(palette.mutedForeground)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            Toggle(
                "",
                isOn: Binding(
                    get: { task.isEnabled },
                    set: { enabled in
                        var updated = task
                        updated.isEnabled = enabled
                        manager.updateScheduledTask(updated)
                    }
                )
            )
            .labelsHidden()
            .toggleStyle(NudgeSwitchToggleStyle())

            Button {
                manager.removeScheduledTask(id: task.id)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(palette.mutedForeground)
            }
            .buttonStyle(.plain)
            .help("Delete Task")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: NudgeMetrics.controlRadius, style: .continuous)
                .fill(palette.muted.opacity(0.60))
        )
        .overlay(
            RoundedRectangle(cornerRadius: NudgeMetrics.controlRadius, style: .continuous)
                .strokeBorder(palette.border.opacity(0.70), lineWidth: 1)
        )
    }

    private var addTaskForm: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("New Scheduled Routine")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(palette.foreground)

            TextField("Task Name (e.g., Morning Top Up)", text: $newName)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: NudgeMetrics.controlRadius, style: .continuous)
                        .fill(palette.input)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: NudgeMetrics.controlRadius, style: .continuous)
                        .strokeBorder(palette.border, lineWidth: 1)
                )

            HStack(spacing: 8) {
                Picker("Action", selection: $newAction) {
                    ForEach(ScheduledActionType.allCases) { act in
                        Text(act.rawValue).tag(act)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity)

                if newAction == .setChargeLimit {
                    Stepper("\(newTargetValue)%", value: $newTargetValue, in: 20...100, step: 5)
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                        .fixedSize()
                }
            }

            HStack(spacing: 10) {
                HStack(spacing: 4) {
                    Text("Time")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.mutedForeground)
                    Picker("Hour", selection: $newHour) {
                        ForEach(0..<24, id: \.self) { h in
                            Text(String(format: "%02d", h)).tag(h)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 56)
                    Text(":")
                        .font(.system(size: 11, weight: .bold))
                    Picker("Minute", selection: $newMinute) {
                        ForEach([0, 15, 30, 45], id: \.self) { m in
                            Text(String(format: "%02d", m)).tag(m)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 56)
                }

                Spacer()
            }

            // Weekday pills (empty = daily)
            HStack(spacing: 4) {
                ForEach(weekdayLabels, id: \.0) { dayNum, short in
                    let active = newWeekdays.contains(dayNum)
                    Button {
                        if active {
                            newWeekdays.remove(dayNum)
                        } else {
                            newWeekdays.insert(dayNum)
                        }
                    } label: {
                        Text(short)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(active ? palette.primaryForeground : palette.foreground)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(active ? palette.primary : palette.card)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(active ? palette.ring : palette.border, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            Toggle("Catch up if missed during sleep", isOn: $newCatchUp)
                .font(.system(size: 11, weight: .medium))
                .toggleStyle(NudgeSwitchToggleStyle())

            HStack {
                Button("Cancel") {
                    withAnimation { showingAddForm = false }
                }
                .buttonStyle(NudgeSecondaryButtonStyle(compact: true))

                Spacer()

                Button("Save Task") {
                    let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                    let title = trimmed.isEmpty ? newAction.rawValue : trimmed
                    let task = ScheduledTask(
                        name: title,
                        action: newAction,
                        targetValue: newAction == .setChargeLimit ? newTargetValue : nil,
                        hour: newHour,
                        minute: newMinute,
                        weekdays: Array(newWeekdays).sorted(),
                        isEnabled: true,
                        catchUpIfMissed: newCatchUp
                    )
                    manager.addScheduledTask(task)
                    newName = ""
                    newWeekdays = []
                    withAnimation { showingAddForm = false }
                }
                .buttonStyle(NudgePrimaryButtonStyle(compact: true))
            }
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: NudgeMetrics.controlRadius, style: .continuous)
                .fill(palette.muted.opacity(0.75))
        )
        .overlay(
            RoundedRectangle(cornerRadius: NudgeMetrics.controlRadius, style: .continuous)
                .strokeBorder(palette.ring.opacity(0.75), lineWidth: 1)
        )
    }

    private func weekdaysSummary(_ days: [Int]) -> String {
        if days.isEmpty || days.count == 7 { return "Daily" }
        let sorted = days.sorted()
        if sorted == [2, 3, 4, 5, 6] { return "Weekdays" }
        if sorted == [1, 7] { return "Weekends" }
        let names = [1: "Sun", 2: "Mon", 3: "Tue", 4: "Wed", 5: "Thu", 6: "Fri", 7: "Sat"]
        return sorted.compactMap { names[$0] }.joined(separator: ", ")
    }
}
