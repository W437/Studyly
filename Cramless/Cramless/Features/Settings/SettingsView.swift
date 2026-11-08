import SwiftUI

/// Settings: who you are, then eight rows, each saying where that page stands now. The plan is one row among them; Squad, Help, your data
/// and About sit one level down (Subscription and More).
struct SettingsView: View {
    @Environment(AppModel.self) private var app

    /// The rows, in four groups: you and your plan, how you study and hear from Capling, how the app works for you, and the rest.
    static let rows: [[SettingsPage]] = [[.account, .subscription], [.study, .notifications],
                                         [.aiPrivacy, .accessibility, .appearance], [.more]]

    var body: some View {
        let _ = app.revision
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ProfileHeader()
                    .padding(.top, 6)
                ForEach(Self.rows, id: \.self) { pages in
                    SettingsLinkList(pages: pages)
                }
            }
            .padding(.horizontal, CLSpace.gutter)
            .padding(.bottom, 40)
            .frame(maxWidth: CLMetrics.readableWidth)
            .frame(maxWidth: .infinity)
        }
        .clScreenBackground()
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        #if DEBUG
        .onAppear { AskDemo.applyLaunchState(app) }
        #endif
    }
}

/// Settings pages as rows of one card, each with the line that says where it stands now.
struct SettingsLinkList: View {
    let pages: [SettingsPage]

    @Environment(AppModel.self) private var app

    var body: some View {
        CLList {
            ForEach(pages) { page in
                NavigationLink(value: Route.settingsPage(page)) {
                    CLRow(icon: page.icon, tint: page.tint, title: page.title,
                          subtitle: SettingsSummary.line(page, app: app).map { .verbatim($0) })
                }
                .buttonStyle(.pressable)
            }
        }
    }
}

/// The name and an initials avatar (with the email once signed in); it opens Account.
struct ProfileHeader: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let name = app.settings.firstName.trimmingCharacters(in: .whitespaces)
        NavigationLink(value: Route.settingsPage(.account)) {
            HStack(spacing: 14) {
                InitialsAvatar(name: name)
                VStack(alignment: .leading, spacing: 3) {
                    Text(name.isEmpty ? "Add your name" : name)
                        .clFont(.title3)
                        .foregroundStyle(CLColor.ink)
                        .lineLimit(2)
                    if let email = app.account.email, app.account.isSignedIn {
                        Text(email).clFont(.footnote).foregroundStyle(CLColor.ink2).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                CLChevron()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .clCard()
        .accessibilityLabel(name.isEmpty ? Text("No name yet") : Text(verbatim: name))
        .accessibilityHint(Text("Opens your account"))
    }
}

extension SettingsPage {
    var title: LocalizedStringResource {
        switch self {
        case .account: "Account"
        case .subscription: "Subscription"
        case .study: "Study"
        case .notifications: "Notifications"
        case .aiPrivacy: "AI and privacy"
        case .assistant: "What Cap can do"
        case .accessibility: "Accessibility"
        case .appearance: "Appearance"
        case .help: "Help"
        case .data: "Your data"
        case .about: "About"
        case .debug: "Debug"
        case .feelLab: "Feel lab"
        case .more: "More"
        case .retention: "How sure you'll be"
        case .hiddenTips: "Hidden tips"
        case .fontLicences: "Font licences"
        }
    }

    var icon: String {
        switch self {
        case .account: "person.crop.circle"
        case .subscription: "sparkles"
        case .study: "target"
        case .notifications: "bell.badge"
        case .aiPrivacy: "lock.shield"
        case .assistant: "wand.and.stars"
        case .accessibility: "accessibility"
        case .appearance: "circle.lefthalf.filled"
        case .help: "questionmark.bubble"
        case .data: "square.and.arrow.up.on.square"
        case .about: "info.circle"
        case .debug: "ladybug"
        case .feelLab: "waveform"
        case .more: "ellipsis"
        case .retention: "chart.line.uptrend.xyaxis"
        case .hiddenTips: "eye.slash"
        case .fontLicences: "textformat"
        }
    }

    var tint: CourseColor {
        switch self {
        case .account, .aiPrivacy: .sky
        case .assistant: .tangerine
        case .subscription: .tangerine
        case .study, .retention: .mint
        case .notifications: .rose
        case .accessibility, .appearance: .sun
        case .help: .sky
        case .data, .about, .debug, .feelLab, .more, .hiddenTips, .fontLicences: .capy
        }
    }

    /// The page a deep link or a harness route opens first on the way to this one, so Back goes where a tap would have come from.
    var parent: SettingsPage? {
        switch self {
        case .help, .data, .about, .retention, .debug: .more
        case .fontLicences: .about
        case .hiddenTips: .study
        case .feelLab: .debug
        case .account, .subscription, .study, .notifications, .aiPrivacy, .assistant, .accessibility, .appearance, .more: nil
        }
    }

    /// The pages from Settings' own root to this one, this one last.
    var trail: [SettingsPage] { (parent?.trail ?? []) + [self] }
}

/// The line under each row of Settings: where that page stands now.
@MainActor
enum SettingsSummary {
    static func line(_ page: SettingsPage, app: AppModel) -> String? {
        let s = app.settings
        switch page {
        case .account:
            if app.config.aiMode == .local { return String(localized: "On this iPhone only") }
            if app.account.isSignedIn { return app.account.email ?? String(localized: "Signed in with Apple") }
            return String(localized: "Sign in to keep a copy in your account")
        case .subscription:
            return planLine(app: app)
        case .study:
            return studyLine(s, calendar: app.calendar)
        case .notifications:
            guard let minutes = s.reminderMinutes else { return String(localized: "Exam countdowns only") }
            return String(localized: "Reminder at \(QuizContent.timeString(minutes: minutes)), exam countdowns")
        case .aiPrivacy:
            if !app.ai.cloudAvailableInThisBuild { return "Everything on this iPhone" }
            guard app.hasCloudConsent else { return "Cloud AI off" }
            return s.sendPhotos ? "Cloud AI on, page photos on" : "Cloud AI on, page photos off"
        case .accessibility:
            var on: [String] = []
            if s.dyslexicFont { on.append("dyslexia-friendly font") }
            if s.readAloud { on.append("read aloud") }
            if !s.sounds || s.quietMode { on.append("sounds off") }
            if !s.capMoves { on.append("Cap still") }
            if !s.capTalks { on.append("Cap quiet") }
            if !s.haptics { on.append("haptics off") }
            return on.isEmpty ? "Font, read aloud, sounds, haptics" : Lexicon.capitalizedFirst(on.joined(separator: ", "))
        case .appearance:
            switch s.theme {
            case .system: return "Matches your iPhone"
            case .light: return "Light"
            case .dark: return "Dark"
            }
        case .more:
            return String(localized: "Help, your data and About")
        case .help:
            return String(localized: "Write to us")
        case .data:
            return String(localized: "Export or delete")
        case .about:
            return String(localized: "The version, terms and privacy")
        case .retention:
            return String(localized: RetentionPage.bandName(s.targetRetention))
        case .hiddenTips:
            return hiddenTipsLine(s)
        case .debug:
            return "Harness routes, onboarding, demo data"
        // What Cap can do is inside AI and privacy; the Feel lab and the licences have rows of their own on their parent pages.
        case .assistant, .feelLab, .fontLicences:
            return nil
        }
    }

    /// "15 min a day", with lighter days and Quiet mode when they're on.
    static func studyLine(_ s: AppSettings, calendar: Calendar) -> String {
        var parts = [String(localized: "\(s.dailyMinutes) min a day")]
        if !s.easyDays.isEmpty {
            let days = s.easyDays.sorted().compactMap { day in
                calendar.shortStandaloneWeekdaySymbols.indices.contains(day - 1) ? calendar.shortStandaloneWeekdaySymbols[day - 1] : nil
            }
            parts.append(String(localized: "lighter on \(days.formatted(.list(type: .and)))"))
        }
        if s.quietMode { parts.append(String(localized: "Quiet mode on")) }
        return parts.joined(separator: ", ")
    }

    /// The kinds of Cap's cards switched off, by name ("Mix-ups and Busy days"); nil when none are.
    static func hiddenTipsLine(_ s: AppSettings) -> String? {
        let names = HiddenTipsPage.hidden(s).map { String(localized: NoticeContent.switchTitle($0)) }
        return names.isEmpty ? nil : names.formatted(.list(type: .and))
    }

    static func planLine(app: AppModel) -> String {
        let e = app.purchases.entitlement
        let short = Date.FormatStyle.dateTime.month(.abbreviated).day()
        switch e.plan {
        case .free: return "Free plan"
        case .pass: return e.expiresAt.map { "Exam Pass until \($0.formatted(short))" } ?? "Exam Pass"
        case .pro, .squad:
            let name = e.plan == .squad ? "Squad" : "Pro"
            guard let end = e.expiresAt else { return name }
            return e.isFreeTrial ? "\(name), free week ends \(end.formatted(short))" : "\(name), renews \(end.formatted(short))"
        }
    }

    static func squadLine(app: AppModel) -> String {
        if app.purchases.allows(.squadSeats) { return "You and up to 3 friends" }
        if app.purchases.plan == .squad { return "On a friend's Squad" }
        return "Study with 3 friends for less"
    }
}

/// Every Settings page, by case.
struct SettingsPageView: View {
    let page: SettingsPage

    var body: some View {
        switch page {
        case .account: AccountPage()
        case .subscription: SubscriptionPage()
        case .study: StudyPage()
        case .notifications: NotificationsPage()
        case .aiPrivacy, .assistant: AIPrivacyPage()
        case .accessibility: AccessibilityPage()
        case .appearance: AppearancePage()
        case .help: HelpPage()
        case .data: DataPage()
        case .about: AboutPage()
        case .more: MorePage()
        case .retention: RetentionPage()
        case .hiddenTips: HiddenTipsPage()
        case .fontLicences: FontLicencesPage()
        case .debug:
            #if DEBUG
            DebugPage()
            #else
            SettingsScroll(title: "Debug") {
                Text("Not in this build.").clFont(.body).foregroundStyle(CLColor.ink2).padding(.top, 20)
            }
            #endif
        case .feelLab:
            #if DEBUG
            FeelLab()
            #else
            SettingsScroll(title: "Feel lab") {
                Text("Not in this build.").clFont(.body).foregroundStyle(CLColor.ink2).padding(.top, 20)
            }
            #endif
        }
    }
}
