import SwiftUI

/// Interactive neon-green charge limit slider with visual Sailing Mode deadband and live battery marker.
public struct ChargeLimitSlider: View {
    @Environment(\.nudgePalette) private var palette

    @Binding var value: Double
    let range: ClosedRange<Double>
    let sailingEnabled: Bool
    let sailingDeadband: Int
    let currentBatteryPercent: Int
    let onCommit: (Int) -> Void

    @State private var isDragging: Bool = false

    public init(
        value: Binding<Double>,
        range: ClosedRange<Double> = 20...100,
        sailingEnabled: Bool,
        sailingDeadband: Int,
        currentBatteryPercent: Int,
        onCommit: @escaping (Int) -> Void
    ) {
        self._value = value
        self.range = range
        self.sailingEnabled = sailingEnabled
        self.sailingDeadband = sailingDeadband
        self.currentBatteryPercent = currentBatteryPercent
        self.onCommit = onCommit
    }

    private func normalized(_ val: Double) -> CGFloat {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return CGFloat(min(1, max(0, (val - range.lowerBound) / span)))
    }

    public var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                let width = max(1, geo.size.width)
                let limitFraction = normalized(value)
                let limitX = width * limitFraction

                let deadbandFloor = max(range.lowerBound, value - Double(sailingDeadband))
                let deadbandStartX = width * normalized(deadbandFloor)
                let deadbandWidth = max(0, limitX - deadbandStartX)

                let batteryX = width * normalized(Double(currentBatteryPercent))

                ZStack(alignment: .leading) {
                    // Base Track
                    Capsule(style: .continuous)
                        .fill(palette.muted)
                        .frame(height: 10)
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(palette.border, lineWidth: 1)
                        )

                    // Active neon-green progress fill up to target limit
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [palette.chart3.opacity(0.85), palette.primary],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(10, limitX), height: 10)

                    // Sailing deadband visual zone
                    if sailingEnabled && deadbandWidth > 2 {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(palette.isDark ? Color.black.opacity(0.32) : Color.black.opacity(0.16))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .strokeBorder(palette.primaryForeground.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                            )
                            .frame(width: deadbandWidth, height: 10)
                            .offset(x: deadbandStartX)
                    }

                    // Current battery level tick mark
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(palette.foreground.opacity(0.7))
                        .frame(width: 2.5, height: 15)
                        .offset(x: min(width - 2.5, max(0, batteryX - 1.25)))

                    // Interactive Thumb
                    Circle()
                        .fill(palette.card)
                        .frame(width: isDragging ? 22 : 20, height: isDragging ? 22 : 20)
                        .overlay(
                            Circle()
                                .strokeBorder(palette.primary, lineWidth: 3)
                        )
                        .shadow(color: Color.black.opacity(0.18), radius: 4, y: 2)
                        .offset(x: min(width - 20, max(0, limitX - 10)))
                        .animation(.easeOut(duration: 0.1), value: isDragging)
                }
                .frame(height: 24)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            isDragging = true
                            let ratio = min(1, max(0, gesture.location.x / width))
                            let raw = range.lowerBound + Double(ratio) * (range.upperBound - range.lowerBound)
                            let stepped = round(raw)
                            value = min(range.upperBound, max(range.lowerBound, stepped))
                        }
                        .onEnded { _ in
                            isDragging = false
                            onCommit(Int(round(value)))
                        }
                )
            }
            .frame(height: 24)

            // Scale labels
            HStack {
                ForEach([20, 40, 60, 80, 100], id: \.self) { mark in
                    Text("\(mark)%")
                        .font(.system(size: 10, weight: Int(round(value)) == mark ? .bold : .medium))
                        .monospacedDigit()
                        .foregroundStyle(Int(round(value)) == mark ? palette.foreground : palette.mutedForeground)
                    if mark != 100 {
                        Spacer()
                    }
                }
            }
        }
    }
}
