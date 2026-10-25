import SwiftUI

// The pieces the readiness and plan steps build from: the checklist that builds the plan (the same spinner-to-check
// beat as the processing steps), the projected path to the target, and the week's minutes.

/// "Building your plan": each step spins, then lands as a mint check.
struct PlanChecklist: View {
    let steps: [String]
    /// Steps done.
    let done: Int
    /// The next step is being worked on (a spinner).
    var working: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 14) {
                    dot(index)
                    Text(step)
                        .clFont(.callout)
                        .fontWeight(.semibold)
                        .foregroundStyle(CLColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 3)
                }
                .padding(.vertical, 7)
                .opacity(index < done || (index == done && working) ? 1 : 0.45)
                .accessibilityElement(children: .combine)
                .accessibilityValue(index < done ? "Done" : index == done && working ? "In progress" : "Waiting")
            }
        }
    }

    private func dot(_ index: Int) -> some View {
        let isDone = index < done
        let isWorking = index == done && working
        return ZStack {
            Circle().fill(isDone ? CLColor.mint : isWorking ? CLColor.skySoft : CLColor.surface3)
            if isDone {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(CLColor.onFill)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            } else if isWorking {
                ProgressView()
                    .controlSize(.mini)
                    .tint(CLColor.skyInk)
            }
        }
        .frame(width: 28, height: 28)
        .accessibilityHidden(true)
    }
}

/// The plan's projected readiness from today to exam day, against the target. One series (no legend: the title
/// names it), a hairline goal, labelled ends, and the honest caption that it's a projection.
struct PlanPathChart: View {
    let points: [ReadinessPoint]
    let target: Double
    /// 0…1 of the line drawn (animated by the step).
    var drawn: Double

    private let plotTop: CGFloat = 18
    private let plotBottom: CGFloat = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                let size = geo.size
                let unit = unitPoints
                ZStack(alignment: .topLeading) {
                    Path { path in
                        let y = yPosition(target, in: size)
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: size.width, y: y))
                    }
                    .stroke(CLColor.mint, lineWidth: 1)
                    Text("\(CLFormat.percent(target)) goal")
                        .clFont(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(CLColor.ink2)
                        .fixedSize()
                        .position(x: 34, y: yPosition(target, in: size) - 10)
                    PathLine(points: unit, top: plotTop, bottom: plotBottom)
                        .fill(LinearGradient(colors: [CLColor.tangerine.opacity(0.12), CLColor.tangerine.opacity(0)],
                                             startPoint: .top, endPoint: .bottom))
                        .mask(alignment: .leading) {
                            Rectangle().frame(width: size.width * drawn)
                        }
                    PathLine(points: unit, top: plotTop, bottom: plotBottom, closed: false)
                        .trim(from: 0, to: drawn)
                        .stroke(CLColor.tangerine, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    if let first = unit.first {
                        endDot(CLColor.tangerine)
                            .position(position(first, in: size))
                    }
                    if let last = unit.last {
                        endDot(points.last.map { $0.value >= target - 0.0001 } == true ? CLColor.mint : CLColor.tangerine)
                            .position(position(last, in: size))
                            .scaleEffect(drawn >= 0.98 ? 1 : 0.3)
                            .opacity(drawn >= 0.98 ? 1 : 0)
                    }
                }
            }
            .frame(height: 128)
            HStack(alignment: .firstTextBaseline) {
                Text("Today \(CLFormat.percent(points.first?.value ?? 0))")
                Spacer(minLength: 8)
                Text("Exam day \(CLFormat.percent(points.last?.value ?? 0))")
            }
            .clFont(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(CLColor.ink2)
            Text("Projected, if you follow the plan")
                .clFont(.caption)
                .foregroundStyle(CLColor.ink3)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your projected path to \(CLFormat.percent(target))")
        .accessibilityValue("From \(CLFormat.percent(points.first?.value ?? 0)) today to \(CLFormat.percent(points.last?.value ?? 0)) on exam day, if you follow the plan.")
    }

    private func endDot(_ color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 10, height: 10)
            .padding(2)
            .background(CLColor.surface, in: Circle())
    }

    /// Points in unit space: x by time from the first to the last, y the value (0…1).
    private var unitPoints: [CGPoint] {
        guard let first = points.first?.date, let last = points.last?.date, last > first else {
            return points.enumerated().map { CGPoint(x: Double($0.offset) / Double(max(1, points.count - 1)), y: $0.element.value) }
        }
        let span = last.timeIntervalSince(first)
        return points.map { CGPoint(x: $0.date.timeIntervalSince(first) / span, y: min(1, max(0, $0.value))) }
    }

    private func yPosition(_ value: Double, in size: CGSize) -> CGFloat {
        plotTop + (1 - value) * (size.height - plotTop - plotBottom)
    }

    private func position(_ unit: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: unit.x * size.width, y: yPosition(unit.y, in: size))
    }
}

/// The projected line (or, closed, the area under it) through unit-space points.
struct PathLine: Shape {
    var points: [CGPoint]
    var top: CGFloat
    var bottom: CGFloat
    var closed = true

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        func at(_ p: CGPoint) -> CGPoint {
            CGPoint(x: rect.minX + p.x * rect.width, y: rect.minY + top + (1 - p.y) * (rect.height - top - bottom))
        }
        path.move(to: at(first))
        for point in points.dropFirst() { path.addLine(to: at(point)) }
        if closed, let last = points.last {
            path.addLine(to: CGPoint(x: at(last).x, y: rect.maxY))
            path.addLine(to: CGPoint(x: at(first).x, y: rect.maxY))
            path.closeSubpath()
        }
        return path
    }
}

/// One day of the week strip.
struct PlanWeekDay: Identifiable, Equatable {
    var id: Int
    var date: Date
    var minutes: Int
    var kind: PlanDay.Kind
    var isToday: Bool
}

/// The next seven days' minutes as columns: today in the accent, rest days empty, the exam eve and the exam marked.
struct PlanWeekStrip: View {
    let days: [PlanWeekDay]
    var risen: Bool

    private let barHeight: CGFloat = 64

    var body: some View {
        let most = max(1, days.map(\.minutes).max() ?? 1)
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                VStack(spacing: 6) {
                    Text(label(day))
                        .clFont(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(day.kind == .rest ? CLColor.ink3 : CLColor.ink2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    ZStack(alignment: .bottom) {
                        Color.clear.frame(height: barHeight)
                        if day.kind == .exam {
                            Image(systemName: "flag.checkered")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(CLColor.tangerineInk)
                                .padding(.bottom, 4)
                        } else if day.minutes > 0 {
                            UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4, style: .continuous)
                                .fill(day.isToday ? CLColor.tangerine : CLColor.tangerine.opacity(0.42))
                                .frame(width: 22)
                                .frame(height: risen ? max(6, barHeight * Double(day.minutes) / Double(most)) : 4)
                                .animation(CLMotion.settle.delay(Double(index) * 0.05), value: risen)
                        }
                    }
                    Text(day.date.formatted(.dateTime.weekday(.narrow)))
                        .clFont(.caption)
                        .fontWeight(day.isToday ? .bold : .semibold)
                        .foregroundStyle(day.isToday ? CLColor.tangerineInk : CLColor.ink3)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(day.date.formatted(.dateTime.weekday(.wide)))
                .accessibilityValue(spoken(day))
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    private func label(_ day: PlanWeekDay) -> String {
        switch day.kind {
        case .exam: "Exam"
        case .rest: "rest"
        case .examEve: "\(day.minutes)m"
        case .study, .light: "\(day.minutes)m"
        }
    }

    private func spoken(_ day: PlanWeekDay) -> String {
        switch day.kind {
        case .exam: "Exam day"
        case .rest: "Rest"
        case .examEve: "Exam eve, \(SessionCopy.minutes(day.minutes)) on weak spots"
        case .study, .light: SessionCopy.minutes(day.minutes)
        }
    }
}
