import SwiftUI

/// Settings ▸ AI and privacy: the switches (Cloud AI, through the consent sheet; page photos, its own switch; hints
/// first), what this iPhone can do by itself, the free limits, what is sent and to whom (notes never train models),
/// and deleting the AI data the server keeps.
///
/// Harness: `CRAMLESS_CONSENT=0` shows Cloud AI off; `CRAMLESS_AGE=teen|under13` an account under 18 or under 13.
struct AIPrivacyPage: View {
    @Environment(AppModel.self) private var app
    @State private var quota: QuotaStatus?
    @State private var confirmingDelete = false
    @State private var deleting = false

    private var ai: AIRouter { app.ai }
    private var isChild: Bool { app.settings.ageBand == .under13 }

    var body: some View {
        let s = app.settings
        let consent = app.hasCloudConsent
        SettingsScroll(title: "AI and privacy") {
            SettingsGroup(title: "Cloud AI", footer: footer(consent: consent)) {
                SettingsToggleRow(
                    title: "Use Cloud AI",
                    subtitle: "Better questions from your pages, careful grading of answers in your own words, and Cap explaining in its own words.",
                    isOn: Binding(get: { consent }, set: setCloud),
                    hintOn: "Asks first. Then your questions to Cap go to \(AIConsent.processor) through Capling's server, with the notes of the course (the text of your pages and lectures, the cards of decks you imported and the names of what you added), the passages it finds in any of your courses when you ask it to look through your notes, answers you type or say and the names of your courses, topics and exams.",
                    hintOff: "Stops sending anything to Cloud AI. Capling keeps working on this iPhone.",
                    disabledReason: cloudDisabledReason)
                SettingsToggleRow(
                    title: "Send page photos",
                    subtitle: "For handwriting, math and diagrams. Photos of the pages you scan go with their text. Needs Cloud AI.",
                    isOn: Binding(get: { consent && s.sendPhotos }, set: setPhotos),
                    hintOn: "Asks first. Then photos of the pages you scan, made smaller, go to Cloud AI with their text.",
                    hintOff: "Stops sending page photos. Their text still goes while Cloud AI is on.",
                    disabledReason: cloudDisabledReason)
            }

            SettingsGroup(title: "Cap, your tutor") {
                SettingsToggleRow(
                    title: "Hints first",
                    subtitle: "Cap asks a guiding question before it explains. Just explain is one tap away in any chat.",
                    isOn: Binding(get: { s.effectiveTutorMode == .hints }, set: { app.setTutorMode($0 ? .hints : .explain) }),
                    hintOn: "Cap asks a question before it explains.",
                    hintOff: "Cap explains straight away.",
                    disabledReason: s.isMinor ? "Always on for accounts under 18, so Cap helps you work it out." : nil)
            }

            CLSectionHeader(title: "On this iPhone")
            VStack(spacing: 0) {
                // While the build keeps Apple's model off there is nothing to report about it.
                if deviceTierShown {
                    SettingsInfoCard(icon: "iphone", tint: deviceReady ? .mint : .sky,
                                     title: deviceReady ? "Apple Intelligence is ready" : "This iPhone's own AI",
                                     text: deviceText)
                    Rectangle().fill(CLColor.hairline).frame(height: 0.5).padding(.leading, 62)
                }
                SettingsInfoCard(icon: "text.book.closed", tint: .sky, title: "Offline rules, always",
                                 text: "Questions, checks of fill-ins and choices, and Cap's answers from your notes, with no network and no AI. They never count against a limit. Answers in your own words you mark yourself, unless an AI is there to check them.")
            }
            .background(CLColor.surface, in: RoundedRectangle(cornerRadius: CLRadius.list, style: .continuous))
            .shadow(color: CLColor.night.opacity(0.05), radius: 1, y: 1)
            .shadow(color: CLColor.night.opacity(0.06), radius: 12, y: 8)

            QuotaCard(status: quota ?? ai.quotaStatus)

            CLSectionHeader(title: "What's sent, and to whom")
            VStack(spacing: 0) {
                SettingsInfoCard(icon: "doc.text", title: "Only with Cloud AI on",
                                 text: "Your questions to Cap, and with each one the notes of the course Cap is answering from (every course, if you chose All courses): the text of your pages and lectures, the cards of decks you imported and the names of what you added. All of it when it's short, otherwise the parts that fit your question. When you ask Cap to look through your notes, the passages it finds in any of your courses go too. Also answers you type or say when they're graded (the words, never your voice). For Cap's tools it also sees the names of your courses, topics and exams, your exam dates, how ready you are, which topics are fading and how many cards are due; if you ask it to research online, that topic is searched on trusted study sites. Page photos only with their own switch.")
                divider
                SettingsInfoCard(icon: "server.rack", title: "\(AIConsent.processor), through Capling's server",
                                 text: "Requests go to \(AIConsent.processor) through our own server, never straight from your phone to an AI company. Our server doesn't keep what you send.")
                divider
                SettingsInfoCard(icon: "hand.raised.fill", tint: .mint, title: "Never used for training",
                                 text: "Your notes and answers are never used to train AI models.")
                divider
                SettingsInfoCard(icon: "list.bullet.rectangle", tint: .sun, title: "What our server keeps",
                                 text: "A log of your AI requests, to count the free limits. Not your notes, answers or chats; your chats stay on this iPhone.")
            }
            .background(CLColor.surface, in: RoundedRectangle(cornerRadius: CLRadius.list, style: .continuous))
            .shadow(color: CLColor.night.opacity(0.05), radius: 1, y: 1)
            .shadow(color: CLColor.night.opacity(0.06), radius: 12, y: 8)

            SettingsGroup(title: nil, footer: "Your courses, cards and progress aren't touched.") {
                SettingsActionRow(icon: "trash", title: "Delete AI data", subtitle: "What our server keeps about your AI use",
                                  destructive: true, busy: deleting) {
                    confirmingDelete = true
                }
            }
            .padding(.top, 26)
        }
        .task { quota = await ai.refreshQuota() }
        .confirmationDialog("Delete AI data?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete AI data", role: .destructive, action: deleteAIData)
        } message: {
            Text("Deletes the log Capling's server keeps of your AI requests. It never stored your notes or answers. Your courses, cards and progress stay.")
        }
        #if DEBUG
        .onAppear { AskDemo.applyLaunchState(app) }
        #endif
    }

    private var divider: some View {
        Rectangle().fill(CLColor.hairline).frame(height: 0.5).padding(.leading, 62)
    }

    // MARK: Words

    private var cloudDisabledReason: LocalizedStringResource? {
        if isChild { return "Not available for accounts under 13. Everything runs on this iPhone." }
        if !ai.cloudAvailableInThisBuild { return "Not set up in this build. Everything runs on this iPhone." }
        return nil
    }

    private func footer(consent: Bool) -> LocalizedStringResource {
        if !ai.cloudAvailableInThisBuild || isChild { return "Capling still writes questions, grades answers and lets Cap explain, on this iPhone." }
        return consent
            ? "Turn it off any time; nothing more is sent from then on, and Capling keeps working on this iPhone."
            : "Off: everything happens on this iPhone, in less detail. You'll be asked before anything is sent."
    }

    private var deviceReady: Bool { ai.onDeviceCapability.availability.isAvailable }

    private var deviceTierShown: Bool { ai.onDeviceCapability.availability != .unavailable(.disabledByBuild) }

    private var deviceText: LocalizedStringResource {
        switch ai.onDeviceCapability.availability {
        case .available:
            "Short questions, quick grades and Cap's short answers can run on this iPhone: private, free and offline."
        case .unavailable(let reason):
            .verbatim(reason.message)
        }
    }

    // MARK: Actions

    private func setCloud(_ on: Bool) {
        if on {
            app.router.present(.consent(.cloudAI(feature: "Write better questions, grade answers carefully and let Cap explain")))
        } else {
            app.withdrawCloudAI()
            CLHaptics.commit()
            app.router.toast("Cloud AI is off. Nothing more is sent.", systemImage: "lock.fill", tone: .neutral)
        }
    }

    private func setPhotos(_ on: Bool) {
        if on {
            app.router.present(.consent(.photos))
        } else {
            app.setSendPhotos(false)
            app.router.toast("Page photos stay on this iPhone.", systemImage: "photo", tone: .neutral)
        }
    }

    private func deleteAIData() {
        deleting = true
        Task {
            do {
                try await app.deleteAIData()
                CLHaptics.commit()
                app.router.toast("AI data deleted", systemImage: "trash")
            } catch RelayError.notConfigured {
                app.router.toast("Nothing to delete: this build never sends anything to Cloud AI.", systemImage: "info.circle", tone: .neutral)
            } catch {
                app.router.toast(RelayError.message(for: error).map { .verbatim($0) } ?? "Couldn't delete it. Try again.", systemImage: "exclamationmark.triangle.fill", tone: .warning)
            }
            deleting = false
        }
    }
}

/// The free limits as meters ("AI scans: 1 of 3 this week"), or "Unlimited" on a paid plan.
struct QuotaCard: View {
    let status: QuotaStatus

    // What never counts: the offline rules, and Apple's model only while the build has it on (`AIBuild.onDeviceModelEnabled`).
    private static var freeFootnote: LocalizedStringResource {
        AIBuild.onDeviceModelEnabled
            ? "Only Cloud AI counts. Your iPhone's own AI and the offline rules are free and never do. Days reset at midnight, weeks on Monday."
            : "Only Cloud AI counts. The offline rules are free and never do. Days reset at midnight, weeks on Monday."
    }

    private static var paidFootnote: LocalizedStringResource {
        AIBuild.onDeviceModelEnabled
            ? "No counted limits. A day with a lot of Cloud AI pauses it until midnight; your iPhone's own AI and the offline rules never pause."
            : "No counted limits. A day with a lot of Cloud AI pauses it until midnight; the offline rules never pause."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CLSectionHeader(title: status.plan.isPaid ? "Your AI" : "Free limits")
            VStack(alignment: .leading, spacing: 14) {
                ForEach(status.meters, id: \.key) { meter in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(Self.name(meter.key)).clFont(.bodyEmphasis).foregroundStyle(CLColor.ink)
                            Spacer()
                            Text(Self.usage(meter)).clFont(.subheadline).foregroundStyle(CLColor.ink2)
                        }
                        if let limit = meter.limit, limit > 0 {
                            let share = Double(meter.used) / Double(limit)
                            CLBar(value: min(1, share), color: share >= 1 ? CLColor.rose : share >= 0.7 ? CLColor.sun : CLColor.sky)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("\(Self.name(meter.key)): \(Self.usage(meter))"))
                }
                if !status.plan.isPaid {
                    Text(Self.freeFootnote)
                        .clFont(.footnote)
                        .foregroundStyle(CLColor.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    // Not "unlimited": a day with a lot of Cloud AI (a cram night) reaches a cost limit that starts again at midnight.
                    Text(Self.paidFootnote)
                        .clFont(.footnote)
                        .foregroundStyle(CLColor.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .clCard()
        }
    }

    static func name(_ key: QuotaMeter.Key) -> String {
        switch key {
        case .scans: "AI scans"
        case .grades: "Graded answers"
        case .tutor: "Answers from Cap"
        case .lectures: "Lecture notes"
        }
    }

    static func usage(_ meter: QuotaMeter) -> String {
        let period = meter.period == .day ? "today" : "this week"
        guard let limit = meter.limit else { return meter.used == 0 ? "Unlimited" : "\(meter.used) \(period), unlimited" }
        return "\(min(meter.used, limit)) of \(limit) \(period)"
    }
}
