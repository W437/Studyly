import DeclaredAgeRange
import SwiftUI

/// Settings ▸ AI and privacy, which is also "What Cap can do" (`SettingsPage.assistant` opens it). One page, in this order: the Cloud AI
/// switch (through the consent sheet) and the page-photos switch; one switch that lets Cap add cards, notes and exams without asking
/// (locked on ask-first under 18) and web research (absent under 18); the free limits; "What's sent" (the consent sheet's full text,
/// `WhatsSentSheet`); everything Cap has added, with Undo; and deleting the AI data the server keeps. Hints first is chosen in each chat.
///
/// Harness: `CRAMLESS_CONSENT=0` shows Cloud AI off; `CRAMLESS_AGE=teen|under13|notShared` an account under 18, under 13, or one iOS
/// gave no range for (with the row that asks again); `CRAMLESS_SCROLL=added` scrolls to "Added by Cap" (`CRAMLESS_ASSISTANT_SEED=1`
/// fills it); `CRAMLESS_CONSENT_DETAILS=1` opens "What's sent".
struct AIPrivacyPage: View {
    @Environment(AppModel.self) private var app
    @State private var quota: QuotaStatus?
    @State private var confirmingDelete = false
    @State private var deleting = false
    @State private var sharingAge = false
    @State private var showsWhatsSent = false
    @Environment(\.requestAgeRange) private var requestAgeRange

    private var ai: AIRouter { app.ai }
    private var isChild: Bool { app.settings.ageBand == .under13 }

    var body: some View {
        let _ = app.revision
        let s = app.settings
        let consent = app.hasCloudConsent
        SettingsScroll(title: "AI and privacy") {
            SettingsGroup(title: "Cloud AI", footer: footer(consent: consent)) {
                SettingsToggleRow(
                    title: "Use Cloud AI",
                    subtitle: "Better questions from your pages, and careful grading of answers in your own words.",
                    isOn: Binding(get: { consent }, set: setCloud),
                    hintOn: "Asks first. Then what you add, your questions to Cap with the notes of the course (the text of your pages and lectures, the cards of decks you imported and the names of what you added), the passages it finds in any of your courses when you ask it to look through your notes, answers you type or say and the names of your courses, topics and exams go to \(AIConsent.processor) through Capling's server.",
                    hintOff: "Stops sending anything to Cloud AI. Capling keeps working on this iPhone.",
                    disabledReason: cloudDisabledReason)
                SettingsToggleRow(
                    title: "Send page photos",
                    subtitle: "For handwriting, math and diagrams. Needs Cloud AI.",
                    isOn: Binding(get: { consent && s.sendPhotos }, set: setPhotos),
                    hintOn: "Asks first. Then photos of the pages you scan, made smaller, go to Cloud AI with their text.",
                    hintOff: "Stops sending page photos. Their text still goes while Cloud AI is on.",
                    disabledReason: cloudDisabledReason)
            }

            SettingsGroup(title: "What Cap can do", footer: s.isMinor ? nil : "Anything that changes or deletes what you already have always asks.") {
                SettingsToggleRow(
                    title: "Let Cap add cards, notes and exams without asking",
                    subtitle: s.isMinor ? nil : "Each one shows in the chat with Undo.",
                    isOn: Binding(get: { !s.assistantAuto.isEmpty }, set: { app.setAssistantAutoAll($0) }),
                    hintOn: "Cap adds cards, notes and exams without asking, and you can undo each one.",
                    hintOff: "Cap shows each one and waits for you.",
                    disabledReason: s.isMinor ? "Cap always asks first for accounts under 18." : nil)
                if !s.isMinor {
                    SettingsToggleRow(
                        title: "Research online",
                        subtitle: "Only when you ask, and only from trusted study sites. Part of Pro.",
                        isOn: Binding(get: { s.assistantWeb }, set: { app.setAssistantWeb($0) }),
                        hintOn: "Cap may look things up on trusted study sites when you ask.",
                        hintOff: "Cap won't look anything up online.")
                }
                // iOS gave no range and the person gave no level that vouches for an adult. They may be one: this is their way to say so.
                if s.ageBand == .notShared {
                    SettingsActionRow(icon: "person.crop.circle.badge.checkmark", tint: .sky, title: "Share your age range",
                                      subtitle: "Capling doesn't know your age, so it keeps to the rules for under 18.", busy: sharingAge) {
                        sharingAge = true
                        Task {
                            await AgeRange.refresh(app: app, using: requestAgeRange)
                            sharingAge = false
                        }
                    }
                }
            }

            QuotaCard(status: quota ?? ai.quotaStatus)

            CLList {
                Button {
                    CLHaptics.tap()
                    showsWhatsSent = true
                } label: {
                    CLRow(icon: "doc.text.magnifyingglass", title: "What's sent", subtitle: "To whom, and what our server keeps")
                }
                .buttonStyle(.pressable)
            }
            .padding(.top, 26)

            additions

            SettingsGroup(title: nil, footer: "Your courses, questions and progress aren't touched.") {
                SettingsActionRow(icon: "trash", title: "Delete AI data", subtitle: "What our server keeps about your AI use",
                                  destructive: true, busy: deleting) {
                    confirmingDelete = true
                }
            }
            .padding(.top, 26)
        }
        .task { quota = await ai.refreshQuota() }
        .sheet(isPresented: $showsWhatsSent) {
            WhatsSentSheet(focus: .cloudAI)
                .environment(\.clDyslexicFont, app.settings.dyslexicFont)
        }
        .confirmationDialog("Delete AI data?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete AI data", role: .destructive, action: deleteAIData)
        } message: {
            Text("Deletes the log Capling's server keeps of your AI requests. It never stored your notes or answers. Your courses, questions and progress stay.")
        }
        #if DEBUG
        .onAppear { AskDemo.applyLaunchState(app) }
        .task {
            guard TestHarness.once("CRAMLESS_CONSENT_DETAILS") == "1" else { return }
            try? await nap(900)
            showsWhatsSent = true
        }
        #endif
    }

    // MARK: What Cap has added

    @ViewBuilder private var additions: some View {
        let list = app.assistantAdditions()
        CLSectionHeader(title: "Added by Cap").id("added")
        if list.isEmpty {
            Text("Nothing yet. When Cap adds something, it shows up here with Undo.")
                .clFont(.subheadline)
                .foregroundStyle(CLColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 6)
        } else {
            CLList {
                ForEach(Array(list.prefix(12))) { entry in
                    HStack(spacing: 12) {
                        CLIconBadge(systemImage: entry.step.icon, tint: entry.step.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: entry.step.title).clFont(.bodyEmphasis).foregroundStyle(CLColor.ink).lineLimit(2)
                            Text(verbatim: line(entry.step)).clFont(.footnote).foregroundStyle(CLColor.ink2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Button("Undo") {
                            CLHaptics.commit()
                            app.undoAssistantStep(messageID: entry.messageID, stepID: entry.step.id)
                            app.router.toast("Taken back", systemImage: "arrow.uturn.backward", tone: .neutral)
                        }
                        .buttonStyle(.cl(.ghost, size: .small, fullWidth: false))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(minHeight: CLMetrics.rowMinHeight)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func line(_ step: AssistantStep) -> String {
        var parts = [step.courseName.clNonEmpty].compactMap { $0 }
        if let when = step.appliedAt { parts.append(when.formatted(.dateTime.month(.abbreviated).day().hour().minute())) }
        if step.auto { parts.append(String(localized: "added without asking")) }
        return parts.joined(separator: " · ")
    }

    // MARK: Words

    private var cloudDisabledReason: LocalizedStringResource? {
        if isChild { return "Not available for accounts under 13. Everything runs on this iPhone." }
        if !ai.cloudAvailableInThisBuild { return "Not set up in this build. Everything runs on this iPhone." }
        return nil
    }

    private func footer(consent: Bool) -> LocalizedStringResource? {
        if !ai.cloudAvailableInThisBuild || isChild { return "Capling still writes questions, grades answers and lets Cap explain, on this iPhone." }
        return consent ? nil : "Off: nothing goes to Cloud AI, and Capling does the work on this iPhone, in less detail."
    }

    // MARK: Actions

    private func setCloud(_ on: Bool) {
        if on {
            app.router.present(.consent(.cloudAI(feature: "Write better questions, grade answers carefully and let Cap explain")))
        } else {
            app.withdrawCloudAI()
            CLHaptics.commit()
            app.router.toast("Cloud AI is off. Nothing more goes to it.", systemImage: "lock.fill", tone: .neutral)
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

// MARK: - The choices

extension AppModel {
    /// "Let Cap add cards, notes and exams without asking": one switch for every kind. Locked on ask-first under 18.
    func setAssistantAutoAll(_ on: Bool) {
        guard !settings.isMinor else { return }
        settings.assistant.auto = on ? Set(AssistantAutoKind.allCases) : []
        CLHaptics.select()
    }

    func setAssistantWeb(_ on: Bool) {
        guard !settings.isMinor else { return }
        settings.assistant.webResearch = on
        CLHaptics.select()
    }

    /// A skipped or taken-back draft, asked for again.
    func reopenAssistantStep(messageID: UUID, stepID: String) {
        updateAssistantStep(messageID: messageID, stepID: stepID) { step in
            if step.status == .skipped || step.status == .undone { step.status = .proposed }
        }
    }
}
