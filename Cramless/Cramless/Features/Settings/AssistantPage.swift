import SwiftUI

/// Settings ▸ What Cap can do: Ask Cap drafts flashcards, questions, notes and exams, and looks things up when asked; here is
/// who decides. Everything is ask-first until a switch says otherwise (never for an account under 18), and everything Cap has
/// added is listed with Undo.
///
/// Harness: `CRAMLESS_AGE=teen` shows an account under 18 (every switch locked on ask-first, no web); `CRAMLESS_SCROLL=added`
/// scrolls to "Added by Cap" (with `CRAMLESS_ASSISTANT_SEED=1`, which fills it).
struct AssistantPage: View {
    @Environment(AppModel.self) private var app

    private var minor: Bool { app.settings.isMinor }

    var body: some View {
        let _ = app.revision
        let s = app.settings
        SettingsScroll(title: "What Cap can do") {
            intro
            if !app.hasCloudConsent {
                SettingsGroup(title: nil) {
                    SettingsActionRow(icon: "sparkles", tint: .tangerine, title: "Turn on Cloud AI",
                                      subtitle: "Cap's tools need it. Everything still works on this iPhone without them.") {
                        app.router.present(.consent(.cloudAI(feature: "Let Cap make cards, questions and notes for you")))
                    }
                }
                .padding(.top, 18)
            }

            SettingsGroup(
                title: "Ask first, or let Cap do it",
                footer: minor
                    ? "For accounts under 18 Cap always asks first. You decide what is added."
                    : "Cap always shows what it made. With “Let Cap do it” on, it adds that kind straight away and you can undo it. Anything that changes or deletes something you already have always asks."
            ) {
                ForEach(AssistantAutoKind.allCases, id: \.self) { kind in
                    SettingsToggleRow(
                        title: .verbatim(kind.title),
                        subtitle: .verbatim(minor ? "Asks first." : s.assistant.auto.contains(kind) ? kind.subtitle : "Asks first. Turn on to let Cap add them itself."),
                        isOn: Binding(get: { s.assistantAuto.contains(kind) }, set: { app.setAssistantAuto(kind, $0) }),
                        hintOn: "Cap adds these without asking, and you can undo each one.",
                        hintOff: "Cap shows these and waits for you.",
                        disabledReason: minor ? "Always ask first for accounts under 18." : nil)
                }
            }
            .padding(.top, 18)

            SettingsGroup(
                title: "On the web",
                footer: minor
                    ? "Not available for accounts under 18."
                    : "Only when you ask, and only from trusted study sites: Wikipedia and its sister sites, government and science agencies, open-access journals and free reference sites. What it finds is shown with its sources and is only saved as a note if you say so. Part of Capling Pro."
            ) {
                SettingsToggleRow(
                    title: "Let Cap research online",
                    subtitle: "Ask “Research the Krebs cycle online” and watch Cap read.",
                    isOn: Binding(get: { s.assistantWeb }, set: { app.setAssistantWeb($0) }),
                    hintOn: "Cap may look things up on trusted study sites when you ask.",
                    hintOff: "Cap won't look anything up online.",
                    disabledReason: minor ? "Not available for accounts under 18." : nil)
            }
            .padding(.top, 18)

            additions
        }
        #if DEBUG
        .onAppear { AskDemo.applyLaunchState(app) }
        #endif
    }

    private var intro: some View {
        HStack(alignment: .center, spacing: 12) {
            CapView(.working, size: 70)
            VStack(alignment: .leading, spacing: 4) {
                Text("Cap drafts. You decide.").clFont(.title3).foregroundStyle(CLColor.ink)
                Text("Ask Cap to make flashcards, questions, a note or an exam, and it shows you first. You see what it's doing and you stay in charge.")
                    .clFont(.subheadline)
                    .foregroundStyle(CLColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 8)
    }

    // MARK: What Cap has added

    @ViewBuilder private var additions: some View {
        let list = app.assistantAdditions()
        CLSectionHeader(title: "Added by Cap").id("added")
        if list.isEmpty {
            Text("Nothing yet. When Cap adds something, it shows up here with Undo.")
                .clFont(.subheadline)
                .foregroundStyle(CLColor.ink2)
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
        if step.auto { parts.append(String(localized: "by “Let Cap do it”")) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - The choices

extension AppModel {
    func setAssistantAuto(_ kind: AssistantAutoKind, _ on: Bool) {
        guard !settings.isMinor else { return }
        var s = settings
        if on { s.assistant.auto.insert(kind) } else { s.assistant.auto.remove(kind) }
        settings = s
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
