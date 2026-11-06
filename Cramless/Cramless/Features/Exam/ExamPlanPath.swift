import SwiftUI

/// The exam's plan as stops on a path (`ExamPresentation.stops`): today, the study days or "about N min a day", the eve, the exam.
/// Under it, "What if I skip Saturday?": the skipped day shows as its own stop and the cost in points of readiness on exam day
/// (`ExamPresentation.skipCost`). The what-if is a preview: nothing is marked as a day off.
struct ExamPlanPath: View {
    let stops: [ExamPresentation.Stop]
    var skip: ExamPresentation.SkipOption?
    var skipping = false
    var cost: ExamPresentation.SkipCost?
    var onToggleSkip: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(stops.enumerated()), id: \.element.id) { index, stop in
                ExamStopRow(stop: stop, isFirst: index == 0, isLast: index == stops.count - 1)
            }
            if let skip {
                Rectangle().fill(CLColor.hairline).frame(height: 1).padding(.vertical, 12)
                if skipping, let cost {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: cost.points < 2 ? "checkmark.circle" : "arrow.down.right.circle")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(cost.points < 2 ? CLColor.mintInk : CLColor.sunInk)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: cost.title).clFont(.subheadlineEmphasis).foregroundStyle(CLColor.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(verbatim: cost.detail).clFont(.footnote).foregroundStyle(CLColor.ink2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .accessibilityElement(children: .combine)
                    .padding(.bottom, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
                Button {
                    CLHaptics.select()
                    onToggleSkip()
                } label: {
                    Text(verbatim: skipping ? skip.keep : skip.question)
                }
                .buttonStyle(.cl(.soft, size: .medium, fullWidth: false))
                .accessibilityHint(Text(skipping ? "Shows the plan with that day back" : "Shows what skipping that day costs. Nothing changes in your plan."))
            }
        }
        .clCard()
    }
}

/// One stop: a marker on the path's line (a filled dot for today, a ring for a study day, dots for a stretch of days, a moon for the
/// eve, a cap for the exam, a dashed ring for a skipped day) and its words. The shapes carry the meaning, not the colour alone.
private struct ExamStopRow: View {
    let stop: ExamPresentation.Stop
    let isFirst: Bool
    let isLast: Bool

    private let column: CGFloat = 26
    private let markerTop: CGFloat = 2

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(isFirst ? Color.clear : CLColor.surface3)
                    .frame(width: 2, height: markerTop)
                marker
                    .frame(width: column, height: 22)
                Rectangle()
                    .fill(isLast ? Color.clear : CLColor.surface3)
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: column)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: stop.title)
                    .clFont(stop.kind == .today || stop.kind == .exam ? .subheadlineEmphasis : .subheadline)
                    .foregroundStyle(stop.isSkipped ? CLColor.ink3 : CLColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = stop.detail {
                    Text(verbatim: detail).clFont(.footnote).foregroundStyle(CLColor.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let note = stop.note {
                    Label {
                        Text(verbatim: note)
                    } icon: {
                        Image(systemName: "arrow.uturn.forward")
                    }
                    .clFont(.footnote)
                    .foregroundStyle(CLColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, markerTop + 1)
            .padding(.bottom, isLast ? 0 : 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: stop.title))
        .accessibilityValue(Text(verbatim: [stop.detail, stop.note].compactMap { $0 }.joined(separator: ". ")))
    }

    @ViewBuilder
    private var marker: some View {
        if stop.isSkipped {
            Circle()
                .strokeBorder(CLColor.ink4, style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
                .frame(width: 16, height: 16)
                .background(CLColor.surface, in: Circle())
        } else {
            switch stop.kind {
            case .today:
                Circle().fill(CLColor.tangerine).frame(width: 16, height: 16)
                    .overlay(Circle().stroke(CLColor.surface, lineWidth: 3))
            case .day:
                Circle().strokeBorder(CLColor.tangerine, lineWidth: 3).frame(width: 14, height: 14)
                    .background(CLColor.surface, in: Circle())
            case .span:
                Image(systemName: "ellipsis")
                    .rotationEffect(.degrees(90))
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(CLColor.ink3)
                    .background(CLColor.surface)
            case .eve:
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(CLColor.skyInk)
                    .frame(width: 22, height: 22)
                    .background(CLColor.surface, in: Circle())
            case .exam:
                Image(systemName: "graduationcap.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CLColor.onFill)
                    .frame(width: 24, height: 24)
                    .background(CLColor.mint, in: Circle())
            }
        }
    }
}
