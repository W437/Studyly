import SwiftUI

/// Settings: who you are and your plan at the top, then every page, each row saying where it stands now.
struct SettingsView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let _ = app.revision
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ProfileHeader()
                    .padding(.top, 6)
                group("You", [.account, .subscription], squad: true)
                group("Studying", [.study, .notifications])
                group("Privacy and access", [.aiPrivacy, .accessibility, .appearance])
                #if DEBUG
                group("More", [.data, .about, .debug])
                #else
                group("More", [.data, .about])
                #endif
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

    private func group(_ title: LocalizedStringResource, _ pages: [SettingsPage], squad: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            CLSectionHeader(title: title)
            CLList {
                ForEach(pages) { page in
                    NavigationLink(value: Route.settingsPage(page)) {
                        CLRow(icon: page.icon, tint: page.tint, title: page.title, subtitle: .verbatim(SettingsSummary.line(page, app: app)))
                    }
                    .buttonStyle(.pressable)
                }
                if squad {
                    NavigationLink(value: Route.squad) {
                        CLRow(icon: "person.3.fill", tint: .mint, title: "Squad", subtitle: .verbatim(SettingsSummary.squadLine(app: app)))
                    }
                    .buttonStyle(.pressable)
                }
            }
        }
    }
}

/// The name, an initials avatar and the plan, with Go Pro for the free plan.
struct ProfileHeader: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let name = app.settings.firstName.trimmingCharacters(in: .whitespaces)
        let plan = app.purchases.plan
        // Go Pro beside the name; under it at the accessibility sizes.
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 14))
        layout {
            NavigationLink(value: Route.settingsPage(.account)) {
                HStack(spacing: 14) {
                    InitialsAvatar(name: name)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(name.isEmpty ? "Add your name" : name)
                            .clFont(.title3)
                            .foregroundStyle(CLColor.ink)
                            .lineLimit(2)
                        CLPill(text: plan == .free ? "Free plan" : .verbatim(plan.displayName), tone: Self.tone(plan),
                               systemImage: plan == .free ? nil : "sparkles")
                        if let email = app.account.email, app.account.isSignedIn {
                            Text(email).clFont(.footnote).foregroundStyle(CLColor.ink2).lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .accessibilityLabel(Text("\(name.isEmpty ? "No name yet" : name), \(plan == .free ? "free plan" : plan.displayName + " plan")"))
            .accessibilityHint(Text("Opens your account"))
            if plan == .free {
                Button("Go Pro") {
                    CLHaptics.tap()
                    app.router.present(.paywall(.settings))
                }
                .buttonStyle(.cl(.primary, size: .small, fullWidth: typeSize.isAccessibilitySize))
            }
        }
        .clCard()
    }

    static func tone(_ plan: Plan) -> CLPill.Tone {
        switch plan {
        case .free: .neutral
        case .pro: .tangerine
        case .squad: .mint
        case .pass: .sun
        }
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
        case .accessibility: "Accessibility"
        case .appearance: "Appearance"
        case .data: "Your data"
        case .about: "About"
        case .debug: "Debug"
        case .feelLab: "Feel lab"
        }
    }

    var icon: String {
        switch self {
        case .account: "person.crop.circle"
        case .subscription: "sparkles"
        case .study: "target"
        case .notifications: "bell.badge"
        case .aiPrivacy: "lock.shield"
        case .accessibility: "accessibility"
        case .appearance: "circle.lefthalf.filled"
        case .data: "square.and.arrow.up.on.square"
        case .about: "info.circle"
        case .debug: "ladybug"
        case .feelLab: "waveform"
        }
    }

    var tint: CourseColor {
        switch self {
        case .account, .aiPrivacy: .sky
        case .subscription: .tangerine
        case .study: .mint
        case .notifications: .rose
        case .accessibility, .appearance: .sun
        case .data, .about, .debug, .feelLab: .capy
        }
    }
}

/// The line under each row of Settings: where that page stands now.
@MainActor
enum SettingsSummary {
    static func line(_ page: SettingsPage, app: AppModel) -> String {
        let s = app.settings
        switch page {
        case .account:
            if app.config.aiMode == .local { return "On this iPhone only" }
            if app.account.isSignedIn { return app.account.email ?? "Signed in with Apple" }
            return "Sign in to keep a copy in your account"
        case .subscription:
            return planLine(app: app)
        case .study:
            let reminder = s.reminderMinutes.map { "reminder at \(QuizContent.timeString(minutes: $0))" } ?? "no reminder"
            return "\(s.dailyMinutes) min a day, \(reminder)"
        case .notifications:
            return s.reminderMinutes == nil ? "Exam countdowns only" : "Daily reminder, exam countdowns"
        case .aiPrivacy:
            if !app.ai.cloudAvailableInThisBuild { return "Everything on this iPhone" }
            guard app.hasCloudConsent else { return "Cloud AI off" }
            return s.sendPhotos ? "Cloud AI on, page photos on" : "Cloud AI on, page photos off"
        case .accessibility:
            var on: [String] = []
            if s.dyslexicFont { on.append("dyslexia-friendly font") }
            if s.readAloud { on.append("read aloud") }
            if !s.sounds { on.append("sounds off") }
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
        case .data:
            return "Export or delete"
        case .about:
            return "Version \(AboutInfo.version)"
        case .debug:
            return "Harness routes, onboarding, demo data"
        case .feelLab:
            return "Every sound and haptic, on each palette"
        }
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
        case .aiPrivacy: AIPrivacyPage()
        case .accessibility: AccessibilityPage()
        case .appearance: AppearancePage()
        case .data: DataPage()
        case .about: AboutPage()
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
