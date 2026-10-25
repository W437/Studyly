import SwiftUI

/// A marked range inside a piece of text, for the highlighter. Ranges are character offsets into the plain
/// string (Swift `Character` count from the start), produced by the grader from quotes it found verbatim.
struct HighlightMark: Hashable, Sendable {
    enum Tone: Sendable { case hit, miss, key, sky }
    var range: Range<Int>
    var tone: Tone
}

/// Text with highlighter marks that sweep in left to right, the way a pen would. Used by grading feedback
/// ("the ideas you hit"), the source page (the lines a question came from) and the onboarding demos.
///
/// `revealed` drives the sweep: false draws the text clean, true sweeps every mark in, staggered.
struct HighlightedText: View {
    let text: String
    var marks: [HighlightMark]
    var revealed = true
    var style: CLTextStyle = .body
    var color: Color = CLColor.ink

    @State private var progress: Double = 0
    @Environment(\.clReduceMotion) private var reduceMotion

    var body: some View {
        HighlightLayer(text: text, marks: marks, progress: revealed ? progress : 0)
            .clFont(style)
            .foregroundStyle(color)
            .onAppear { animate(to: revealed) }
            .onChange(of: revealed) { _, on in animate(to: on) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(text))
    }

    private func animate(to on: Bool) {
        if !on { progress = 0; return }
        if reduceMotion { progress = 1; return }
        progress = 0
        withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: max(0.55, Double(marks.count) * 0.35))) {
            progress = 1
        }
    }
}

/// Redrawn on every animation frame (it is `Animatable`), so the marks really sweep instead of snapping.
private struct HighlightLayer: View, Animatable {
    let text: String
    let marks: [HighlightMark]
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        Text(attributed(progress: progress))
    }

    /// Builds the attributed string. Each mark covers the fraction of its range the sweep has reached; marks
    /// start one after another so the eye follows them in order.
    private func attributed(progress: Double) -> AttributedString {
        var result = AttributedString(text)
        let chars = Array(text)
        let sorted = marks.sorted { $0.range.lowerBound < $1.range.lowerBound }
        guard !sorted.isEmpty else { return result }
        let slot = 1.0 / Double(sorted.count)
        for (index, mark) in sorted.enumerated() {
            let local = max(0, min(1, (progress - Double(index) * slot * 0.6) / max(slot, 0.0001)))
            guard local > 0 else { continue }
            let lower = max(0, min(chars.count, mark.range.lowerBound))
            let upper = max(lower, min(chars.count, mark.range.upperBound))
            let visibleUpper = lower + Int((Double(upper - lower) * local).rounded(.up))
            guard visibleUpper > lower,
                  let start = result.characters.index(result.startIndex, offsetBy: lower, limitedBy: result.endIndex),
                  let end = result.characters.index(result.startIndex, offsetBy: visibleUpper, limitedBy: result.endIndex)
            else { continue }
            result[start..<end].backgroundColor = fill(for: mark.tone)
        }
        return result
    }

    private func fill(for tone: HighlightMark.Tone) -> Color {
        switch tone {
        case .hit: CLColor.markHit
        case .miss: CLColor.markMiss
        case .key: CLColor.markKey
        case .sky: CLColor.markSky
        }
    }
}

extension HighlightMark {
    /// Finds `quote` inside `text` (case- and whitespace-insensitive) and returns its character range, or nil.
    /// The grader and the source view only ever mark text they can find: a model's quote that is not in the
    /// person's answer is dropped, never drawn somewhere approximate.
    static func locate(_ quote: String, in text: String) -> Range<Int>? {
        let needle = quote.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return nil }
        let hay = text.lowercased()
        guard let r = hay.range(of: needle, options: [.diacriticInsensitive]) else { return nil }
        let lower = hay.distance(from: hay.startIndex, to: r.lowerBound)
        let upper = hay.distance(from: hay.startIndex, to: r.upperBound)
        return lower..<upper
    }
}
