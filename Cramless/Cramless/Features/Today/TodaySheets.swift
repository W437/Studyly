import SwiftUI

/// "Why these?": why today's session holds what it holds, in three rows at most (`TodayReasons`), with "Study something else" (every
/// course's topics, each with Practice) and a quiet "Got it". A fitted sheet: as tall as what it says.
struct TodayReasonsSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var rows: [TodayReasons.Row] = []

    var body: some View {
        TodayFittedSheet {
            VStack(alignment: .leading, spacing: 18) {
                Text("Why these?")
                    .clFont(.title2)
                    .foregroundStyle(CLColor.ink)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 24)
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(rows) { row in
                        HStack(alignment: .top, spacing: 12) {
                            CLIconBadge(systemImage: row.symbol, tint: .sky, size: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: row.title)
                                    .clFont(.subheadlineEmphasis)
                                    .foregroundStyle(CLColor.ink)
                                if let detail = row.detail {
                                    Text(verbatim: detail)
                                        .clFont(.subheadline)
                                        .foregroundStyle(CLColor.ink2)
                                }
                            }
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                VStack(spacing: 4) {
                    Button {
                        dismiss()
                        CLHaptics.tap()
                        app.router.push(.skyList, on: .today)
                    } label: {
                        Text("Study something else")
                    }
                    .buttonStyle(.cl(.soft))
                    .accessibilityHint("Opens your courses, each topic with Practice")
                    Button("Got it") { dismiss() }
                        .buttonStyle(.cl(.ghost, size: .medium))
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, CLSpace.gutter)
            .padding(.bottom, 20)
        }
        .onAppear { rows = TodayReasons.make(app.todayReasonsInput()) }
    }
}

/// Today's quests up close, from the quests row: the three quests with how far each is, and the week's meter (`TodayQuestsCard`). A
/// fitted sheet.
struct TodayQuestsSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        TodayFittedSheet {
            VStack(spacing: 14) {
                TodayQuestsCard(quests: app.questsToday())
                    .padding(.top, 24)
                Button("Done") { dismiss() }
                    .buttonStyle(.cl(.soft, size: .medium))
            }
            .padding(.horizontal, CLSpace.gutter)
            .padding(.bottom, 20)
        }
    }
}

/// A sheet as tall as its content (scrolls when that is more than the screen), on the page's background.
struct TodayFittedSheet<Content: View>: View {
    @ViewBuilder var content: Content
    @State private var height: CGFloat = 420

    var body: some View {
        ScrollView {
            content
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .presentationDetents([.height(height + 8)])
        .presentationDragIndicator(.visible)
        .presentationBackground(CLColor.background)
    }
}
