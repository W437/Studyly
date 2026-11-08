import SwiftUI

/// Settings ▸ More: how sure you'll be, then Help, your data and About (and Debug in DEBUG builds).
///
/// Harness: `CRAMLESS_ROUTE=settings:more`.
struct MorePage: View {
    var body: some View {
        SettingsScroll(title: "More") {
            VStack(spacing: 18) {
                SettingsLinkList(pages: [.retention])
                SettingsLinkList(pages: [.help, .data, .about])
                #if DEBUG
                SettingsLinkList(pages: [.debug])
                #endif
            }
            .padding(.top, 14)
        }
    }
}

/// Settings ▸ More ▸ How sure you'll be: the target retention (85–95%), how likely you are to still know a question when it comes back.
/// The value is written once the slider rests, so the plan is rebuilt once.
///
/// Harness: `CRAMLESS_ROUTE=settings:retention`.
struct RetentionPage: View {
    @Environment(AppModel.self) private var app
    /// The slider's value while it moves; written to the settings once it rests.
    @State private var retention: Double = 0.9

    var body: some View {
        SettingsScroll(title: "How sure you'll be") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Target").clFont(.bodyEmphasis).foregroundStyle(CLColor.ink)
                    Spacer()
                    Text(CLFormat.percent(retention)).clFont(.number(22)).foregroundStyle(CLColor.ink)
                        .contentTransition(.numericText(value: retention))
                }
                Slider(value: $retention, in: 0.85...0.95, step: 0.01)
                    .tint(CLColor.tangerine)
                    // Written once the value rests (a drag or VoiceOver's adjust), so the plan is rebuilt once.
                    .task(id: retention) {
                        try? await Task.sleep(for: .milliseconds(450))
                        guard !Task.isCancelled else { return }
                        commit()
                    }
                    .accessibilityLabel("Target")
                    .accessibilityValue(Text(CLFormat.percent(retention)))
                HStack {
                    Text("Fewer reviews").clFont(.caption).foregroundStyle(CLColor.ink3)
                    Spacer()
                    Text("More reviews").clFont(.caption).foregroundStyle(CLColor.ink3)
                }
                .accessibilityHidden(true)
                Text(Self.retentionText(retention))
                    .clFont(.subheadline)
                    .foregroundStyle(CLColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .animation(CLMotion.fade, value: Self.band(retention))
            }
            .clCard()
            .padding(.top, 14)
        }
        .onAppear { retention = app.settings.targetRetention }
    }

    private func commit() {
        let value = (retention * 100).rounded() / 100
        if value != app.settings.targetRetention { app.settings.targetRetention = value }
    }

    static func band(_ value: Double) -> Int { value < 0.885 ? 0 : value <= 0.915 ? 1 : 2 }

    /// The band in a few words, for the row on More (no second percentage beside readiness's).
    static func bandName(_ value: Double) -> LocalizedStringResource {
        switch band(value) {
        case 0: "Fewer reviews"
        case 1: "The sweet spot for most people"
        default: "More reviews, for exam week"
        }
    }

    /// The target in plain words.
    static func retentionText(_ value: Double) -> String {
        let percent = Int((value * 100).rounded())
        let base = "Each question comes back when you're about \(percent)% likely to still know it."
        switch band(value) {
        case 0: return base + " Fewer reviews each day, and you'll forget a little more in between."
        case 1: return base + " The sweet spot for most people: about 90%."
        default: return base + " More reviews each day for a little more certainty. Worth it in exam week."
        }
    }
}

/// Settings ▸ Study ▸ Hidden tips: the kinds of Cap's cards turned off with "Don't show these" on Today, each with "Show again". Study shows
/// its row only while something is hidden.
///
/// Harness: `CRAMLESS_HIDDEN_TIPS=mixUp,busyDay` (`NoticeKind` raw values) hides those kinds at launch; `CRAMLESS_ROUTE=settings:hiddenTips`.
struct HiddenTipsPage: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dynamicTypeSize) private var typeSize

    /// The kinds switched off, in the order Cap deals them.
    static func hidden(_ settings: AppSettings) -> [NoticeKind] {
        NoticeKind.live.filter { !settings.notices.allows($0) }
    }

    var body: some View {
        let hidden = Self.hidden(app.settings)
        SettingsScroll(title: "Hidden tips") {
            if hidden.isEmpty {
                Text("Nothing is hidden. Cap brings up every kind of tip on Today.")
                    .clFont(.body)
                    .foregroundStyle(CLColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 20)
                    .padding(.horizontal, 6)
                    .transition(.opacity)
            } else {
                SettingsGroup(footer: "Cap won't bring these up on Today.") {
                    ForEach(hidden, id: \.self) { kind in row(kind) }
                }
                .padding(.top, 14)
            }
        }
        .animation(CLMotion.settle, value: hidden)
    }

    private func row(_ kind: NoticeKind) -> some View {
        let title = NoticeContent.switchTitle(kind)
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            Text(title)
                .clFont(.bodyEmphasis)
                .foregroundStyle(CLColor.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Show again") {
                CLHaptics.tap()
                app.setNoticeKind(kind, on: true)
            }
            .buttonStyle(.cl(.soft, size: .small, fullWidth: false))
            .accessibilityLabel(Text("Show \(String(localized: title)) again"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: CLMetrics.rowMinHeight)
    }
}
