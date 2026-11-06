import SwiftUI

/// "Cap noticed": one of Cap's cards (`CapNotice`) at a time, with "1 of N" when more wait behind it, its one action and "Later"
/// (until tomorrow). Today shows the first of `AppModel.todayNotices()`; in Stage 1 they are the open mix-ups.
///
/// DEBUG: `CRAMLESS_TODAY_NOTICES=0|1|2|3` deals that many (see `TodaySnapshot`), `CRAMLESS_TODAY_LATER=<ms>` presses Later that long
/// after launch (`TodayView`).
struct TodayNoticeCard: View {
    let notice: CapNotice
    /// Its place among today's cards, from 1, and how many there are.
    let index: Int
    let total: Int
    var onAction: (CapNotice.Action) -> Void
    var onLater: () -> Void
    var onOpen: (CapNotice.Link) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CapFace(size: 44)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    CLEyebrow(text: "Cap noticed", color: CLColor.tangerineInk)
                    Spacer(minLength: 8)
                    if total > 1 {
                        Text(verbatim: TodayCopy.noticeCount(index, of: total))
                            .clFont(.footnoteEmphasis)
                            .foregroundStyle(CLColor.ink3)
                            .monospacedDigit()
                    }
                }
                .accessibilityHidden(true)
                titleView
                Text(verbatim: notice.detail)
                    .clFont(.subheadline)
                    .foregroundStyle(CLColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                ReflowStack(verticalAlignment: .center, spacing: 6) {
                    if let action = notice.action {
                        Button(action.title) { onAction(action) }
                            .buttonStyle(.cl(.dark, size: .medium, fullWidth: false))
                    }
                    Button("Later", action: onLater)
                        .buttonStyle(.cl(.ghost, size: .medium, fullWidth: false))
                        .accessibilityHint("Cap brings it up tomorrow")
                }
                .padding(.top, 10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .clCard()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: total > 1 ? "\(String(localized: "Cap noticed")), \(TodayCopy.noticeCount(index, of: total))"
                                 : String(localized: "Cap noticed")))
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

/// The eve's line in Cap's place: he is quiet tonight, and the other exams wait until after this one.
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
