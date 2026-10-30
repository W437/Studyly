import SwiftUI

// Small pieces of motion for the assistant's cards. Each settles to its final frame under Reduce Motion (`clReduceMotion`),
// and none loops once the work is done.

/// A tick that draws itself.
struct DrawnCheckShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + rect.width * 0.18, y: rect.midY + rect.height * 0.02))
        p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.42, y: rect.maxY - rect.height * 0.24))
        p.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.14, y: rect.minY + rect.height * 0.26))
        return p
    }
}

/// A round badge with a tick drawing itself inside. `done` flips it from an empty ring to the filled, ticked state.
struct DrawnCheck: View {
    var done: Bool
    var tint: Color = CLColor.mint
    var size: CGFloat = 22

    @Environment(\.clReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().strokeBorder(done ? tint : CLColor.surface3, lineWidth: 2)
            Circle().fill(tint).scaleEffect(done ? 1 : 0.2).opacity(done ? 1 : 0)
            DrawnCheckShape()
                .trim(from: 0, to: done ? 1 : 0)
                .stroke(CLColor.onFill, style: StrokeStyle(lineWidth: size * 0.11, lineCap: .round, lineJoin: .round))
                .padding(size * 0.2)
        }
        .frame(width: size, height: size)
        .animation(reduceMotion ? nil : CLMotion.pop, value: done)
        .accessibilityHidden(true)
    }
}

/// Text that types itself out, once per change of text, and is all there at once under Reduce Motion.
struct TypewriterText: View {
    let text: String
    var perSecond: Double = 48

    @Environment(\.clReduceMotion) private var reduceMotion
    @State private var shown = 0

    var body: some View {
        Text(String(text.prefix(reduceMotion ? text.count : shown)))
            .task(id: text) {
                guard !reduceMotion else { shown = text.count; return }
                shown = min(shown, text.count)
                let step = max(1, Int(perSecond / 30))
                while shown < text.count {
                    shown = min(text.count, shown + step)
                    try? await nap(33)
                    if Task.isCancelled { return }
                }
            }
    }
}

/// A burst of small sparkles from the middle, once per change of `trigger`.
struct SparkBurst: View {
    var trigger: Int
    var tint: Color = CLColor.sun
    var count = 7
    var radius: CGFloat = 34

    @Environment(\.clReduceMotion) private var reduceMotion
    @State private var out = false

    var body: some View {
        ZStack {
            ForEach(0..<count, id: \.self) { i in
                let angle = Double(i) / Double(count) * 2 * .pi + 0.4
                SparkleShape()
                    .fill(i % 2 == 0 ? tint : CLColor.tangerine)
                    .frame(width: i % 3 == 0 ? 10 : 7, height: i % 3 == 0 ? 10 : 7)
                    .offset(x: out ? cos(angle) * radius : 0, y: out ? sin(angle) * radius : 0)
                    .scaleEffect(out ? 0.2 : 1)
                    .opacity(out ? 0 : 1)
            }
        }
        .opacity(reduceMotion || trigger == 0 ? 0 : 1)
        .allowsHitTesting(false)
        .onChange(of: trigger) { _, _ in
            guard !reduceMotion else { return }
            out = false
            withAnimation(.easeOut(duration: 0.75)) { out = true }
        }
        .accessibilityHidden(true)
    }
}

/// A beam of light that passes down a view once, lighting what it crosses. `run` starts it.
struct ScanBeam: ViewModifier {
    var run: Int
    var tint: Color = CLColor.sky

    @Environment(\.clReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 1.2

    func body(content: Content) -> some View {
        content.overlay {
            GeometryReader { geo in
                let h = geo.size.height
                LinearGradient(colors: [tint.opacity(0), tint.opacity(0.28), tint.opacity(0)], startPoint: .top, endPoint: .bottom)
                    .frame(height: max(26, h * 0.5))
                    .offset(y: progress * h - max(26, h * 0.5) / 2)
                    .overlay(alignment: .top) {
                        Capsule().fill(tint.opacity(0.9)).frame(height: 1.5)
                            .shadow(color: tint, radius: 6)
                            .offset(y: progress * h)
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
            }
            .allowsHitTesting(false)
            .clipped()
            .opacity(reduceMotion ? 0 : 1)
        }
        .onChange(of: run) { _, _ in
            guard !reduceMotion else { return }
            progress = -0.2
            withAnimation(.timingCurve(0.3, 0.1, 0.3, 1, duration: 1.0)) { progress = 1.2 }
        }
        .task {
            guard !reduceMotion, run > 0 else { return }
            progress = -0.2
            withAnimation(.timingCurve(0.3, 0.1, 0.3, 1, duration: 1.0)) { progress = 1.2 }
        }
    }
}

extension View {
    func scanBeam(run: Int, tint: Color = CLColor.sky) -> some View { modifier(ScanBeam(run: run, tint: tint)) }
}

/// A soft moving highlight over something being worked on.
struct WorkingShimmer: ViewModifier {
    var active: Bool

    @Environment(\.clReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if active && !reduceMotion {
            content.overlay {
                TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
                    GeometryReader { geo in
                        let t = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
                        LinearGradient(colors: [.clear, Color.white.opacity(0.35), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: geo.size.width * 0.5)
                            .offset(x: (t * 1.6 - 0.5) * geo.size.width)
                            .blendMode(.plusLighter)
                    }
                }
                .allowsHitTesting(false)
                .mask(content)
            }
        } else {
            content
        }
    }
}

extension View {
    func workingShimmer(_ active: Bool) -> some View { modifier(WorkingShimmer(active: active)) }
}

/// Three dots that breathe in turn: Cap is still writing.
struct WorkingDots: View {
    var tint: Color = CLColor.ink3

    @Environment(\.clReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    Circle().fill(tint)
                        .frame(width: 6, height: 6)
                        .scaleEffect(reduceMotion ? 1 : 0.65 + 0.35 * max(0, sin(t * 5 - Double(i) * 0.9)))
                        .opacity(reduceMotion ? 0.7 : 0.45 + 0.55 * max(0, sin(t * 5 - Double(i) * 0.9)))
                }
            }
        }
        .accessibilityHidden(true)
    }
}
