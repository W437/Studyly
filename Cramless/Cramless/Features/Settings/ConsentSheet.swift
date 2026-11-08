import SwiftUI

/// Asks before anything goes to Cloud AI. Presented by a screen (as `.consent(reason)`) when a job's outcome
/// carries `AISuggestion.allowCloud` or `.allowPhotos`; the router never presents it. Allow records the consent
/// version (`AIConsent.currentVersion`); the screen then runs the job again, and the router reads the new settings.
///
/// Two lines say it all at a glance: what goes, to whom (OpenAI, through Capling's server) and why; that our server keeps none of it,
/// nothing trains AI, and it can be turned off. "Exactly what's sent" opens the full text (`WhatsSentSheet`, the same one Settings ▸ AI
/// and privacy opens). It never says nothing leaves the device: with Cloud AI on, things do. A fitted sheet, as tall as what it says.
///
/// Harness: `CRAMLESS_ROUTE=consent` or `consent:photos`, with `CRAMLESS_CONSENT=0` for a person who hasn't allowed it;
/// `CRAMLESS_CONSENT_DETAILS=1` opens the full text over it.
struct ConsentSheet: View {
    let reason: ConsentReason
    /// How it goes away, when it isn't the router's sheet (over the syllabus flow, whose editor is the router's sheet).
    var onClose: (() -> Void)? = nil

    @Environment(AppModel.self) private var app
    @State private var showsDetails = false
    @State private var contentHeight: CGFloat = 320
    @State private var actionsHeight: CGFloat = 130

    private var isChild: Bool { app.settings.ageBand == .under13 }
    private var hasConsent: Bool { app.hasCloudConsent }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CLSpace.l) {
                header
                if isChild {
                    Text("Cloud AI isn't available for accounts under 13. Questions, grades and Cap's answers come from your iPhone.")
                        .clFont(.body)
                        .foregroundStyle(CLColor.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(alignment: .leading, spacing: CLSpace.s) {
                        Text(Self.whatGoes(reason, cloudOn: hasConsent))
                            .clFont(.body)
                            .foregroundStyle(CLColor.ink)
                        Text(Self.kept)
                            .clFont(.body)
                            .foregroundStyle(CLColor.ink2)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    CLList {
                        Button {
                            CLHaptics.tap()
                            showsDetails = true
                        } label: {
                            CLRow(icon: "doc.text.magnifyingglass", title: "Exactly what's sent")
                        }
                        .buttonStyle(.pressable)
                    }
                }
            }
            .padding(.horizontal, CLSpace.gutter)
            .padding(.top, CLSpace.xxl)
            .padding(.bottom, CLSpace.l)
            .frame(maxWidth: CLMetrics.readableWidth)
            .frame(maxWidth: .infinity)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            actions.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { actionsHeight = $0 }
        }
        .presentationDetents([.height(contentHeight + actionsHeight)])
        .presentationDragIndicator(.visible)
        .presentationBackground(CLColor.background)
        // Sheets don't inherit the root's font choice (RootView sets it inside the modifier that presents them).
        .environment(\.clDyslexicFont, app.settings.dyslexicFont)
        .sheet(isPresented: $showsDetails) {
            WhatsSentSheet(focus: reason == .photos ? .photos(cloudOn: hasConsent) : .cloudAI)
                .environment(\.clDyslexicFont, app.settings.dyslexicFont)
        }
        #if DEBUG
        .task {
            guard TestHarness.once("CRAMLESS_CONSENT_DETAILS") == "1" else { return }
            try? await nap(900)
            showsDetails = true
        }
        #endif
    }

    // MARK: Parts

    private var header: some View {
        HStack(alignment: .center, spacing: CLSpace.m) {
            CapFace(size: 48)
            Text(title)
                .clFont(.title2)
                .foregroundStyle(CLColor.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private var actions: some View {
        VStack(spacing: CLSpace.s) {
            if isChild {
                Button("OK") { close() }
                    .buttonStyle(.cl(.primary))
            } else {
                Button(allowTitle) { allow() }
                    .buttonStyle(.cl(.primary))
                Button("Not now") { close() }
                    .buttonStyle(.cl(.ghost, size: .medium))
            }
        }
        .padding(.horizontal, CLSpace.gutter)
        .padding(.top, CLSpace.m)
        .padding(.bottom, CLSpace.s)
        .background(alignment: .top) {
            // Opaque, so the text scrolling under it never shows through.
            CLColor.background
                .overlay(alignment: .top) { Rectangle().fill(CLColor.hairline).frame(height: 0.5) }
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private func close() {
        if let onClose { onClose() } else { app.router.dismissSheet() }
    }

    private func allow() {
        CLHaptics.commit()
        switch reason {
        case .cloudAI:
            // Page photos keep whatever the person chose before; they have their own sheet and switch.
            app.allowCloudAI()
        case .photos:
            if hasConsent { app.setSendPhotos(true) } else { app.allowCloudAI(sendPhotos: true) }
        }
        close()
        app.router.toast(reason == .photos ? "Page photos will go to Cloud AI" : "Cloud AI is on", systemImage: "checkmark.circle.fill")
    }

    // MARK: Words

    private var title: String {
        switch reason {
        case .cloudAI: "Use Cloud AI?"
        case .photos: "Send page photos?"
        }
    }

    private var allowTitle: String {
        switch reason {
        case .cloudAI: "Allow Cloud AI"
        case .photos: hasConsent ? "Send page photos" : "Allow Cloud AI and photos"
        }
    }

    /// The first line: what goes, to whom, and why. The processor is named here, never below the fold.
    static func whatGoes(_ reason: ConsentReason, cloudOn: Bool) -> LocalizedStringResource {
        switch reason {
        case .cloudAI:
            "Your notes, questions and answers go to \(AIConsent.processor), through Capling's server, so Cap can write and grade questions."
        case .photos where cloudOn:
            "Photos of the pages you scan go to \(AIConsent.processor) with their text, through Capling's server, so it can read handwriting, math and diagrams."
        case .photos:
            "Photos of the pages you scan go to \(AIConsent.processor) with your notes, questions and answers, through Capling's server, so it can read handwriting, math and diagrams."
        }
    }

    /// The second line. Our server keeps none of what is sent (the provider's own terms are in the privacy policy, not promised here).
    static let kept: LocalizedStringResource = "Our server keeps none of it, and nothing trains AI. Turn it off any time in Settings."
}

// MARK: - The full text

/// Everything that goes with Cloud AI on, and to whom: the full text behind the consent sheet's two lines ("Exactly what's sent") and
/// Settings ▸ AI and privacy's "What's sent". `AIConsent.Words` says what is added, asked and answered, so the two places can't drift.
struct WhatsSentSheet: View {
    enum Focus: Equatable {
        case cloudAI
        /// From the photos sheet: the photos first, and, with Cloud AI already on, only what the photos switch adds.
        case photos(cloudOn: Bool)
    }

    var focus: Focus = .cloudAI

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: CLSpace.l) {
                    ForEach(points, id: \.icon) { point in
                        ConsentPoint(systemImage: point.icon, title: point.title, text: point.text)
                    }
                }
                .clCard()
                .padding(.horizontal, CLSpace.gutter)
                .padding(.top, CLSpace.s)
                .padding(.bottom, CLSpace.xl)
                .frame(maxWidth: CLMetrics.readableWidth)
                .frame(maxWidth: .infinity)
            }
            .clScreenBackground()
            .navigationTitle("What's sent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private struct Point { var icon: String; var title: LocalizedStringResource; var text: LocalizedStringResource }

    private var points: [Point] {
        var list: [Point] = []
        if case .photos(let cloudOn) = focus {
            list.append(Point(icon: "photo", title: "Page photos", text: cloudOn
                ? "Photos of the pages you scan, made smaller first, along with their text, for as long as this switch is on."
                : "Photos of the pages you scan, made smaller first, along with their text, for as long as this switch is on. This also turns on Cloud AI, so your notes, your answers and your questions to Cap go too."))
        }
        if focus != .photos(cloudOn: true) {
            list += [
                Point(icon: "doc.text", title: AIConsent.Words.addedTitle, text: AIConsent.Words.added),
                Point(icon: "bubble.left.and.text.bubble.right", title: AIConsent.Words.askedTitle, text: AIConsent.Words.asked),
                Point(icon: "checkmark.bubble", title: AIConsent.Words.answeredTitle, text: AIConsent.Words.answered),
            ]
        }
        return list + [
            Point(icon: "server.rack", title: "Who reads it",
                  text: "\(AIConsent.processor), through Capling's own server, never straight from your phone to an AI company. Our server doesn't keep what you send."),
            Point(icon: "hand.raised", title: "Never used for training",
                  text: "Your notes and answers are never used to train AI models."),
            Point(icon: "list.bullet.rectangle", title: "What our server keeps",
                  text: "A short record of each AI request and a count of them, for your limits. Never what a request said, and your chats stay on this iPhone. If you sign in, sync keeps a copy of your study in your account."),
            Point(icon: "switch.2", title: "Your choice",
                  text: "Turn it off any time in Settings, AI and privacy. Without it, Capling still works: questions and grades come from your iPhone, in less detail."),
        ]
    }
}

/// One point of the full text: an icon, a short title and a plain sentence or two.
private struct ConsentPoint: View {
    let systemImage: String
    let title: LocalizedStringResource
    let text: LocalizedStringResource

    var body: some View {
        HStack(alignment: .top, spacing: CLSpace.m) {
            CLIconBadge(systemImage: systemImage, tint: .sky, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).clFont(.bodyEmphasis).foregroundStyle(CLColor.ink)
                Text(text)
                    .clFont(.subheadline)
                    .foregroundStyle(CLColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
