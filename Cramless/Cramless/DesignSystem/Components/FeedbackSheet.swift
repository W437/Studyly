import SwiftUI

// The answer panel: after a question is checked, the footer's buttons give way to a panel that rises from the bottom
// edge in the verdict's colour, with Cap reacting, a big headline ("Nice!", "Almost.", "Not yet.", "Saved it."), the
// run of right answers, why, the fix, the source, and Continue. The question views build an `AnswerFeedback`;
// `sessionFooter(feedback:…)` swaps it in (SessionParts.swift). At the accessibility sizes the panel keeps only the
// headline and Continue, and the view shows the details in its card (`FeedbackDetails`).

/// The colours of a result: mint right, sun partly, rose not yet, and sky where nothing is judged yet.
enum FeedbackTone: Sendable, Equatable {
    case mint, sun, rose
    /// An answer to compare with the model answer, marked by the person: no verdict's colour yet.
    case neutral

    var fill: Color {
        switch self {
        case .mint: CLColor.mintSoft
        case .sun: CLColor.sunSoft
        case .rose: CLColor.roseSoft
        case .neutral: CLColor.skySoft
        }
    }

    var ink: Color {
        switch self {
        case .mint: CLColor.mintInk
        case .sun: CLColor.sunInk
        case .rose: CLColor.roseInk
        case .neutral: CLColor.skyInk
        }
    }

    var solid: Color {
        switch self {
        case .mint: CLColor.mint
        case .sun: CLColor.sun
        case .rose: CLColor.rose
        case .neutral: CLColor.sky
        }
    }

    /// Continue's fill on the panel. "Not yet" (and an answer still to be marked) moves on in tangerine, the primary action's
    /// colour: a red button reads as an alarm.
    var button: Color {
        switch self {
        case .mint: CLColor.mint
        case .sun: CLColor.sun
        case .rose, .neutral: CLColor.tangerine
        }
    }

    var buttonEdge: Color {
        switch self {
        case .mint: CLColor.mintEdge
        case .sun: CLColor.sunEdge
        case .rose, .neutral: CLColor.tangerineEdge
        }
    }
}

/// What an answer's panel says.
struct AnswerFeedback: Equatable {
    var tone: FeedbackTone
    var headline: LocalizedStringResource
    /// Cap's reaction: a hop for "Nice!", a wiggle for "Almost.", a kind nod for "Not yet.", sparkles for a save or
    /// a run of five. While the AI double-checks, Cap thinks instead.
    var cap: CapMoment
    /// Why: the option's explanation, the grader's feedback.
    var message: String?
    var fix: String?
    var note: String?
    var source: SourceRef?
    /// Who checked it ("Checked on this iPhone").
    var provenance: String?
    var working = false
    /// The run of right answers this one makes; shown from 3.
    var combo = 0

    static func == (a: AnswerFeedback, b: AnswerFeedback) -> Bool {
        a.tone == b.tone && String(localized: a.headline) == String(localized: b.headline) && a.cap == b.cap
            && a.message == b.message && a.fix == b.fix && a.note == b.note && a.source == b.source
            && a.provenance == b.provenance && a.working == b.working && a.combo == b.combo
    }
}

/// The panel itself. `primary` is Continue; `secondary` holds "Explain my mistake" and the like.
struct FeedbackPanel<Primary: View, Secondary: View>: View {
    let feedback: AnswerFeedback
    let primary: Primary
    let secondary: Secondary

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // Cap is 82 pt, up from 60, so he reads at a glance. The panel's spacing is tightened by the same amount, so it is no taller
        // than it was, and nothing overlaps the card above. His art is tall and narrow: the box has empty sides, which the negative
        // padding takes back. At the accessibility sizes the panel keeps the smaller Cap and the roomier spacing it always had.
        let accessibility = typeSize.isAccessibilitySize
        VStack(alignment: .leading, spacing: accessibility ? 12 : 8) {
            HStack(alignment: .center, spacing: accessibility ? 12 : 6) {
                CapView(feedback.working ? .working : feedback.cap, size: accessibility ? 44 : 82)
                    .padding(.horizontal, accessibility ? 0 : -8)
                VStack(alignment: .leading, spacing: 4) {
                    Text(feedback.headline)
                        .clFont(.brandTitle(28))
                        .foregroundStyle(feedback.tone.ink)
                        // A longer headline ("Compare with the answer.") wraps to a second line beside Cap instead of being cut off.
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    if feedback.combo >= 3 {
                        ComboChip(count: feedback.combo)
                    }
                }
                Spacer(minLength: 0)
            }
            if !accessibility {
                FeedbackDetails(feedback: feedback)
            }
            primary
            if !accessibility {
                HStack(spacing: 10) { secondary }
            }
        }
        .frame(maxWidth: CLMetrics.readableWidth, alignment: .leading)
        .padding(.horizontal, CLSpace.gutter)
        .padding(.top, accessibility ? 18 : 10)
        .padding(.bottom, accessibility ? 8 : 6)
        .frame(maxWidth: .infinity)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30, style: .continuous)
                .fill(CLColor.surface)
                .overlay(UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30, style: .continuous)
                    .fill(feedback.tone.fill))
                .shadow(color: CLColor.night.opacity(0.08), radius: 16, y: -4)
                .ignoresSafeArea(edges: .bottom)
        }
        .accessibilityElement(children: .contain)
    }
}

/// Why, the fix, a spelling note, the source and who checked it: on the panel, or (at the accessibility sizes) in
/// the question's card.
struct FeedbackDetails: View {
    let feedback: AnswerFeedback

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let message = feedback.message, !message.isEmpty {
                Text(message)
                    .clFont(.subheadline)
                    .foregroundStyle(CLColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let fix = feedback.fix, !fix.isEmpty {
                Text(fix)
                    .clFont(.subheadlineEmphasis)
                    .foregroundStyle(CLColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let note = feedback.note {
                Label(note, systemImage: "textformat.abc")
                    .clFont(.footnoteEmphasis)
                    .foregroundStyle(CLColor.ink2)
            }
            if feedback.source != nil || feedback.provenance != nil {
                HStack(alignment: .center, spacing: 8) {
                    if let source = feedback.source { SourceButton(ref: source) }
                    if let provenance = feedback.provenance {
                        HStack(spacing: 5) {
                            if feedback.working { ProgressView().controlSize(.mini) }
                            Text(provenance)
                                .clFont(.caption)
                                .foregroundStyle(CLColor.ink2)
                                .contentTransition(.opacity)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// "5 in a row": a run of right answers, from three on.
struct ComboChip: View {
    let count: Int

    var body: some View {
        Label("\(count) in a row", systemImage: "bolt.fill")
            .font(.system(.subheadline, design: .rounded, weight: .bold))
            .contentTransition(.numericText(value: Double(count)))
            .foregroundStyle(CLColor.onFill)
            .padding(.horizontal, 10)
            .frame(minHeight: 26)
            .background(CLColor.mint, in: Capsule())
            .accessibilityLabel("\(count) right in a row")
    }
}
