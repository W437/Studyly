import SwiftUI

/// Every badge, earned ones in colour and the rest as silhouettes with how far along they are. A tap on one opens its sheet.
/// Pushed from Progress ▸ Badges ▸ See all (`Route.badges`).
struct BadgesView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let _ = app.revision
        let statuses = app.badgeStatuses()
        let earned = statuses.filter(\.isEarned).count
        let columns = [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 150 : 96), spacing: 12, alignment: .top)]
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(BadgeCopy.count(earned: earned, of: statuses.count))
                    .clFont(.subheadlineEmphasis)
                    .foregroundStyle(CLColor.ink2)
                    .padding(.top, 8)
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(statuses) { status in
                        Button {
                            CLHaptics.tap()
                            app.router.present(.badge(status.badge))
                        } label: {
                            BadgeCell(status: status, calendar: app.calendar)
                        }
                        .buttonStyle(.pressable)
                    }
                }
            }
            .padding(.horizontal, CLSpace.gutter)
            .padding(.bottom, 40)
        }
        .clScreenBackground()
        .navigationTitle("Badges")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A medal with its name and, under it, when it was earned or how far along it is.
struct BadgeCell: View {
    let status: BadgeStatus
    let calendar: Calendar
    var medalSize: CGFloat = 84
    /// The line under the name: when it was earned, or how far along it is. Progress's row leaves it out (the medal and the
    /// name are enough there; the badge's own sheet says the rest).
    var showsDetail = true

    var body: some View {
        VStack(spacing: 8) {
            BadgeMedal(badge: status.badge, earned: status.isEarned, size: medalSize)
            Text(status.badge.title)
                .clFont(.footnoteEmphasis)
                .foregroundStyle(status.isEarned ? CLColor.ink : CLColor.ink3)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
            if showsDetail {
                Text(detail)
                    .clFont(.caption)
                    .foregroundStyle(CLColor.ink3)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(status.badge.title))
        .accessibilityValue(status.isEarned ? Text("Earned") : Text(BadgeCopy.progress(status.progress)))
        .accessibilityHint(Text(status.badge.blurb))
        .accessibilityAddTraits(.isButton)
    }

    private var detail: LocalizedStringResource {
        if let date = status.earnedAt { return BadgeCopy.earned(on: date, calendar: calendar) }
        if status.isEarned { return "Earned" }
        return BadgeCopy.progress(status.progress)
    }
}

/// One badge up close: a big medal that follows the phone's tilt, what it is for, and when it was earned or how far along it
/// is. The sheet is as tall as its content.
struct BadgeSheet: View {
    let badge: Badge

    @Environment(AppModel.self) private var app
    @State private var contentHeight: CGFloat = 460

    var body: some View {
        let status = app.badgeStatuses().first { $0.badge == badge }
        let earned = status?.isEarned ?? false
        ScrollView {
            VStack(spacing: 14) {
                TiltingMedal(badge: badge, earned: earned, size: 200)
                    .padding(.top, 26)
                    .padding(.bottom, 6)
                Text(badge.title)
                    .clFont(.brandHeading(28))
                    .foregroundStyle(CLColor.ink)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(badge.blurb)
                    .clFont(.callout)
                    .foregroundStyle(CLColor.ink2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if let status { footer(status) }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .presentationDetents([.height(contentHeight + 16)])
        .presentationDragIndicator(.visible)
        .presentationBackground(CLColor.background)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func footer(_ status: BadgeStatus) -> some View {
        if let date = status.earnedAt {
            CLPill(text: BadgeCopy.earned(on: date, calendar: app.calendar), tone: .mint, systemImage: "checkmark")
        } else if status.isEarned {
            CLPill(text: "Earned", tone: .mint, systemImage: "checkmark")
        } else {
            VStack(spacing: 8) {
                CLBar(value: status.progress.fraction, color: CLColor.tangerine, height: 8)
                    .frame(maxWidth: 220)
                Text(BadgeCopy.progress(status.progress))
                    .clFont(.footnoteEmphasis)
                    .foregroundStyle(CLColor.ink3)
            }
        }
    }
}
