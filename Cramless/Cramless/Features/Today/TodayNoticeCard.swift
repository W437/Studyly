import SwiftUI

/// "Cap noticed": one of Cap's cards (`CapNotice`) at a time, with "2 of 3" when there are others today, its one action, "Later" (until
/// tomorrow) and what the button costs. Today shows the first of `AppModel.todayNotices()`. The menu's "Don't show these" switches the
/// kind off (Settings ▸ Study turns it on again). "Plan updated" (after "Fix my week") has "OK" and Undo instead.
///
/// DEBUG: `CRAMLESS_TODAY_NOTICES=0|1|2|3` deals that many (see `TodaySnapshot`), `CRAMLESS_NOTICES=mixup,lookalike,fading,back,mock,gap,lecturedate|all|none`
/// shapes the world so the real engine finds them and `CRAMLESS_NOTICE_STATE=second|later|done|allLater` puts them part way through the
/// day (`AppModel+NoticeHarness`); `CRAMLESS_TODAY_LATER=<ms>` presses Later and `CRAMLESS_NOTICE_TAP=<ms>` the button, that long after
/// launch (`TodayView`).
struct TodayNoticeCard: View {
    let notice: CapNotice
    /// Its place among today's cards, from 1, and how many there are.
    let index: Int
    let total: Int
    var onAction: (CapNotice.Action) -> Void
    var onLater: () -> Void
    var onOpen: (CapNotice.Link) -> Void
    var onHide: () -> Void = {}

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // At the largest text the words take the card's whole width: beside the face, "Cap noticed" breaks inside a word.
        let large = typeSize.isAccessibilitySize
        HStack(alignment: .top, spacing: 12) {
            if !large { CapFace(size: 44) }
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: large ? .center : .firstTextBaseline) {
                    if large { CapFace(size: 44) } else { eyebrow }
                    Spacer(minLength: 8)
                    if total > 1, !notice.isConfirmation {
                        Text(verbatim: TodayCopy.noticeCount(index, of: total))
                            .clFont(.footnoteEmphasis)
                            .foregroundStyle(CLColor.ink3)
                            .monospacedDigit()
                            .accessibilityHidden(true)
                    }
                    if !notice.isConfirmation { menu }
                }
                // The menu's hit area reaches over the title's first line; it stays on top.
                .zIndex(1)
                if large { eyebrow.fixedSize(horizontal: false, vertical: true) }
                titleView
                Text(verbatim: notice.detail)
                    .clFont(.subheadline)
                    .foregroundStyle(CLColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                buttons
                    .padding(.top, 10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .clCard()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: total > 1 ? "\(String(localized: "Cap noticed")), \(TodayCopy.noticeCount(index, of: total))"
                                 : String(localized: "Cap noticed")))
    }

    private var eyebrow: some View {
        CLEyebrow(text: "Cap noticed", color: CLColor.tangerineInk)
            .accessibilityHidden(true)
    }

    /// A button's words are never cut: what it costs goes beside the buttons when all of it fits, and under them when it doesn't.
    @ViewBuilder private var buttons: some View {
        if notice.isConfirmation {
            ReflowStack(verticalAlignment: .center, spacing: 6) {
                Button("OK", action: onLater)
                    .buttonStyle(.cl(.dark, size: .medium, fullWidth: false))
                if let action = notice.action {
                    Button(action.title) { onAction(action) }
                        .buttonStyle(.cl(.ghost, size: .medium, fullWidth: false))
                        .accessibilityHint("Takes the minutes off your plan")
                }
            }
        } else if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 6) {
                actionButtons
                costCaption
            }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    actionButtons
                    costCaption.padding(.leading, 2)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) { actionButtons }
                    costCaption
                }
                VStack(alignment: .leading, spacing: 6) {
                    actionButtons
                    costCaption
                }
            }
        }
    }

    @ViewBuilder private var actionButtons: some View {
        if let action = notice.action {
            Button(action.title) { onAction(action) }
                .buttonStyle(.cl(.dark, size: .medium, fullWidth: typeSize.isAccessibilitySize))
        }
        if notice.decline != nil {
            Button(action: onLater) { Text(verbatim: ExamHeardCopy.wrong) }
                .buttonStyle(.cl(.ghost, size: .medium, fullWidth: typeSize.isAccessibilitySize))
                .accessibilityHint(Text(verbatim: ExamHeardCopy.refused))
        } else {
            Button("Later", action: onLater)
                .buttonStyle(.cl(.ghost, size: .medium, fullWidth: typeSize.isAccessibilitySize))
                .accessibilityHint("Cap brings it up tomorrow")
        }
    }

    @ViewBuilder private var costCaption: some View {
        if let cost = notice.cost {
            Text(verbatim: cost)
                .clFont(.caption)
                .foregroundStyle(CLColor.ink3)
        }
    }

    /// The menu's hit area is a full 44 points; the negative padding keeps it from making the card's top row taller.
    private var menu: some View {
        Menu {
            Button("Don't show these", systemImage: "eye.slash", action: onHide)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(CLColor.ink3)
                .frame(width: CLMetrics.minHitTarget, height: CLMetrics.minHitTarget)
                .contentShape(Rectangle())
        }
        .padding(.vertical, -14)
        .padding(.trailing, -12)
        .padding(.leading, -8)
        .accessibilityLabel("More")
    }

    @ViewBuilder private var titleView: some View {
        let text = Text(verbatim: notice.title)
            .clFont(.headline)
            .foregroundStyle(CLColor.ink)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
        if let link = notice.link {
            Button { onOpen(link) } label: { text }
                .buttonStyle(.plain)
                .accessibilityHint("Opens it")
        } else {
            text
        }
    }
}

/// The eve's line in Cap's place: he is quiet today, and the other exams wait until after this one.
struct TodayQuietLine: View {
    let text: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            CapFace(size: 36)
            Text(verbatim: text)
                .clFont(.subheadline)
                .foregroundStyle(CLColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .clCard(padding: 14, flat: true)
        .accessibilityElement(children: .combine)
    }
}
