import SwiftUI

/// The readiness ring: a round-capped arc over a track, coloured by `CLColor.readiness`, with the percentage in
/// rounded numerals. Shared with the widget extension. Pass `animatesFromZero` to make it climb on appear (the
/// onboarding scene and the readiness reveal use the same ring and the same `CLMotion.fill`-length climb).
struct ReadinessRing: View {
    /// 0…1.
    var value: Double
    var size: CGFloat = 86
    var lineWidth: CGFloat = 10
    var showsLabel = true
    var caption: String?
    var animatesFromZero = false
    var trackColor: Color = CLColor.surface3

    @State private var shown: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let clamped = max(0, min(1, value))
        ZStack {
            Circle().stroke(trackColor, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: animatesFromZero ? shown : clamped)
                .stroke(CLColor.readiness(clamped), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if showsLabel {
                VStack(spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text("\(Int(((animatesFromZero ? shown : clamped) * 100).rounded()))")
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
            } else {
                withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 1.3)) { shown = clamped }
            }
        }
        .onChange(of: value) { _, newValue in
            guard animatesFromZero else { return }
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .timingCurve(0.2, 0.8, 0.2, 1, duration: 1.0)) {
                shown = max(0, min(1, newValue))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(caption ?? "Readiness"))
        .accessibilityValue(Text("\(Int((clamped * 100).rounded())) percent"))
    }
}
