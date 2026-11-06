import SwiftUI

/// The readiness ring: a round-capped arc over a track, coloured by `CLColor.readiness`, with the percentage in
/// rounded numerals. Shared with the widget extension. Pass `animatesFromZero` to make it climb on appear (the
/// onboarding scene and the readiness reveal use the same ring and the same `CLMotion.fill`-length climb).
///
/// The exam page also passes `goal` (a mint dot on the track where the exam's goal sits) and `projected` (a faint arc from now to
/// where the plan takes it). Both default to nil, so every other ring, the widgets' included, draws as before.
struct ReadinessRing: View {
    /// 0…1.
    var value: Double
    var size: CGFloat = 86
    var lineWidth: CGFloat = 10
    var showsLabel = true
    var caption: String?
    var animatesFromZero = false
    var trackColor: Color = CLColor.surface3
    /// The exam's goal, 0…1: a mint dot on the track.
    var goal: Double? = nil
    /// Where the plan takes the value, 0…1: a faint arc from the value on (drawn only when it is ahead of the value).
    var projected: Double? = nil
    /// `.projection` draws the arc dashed: a forecast ("about 52% after today"), not a measurement.
    var style: Style = .solid

    @State private var shown: Double = 0
    @State private var shownProjected: Double = 0
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    /// Reduce Motion, or the app's DEBUG override (`CRAMLESS_REDUCE_MOTION=1`; the Simulator can't switch it on).
    private var reduceMotion: Bool { systemReduceMotion || Self.forcesReduceMotion }

    #if DEBUG
    private static let forcesReduceMotion = ProcessInfo.processInfo.environment["CRAMLESS_REDUCE_MOTION"] == "1"
    #else
    private static let forcesReduceMotion = false
    #endif

    var body: some View {
        let clamped = max(0, min(1, value))
        let ahead = projected.map { max(clamped, min(1, $0)) } ?? clamped
        let current = animatesFromZero ? shown : clamped
        let reach = animatesFromZero ? shownProjected : ahead
        ZStack {
            Circle().stroke(trackColor, lineWidth: lineWidth)
            if projected != nil, reach > current + 0.002 {
                Circle()
                    .trim(from: current, to: reach)
                    .stroke(CLColor.readiness(ahead).opacity(0.24), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            Circle()
                .trim(from: 0, to: current)
                .stroke(CLColor.readiness(clamped), style: arcStroke)
                .rotationEffect(.degrees(-90))
            if let goal {
                goalDot(goal)
            }
            if showsLabel {
                VStack(spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text("\(Int((current * 100).rounded()))")
                            .font(.system(size: size * 0.26, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Text("%")
                            .font(.system(size: size * 0.13, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(CLColor.ink)
                    if let caption {
                        Text(caption)
                            .font(.system(size: max(10, size * 0.11), weight: .semibold))
                            .foregroundStyle(CLColor.ink2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                .padding(lineWidth)
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            guard animatesFromZero else { return }
            if reduceMotion {
                shown = clamped
                shownProjected = ahead
            } else {
                withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 1.3)) {
                    shown = clamped
                    shownProjected = ahead
                }
            }
        }
        .onChange(of: value) { _, _ in follow(clamped: clamped, ahead: ahead) }
        .onChange(of: projected) { _, _ in follow(clamped: clamped, ahead: ahead) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(caption ?? "Readiness"))
        .accessibilityValue(Text(accessibilityValue(clamped)))
    }

    /// The goal's place on the track: a mint dot with a ring of the track's colour round it, so it reads over the arcs too.
    private func goalDot(_ goal: Double) -> some View {
        let angle = Angle.degrees(360 * max(0, min(1, goal)) - 90)
        let radius = (size - lineWidth) / 2
        let dot = max(6, lineWidth * 0.62)
        return Circle()
            .fill(CLColor.mint)
            .overlay(Circle().stroke(CLColor.surface, lineWidth: max(1.5, dot * 0.22)))
            .frame(width: dot, height: dot)
            .offset(x: radius * cos(angle.radians), y: radius * sin(angle.radians))
            .accessibilityHidden(true)
    }

    private func follow(clamped: Double, ahead: Double) {
        guard animatesFromZero else { return }
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .timingCurve(0.2, 0.8, 0.2, 1, duration: 1.0)) {
            shown = clamped
            shownProjected = ahead
        }
    }

    /// "42 percent", or with a goal "42 percent, goal 80 percent".
    private func accessibilityValue(_ clamped: Double) -> String {
        let now = Int((clamped * 100).rounded())
        guard let goal else { return String(localized: "\(now) percent") }
        return String(localized: "\(now) percent, goal \(Int((max(0, min(1, goal)) * 100).rounded())) percent")
    }
}

extension ReadinessRing {
    enum Style: Sendable { case solid, projection }

    /// The arc's stroke: round-capped, and dashed for a projection (so it reads without colour too).
    var arcStroke: StrokeStyle {
        switch style {
        case .solid: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
        case .projection: StrokeStyle(lineWidth: lineWidth, lineCap: .round, dash: [lineWidth * 0.8, lineWidth * 1.9])
        }
    }
}
