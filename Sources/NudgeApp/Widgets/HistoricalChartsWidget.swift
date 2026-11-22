import SwiftUI
import Charts
import NudgeCore

public enum HistoricalChartTab: String, CaseIterable, Identifiable {
    case charge = "Charge %"
    case temperature = "Temp °C"
    case power = "Power W"

    public var id: String { rawValue }
}

public struct HistoricalChartsWidget: View {
    @Environment(\.nudgePalette) private var palette
    @ObservedObject var manager: BatteryManager

    @State private var selectedTab: HistoricalChartTab = .charge
    var chartHeight: CGFloat = 155

    public init(manager: BatteryManager, chartHeight: CGFloat = 155) {
        self.manager = manager
        self.chartHeight = chartHeight
    }

    private var points: [BatteryHistoryPoint] {
        if manager.history.isEmpty {
            let s = manager.latestSnapshot
            return [
                BatteryHistoryPoint(
                    timestamp: s.timestamp.addingTimeInterval(-60),
                    displayPercentage: s.displayPercentage,
                    hardwarePercentage: s.rawHardwarePercentage,
                    temperatureCelsius: s.temperatureCelsius,
                    chargerWatts: s.powerFlow.chargerInputWatts,
                    batteryWatts: s.powerFlow.batteryWatts,
                    systemWatts: s.powerFlow.systemLoadWatts
                ),
                BatteryHistoryPoint(
                    timestamp: s.timestamp,
                    displayPercentage: s.displayPercentage,
                    hardwarePercentage: s.rawHardwarePercentage,
                    temperatureCelsius: s.temperatureCelsius,
                    chargerWatts: s.powerFlow.chargerInputWatts,
                    batteryWatts: s.powerFlow.batteryWatts,
                    systemWatts: s.powerFlow.systemLoadWatts
                )
            ]
        }
        return manager.history
    }

    public var body: some View {
        NudgeCard(
            title: "Historical Telemetry",
            subtitle: "\(manager.history.count) samples captured",
            symbol: "chart.xyaxis.line",
            headerTrailing: {
                tabSwitcher
            }
        ) {
            VStack(spacing: 10) {
                Group {
                    switch selectedTab {
                    case .charge:
                        chargeChart
                    case .temperature:
                        temperatureChart
                    case .power:
                        powerChart
                    }
                }
                .frame(height: chartHeight)

                summaryStrip
            }
        }
    }

    private var tabSwitcher: some View {
        HStack(spacing: 3) {
            ForEach(HistoricalChartTab.allCases) { tab in
                let isSelected = selectedTab == tab
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        selectedTab = tab
                    }
                } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 10.5, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? palette.primaryForeground : palette.mutedForeground)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(isSelected ? palette.primary : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2.5)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(palette.muted)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(palette.border, lineWidth: 1)
        )
    }

    private var chargeChart: some View {
        Chart {
            ForEach(points) { point in
                AreaMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Charge", point.displayPercentage)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(
                    LinearGradient(
                        colors: [palette.chart1.opacity(0.45), palette.chart1.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Charge", point.displayPercentage)
                )
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round))
                .foregroundStyle(palette.chart1)
            }

            RuleMark(y: .value("Charge Limit", manager.config.chargeLimit))
                .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [4, 4]))
                .foregroundStyle(palette.chart3)
                .annotation(position: .top, alignment: .trailing) {
                    Text("Limit \(manager.config.chargeLimit)%")
                        .font(.system(size: 9.5, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(palette.accentForeground)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(palette.accent)
                        )
                }
        }
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 25, 50, 75, 100]) { val in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6))
                    .foregroundStyle(palette.border)
                AxisValueLabel {
                    if let intVal = val.as(Int.self) {
                        Text("\(intVal)%")
                            .font(.system(size: 9.5))
                            .monospacedDigit()
                            .foregroundStyle(palette.mutedForeground)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: .dateTime.hour().minute())
                    .font(.system(size: 9.5))
                    .foregroundStyle(palette.mutedForeground)
            }
        }
    }

    private var temperatureChart: some View {
        let maxTemp = max(45.0, (points.map(\.temperatureCelsius).max() ?? 35.0) + 5.0)
        let minTemp = max(15.0, (points.map(\.temperatureCelsius).min() ?? 25.0) - 5.0)

        return Chart {
            ForEach(points) { point in
                AreaMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Temp", point.temperatureCelsius)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(
                    LinearGradient(
                        colors: [palette.chart3.opacity(0.38), palette.chart3.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Temp", point.temperatureCelsius)
                )
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round))
                .foregroundStyle(palette.chart3)
            }

            RuleMark(y: .value("Heat Limit", manager.config.heatThresholdCelsius))
                .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [4, 4]))
                .foregroundStyle(palette.destructive)
                .annotation(position: .top, alignment: .trailing) {
                    Text("Heat \(Int(manager.config.heatThresholdCelsius))°C")
                        .font(.system(size: 9.5, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(palette.destructiveForeground)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(palette.destructive)
                        )
                }
        }
        .chartYScale(domain: minTemp...maxTemp)
        .chartYAxis {
            AxisMarks(position: .leading) { val in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6))
                    .foregroundStyle(palette.border)
                AxisValueLabel {
                    if let d = val.as(Double.self) {
                        Text("\(Int(round(d)))°")
                            .font(.system(size: 9.5))
                            .monospacedDigit()
                            .foregroundStyle(palette.mutedForeground)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: .dateTime.hour().minute())
                    .font(.system(size: 9.5))
                    .foregroundStyle(palette.mutedForeground)
            }
        }
    }

    private var powerChart: some View {
        Chart {
            RuleMark(y: .value("Zero", 0))
                .lineStyle(StrokeStyle(lineWidth: 0.8))
                .foregroundStyle(palette.border)

            ForEach(points) { point in
                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Watts", point.chargerWatts),
                    series: .value("Series", "Charger")
                )
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .foregroundStyle(palette.chart1)

                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Watts", point.systemWatts),
                    series: .value("Series", "System")
                )
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .foregroundStyle(palette.isDark ? palette.chart2 : Color(hex: 0x3B82F6))

                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Watts", point.batteryWatts),
                    series: .value("Series", "Battery")
                )
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 1.8, dash: [3, 2]))
                .foregroundStyle(palette.chart3)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { val in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6))
                    .foregroundStyle(palette.border)
                AxisValueLabel {
                    if let d = val.as(Double.self) {
                        Text("\(Int(round(d)))W")
                            .font(.system(size: 9.5))
                            .monospacedDigit()
                            .foregroundStyle(palette.mutedForeground)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: .dateTime.hour().minute())
                    .font(.system(size: 9.5))
                    .foregroundStyle(palette.mutedForeground)
            }
        }
    }

    private var summaryStrip: some View {
        HStack(spacing: 8) {
            switch selectedTab {
            case .charge:
                let vals = points.map(\.displayPercentage)
                statChip(label: "Min", value: "\(vals.min() ?? 0)%")
                statChip(label: "Avg", value: "\(vals.isEmpty ? 0 : vals.reduce(0, +) / vals.count)%")
                statChip(label: "Now", value: "\(manager.latestSnapshot.displayPercentage)%")
            case .temperature:
                let vals = points.map(\.temperatureCelsius)
                let avg = vals.isEmpty ? 0 : vals.reduce(0, +) / Double(vals.count)
                statChip(label: "Min", value: String(format: "%.1f°C", vals.min() ?? 0))
                statChip(label: "Avg", value: String(format: "%.1f°C", avg))
                statChip(label: "Peak", value: String(format: "%.1f°C", vals.max() ?? 0))
            case .power:
                legendDot(label: "Charger", value: String(format: "%.1fW", manager.latestSnapshot.powerFlow.chargerInputWatts), color: palette.chart1)
                legendDot(label: "System", value: String(format: "%.1fW", manager.latestSnapshot.powerFlow.systemLoadWatts), color: palette.isDark ? palette.chart2 : Color(hex: 0x3B82F6))
                legendDot(label: "Battery", value: String(format: "%+.1fW", manager.latestSnapshot.powerFlow.batteryWatts), color: palette.chart3)
            }
        }
    }

    private func statChip(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(palette.mutedForeground)
            Spacer()
            Text(value)
                .nudgeMetricFont(size: 11.5, weight: .semibold)
                .foregroundStyle(palette.foreground)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(palette.muted)
        )
    }

    private func legendDot(label: String, value: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(palette.mutedForeground)
            Spacer(minLength: 2)
            Text(value)
                .nudgeMetricFont(size: 10.5, weight: .semibold)
                .foregroundStyle(palette.foreground)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(palette.muted)
        )
    }
}
