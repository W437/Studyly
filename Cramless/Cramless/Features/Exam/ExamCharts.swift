import Charts
import SwiftUI

// The exam charts. One series each (readiness), so no legend box: the card's title names it, and a small key tells
// the solid history from the dashed projection. Marks: 2.5 pt lines with round caps, the history's area as a 10%
// wash, an end dot with a surface ring, solid hairline gridlines. Brand tangerine sits under 3:1 on white, so the
// values that matter are direct labels (now, exam day, the target) and every point is in the VoiceOver chart
// description; scrubbing reads any day out.

/// Readiness so far (solid) and the plan's path to exam day (dashed), against the target. Drag to read a day.
struct ExamPathChart: View {
    let path: ExamPresentation.Path
    let calendar: Calendar
    var height: CGFloat = 190

    @State private var selected: Date?
    @State private var lastTickDay: Int?
    @ScaledMetric(relativeTo: .caption) private var labelScale: CGFloat = 1

    var body: some View {
        let span = max(1, path.end.timeIntervalSince(path.start))
        let nowFraction = path.now.timeIntervalSince(path.start) / span
        let endIsClose = 1 - nowFraction < 0.24
        let end = path.projection.last
        Chart {
            RuleMark(y: .value("Target", path.target))
                .foregroundStyle(CLColor.mintInk.opacity(0.7))
                .lineStyle(StrokeStyle(lineWidth: 1))
                .annotation(position: .top, alignment: .leading, spacing: 3) {
                    Text("Target \(CLFormat.percent(path.target))")
                        .clFont(.caption).fontWeight(.semibold)
                        .foregroundStyle(CLColor.mintInk)
                }
                .accessibilityLabel(Text("Target"))
                .accessibilityValue(Text(CLFormat.percent(path.target)))

            ForEach(path.history) { point in
                AreaMark(x: .value("Day", point.date), yStart: .value("Base", 0.0), yEnd: .value("Readiness", point.value))
                    .foregroundStyle(CLColor.tangerine.opacity(0.10))
                    .interpolationMethod(.monotone)
                    .accessibilityHidden(true)
            }
            ForEach(path.history) { point in
                LineMark(x: .value("Day", point.date), y: .value("Readiness", point.value), series: .value("Part", "So far"))
                    .foregroundStyle(CLColor.tangerine)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
                    .accessibilityLabel(Text(dayLabel(point.date)))
                    .accessibilityValue(Text(CLFormat.percent(point.value)))
            }
            ForEach(path.projection) { point in
                LineMark(x: .value("Day", point.date), y: .value("Readiness", point.value), series: .value("Part", "Projection"))
                    .foregroundStyle(CLColor.tangerine.opacity(0.8))
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round, dash: [2, 6]))
                    .interpolationMethod(.monotone)
                    .accessibilityLabel(Text(dayLabel(point.date)))
                    .accessibilityValue(Text("\(CLFormat.percent(point.value)), projected"))
            }

            if let end, end.date > path.now {
                PointMark(x: .value("Day", end.date), y: .value("Readiness", end.value))
                    .symbolSize(110)
                    .foregroundStyle(CLColor.surface)
                    .accessibilityHidden(true)
                PointMark(x: .value("Day", end.date), y: .value("Readiness", end.value))
                    .symbolSize(44)
                    .foregroundStyle(CLColor.tangerine.opacity(0.8))
                    .annotation(position: end.value > path.target - 0.12 && end.value < path.target + 0.06 ? .bottom : .top,
                                alignment: .trailing, spacing: 5) {
                        Text(endIsClose ? "\(CLFormat.percent(end.value)) · \(shortDay(end.date))" : CLFormat.percent(end.value))
                            .clFont(.number(13, .bold))
                            .foregroundStyle(CLColor.ink2)
                    }
                    .accessibilityHidden(true)
            }
            PointMark(x: .value("Day", path.now), y: .value("Readiness", path.current))
                .symbolSize(190)
                .foregroundStyle(CLColor.surface)
                .accessibilityHidden(true)
            PointMark(x: .value("Day", path.now), y: .value("Readiness", path.current))
                .symbolSize(90)
                .foregroundStyle(CLColor.tangerine)
                .annotation(position: path.current > path.target - 0.12 && path.current < path.target + 0.06 ? .bottomLeading : .topLeading,
                            spacing: 2) {
                    Text(CLFormat.percent(path.current))
                        .clFont(.number(14, .heavy))
                        .foregroundStyle(CLColor.ink)
                }
                .accessibilityHidden(true)

            if let selected, let point = path.nearest(to: selected) {
                RuleMark(x: .value("Day", point.date))
                    .foregroundStyle(CLColor.ink3)
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, spacing: 0, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        VStack(spacing: 1) {
                            Text(CLFormat.percent(point.value)).clFont(.number(15, .heavy)).foregroundStyle(CLColor.ink)
                            Text(point.isProjection ? "\(shortDay(point.date)) · projected" : shortDay(point.date))
                                .clFont(.caption).foregroundStyle(CLColor.ink2)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(CLColor.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .shadow(color: CLColor.night.opacity(0.12), radius: 6, y: 2)
                    }
                    .accessibilityHidden(true)
            }
        }
        .chartYScale(domain: 0...1.08)
        .chartXScale(domain: path.start...path.end)
        .chartYAxis {
            AxisMarks(position: .trailing, values: [0, 0.5, 1]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1)).foregroundStyle(CLColor.hairline)
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(CLFormat.percent(v)).clFont(.caption).foregroundStyle(CLColor.ink3)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: xLabels(endIsClose: endIsClose).map(\.date)) { value in
                if let date = value.as(Date.self), let label = xLabels(endIsClose: endIsClose).first(where: { abs($0.date.timeIntervalSince(date)) < 1 }) {
                    AxisValueLabel(anchor: label.anchor) {
                        Text(label.text).clFont(.caption).foregroundStyle(CLColor.ink3)
                    }
                }
            }
        }
        .chartXSelection(value: $selected)
        .frame(height: height * max(1, min(1.4, labelScale)))
        .onChange(of: selected) { _, date in
            // A tick for each day crossed while scrubbing.
            guard let date, let point = path.nearest(to: date) else { lastTickDay = nil; return }
            let day = calendar.dayNumber(for: point.date)
            if day != lastTickDay { CLHaptics.select(); lastTickDay = day }
        }
        .accessibilityLabel(Text("Readiness, the last two weeks and the plan to exam day"))
    }

    private struct XLabel { var date: Date; var text: String; var anchor: UnitPoint }

    private func xLabels(endIsClose: Bool) -> [XLabel] {
        var labels = [XLabel(date: path.start, text: shortDay(path.start), anchor: .topLeading),
                      XLabel(date: path.now, text: "Today", anchor: endIsClose ? .topTrailing : .top)]
        if !endIsClose {
            labels.append(XLabel(date: path.end, text: path.isCut ? "\(shortDay(path.end)) →" : shortDay(path.end), anchor: .topTrailing))
        }
        return labels
    }

    private func shortDay(_ date: Date) -> String { LibraryFormat.shortDate(date, calendar: calendar) }

    private func dayLabel(_ date: Date) -> String { CLFormat.day(date, calendar: calendar) }
}

/// The key under the path chart: what's solid and what's dashed.
struct ExamPathKey: View {
    var body: some View {
        HStack(spacing: 14) {
            key(dashed: false, "So far")
            key(dashed: true, "If you follow the plan")
        }
        .accessibilityHidden(true)
    }

    private func key(dashed: Bool, _ title: String) -> some View {
        HStack(spacing: 6) {
            Canvas { context, size in
                var line = Path()
                line.move(to: CGPoint(x: 1, y: size.height / 2))
                line.addLine(to: CGPoint(x: size.width - 1, y: size.height / 2))
                context.stroke(line, with: .color(CLColor.tangerine.opacity(dashed ? 0.8 : 1)),
                               style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: dashed ? [2, 5] : []))
            }
            .frame(width: 20, height: 6)
            Text(title).clFont(.caption).foregroundStyle(CLColor.ink2)
        }
    }
}

/// Two weeks of readiness as a sparkline: the line in the quiet ink, today's dot in its readiness colour.
struct ReadinessSparkline: View {
    let points: [ReadinessPoint]

    var body: some View {
        Chart {
            ForEach(points) { point in
                LineMark(x: .value("Day", point.date), y: .value("Readiness", point.value))
                    .foregroundStyle(CLColor.ink4)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
            }
            if let last = points.last {
                // The line ends in a star, with a ring of card colour so it reads over the line.
                PointMark(x: .value("Day", last.date), y: .value("Readiness", last.value))
                    .symbol {
                        ZStack {
                            SparkleShape().fill(CLColor.surface).frame(width: 21, height: 21)
                            SparkleShape().fill(CLColor.readiness(last.value)).frame(width: 15, height: 15)
                        }
                    }
            }
        }
        .chartYScale(domain: 0...1)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Last two weeks"))
        .accessibilityValue(Text(summary))
    }

    private var summary: String {
        guard let first = points.first, let last = points.last else { return "No history yet" }
        return "From \(CLFormat.percent(first.value)) to \(CLFormat.percent(last.value))"
    }
}
