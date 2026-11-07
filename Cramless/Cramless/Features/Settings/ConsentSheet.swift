import SwiftUI

/// Asks before anything goes to Cloud AI. Presented by a screen (as `.consent(reason)`) when a job's outcome
/// carries `AISuggestion.allowCloud` or `.allowPhotos`; the router never presents it. Allow records the consent
/// version (`AIConsent.currentVersion`); the screen then runs the job again, and the router reads the new settings.
///
/// The copy says what is sent (`AIConsent.Words`: what's added, asked and answered; photos only with their own switch), who processes it (OpenAI,
/// through Capling's server), that notes never train models, and how to turn it off. It never says nothing leaves the
/// device: with Cloud AI on, things do.
///
/// Harness: `CRAMLESS_ROUTE=consent` or `consent:photos`, with `CRAMLESS_CONSENT=0` for a person who hasn't allowed it.
struct ConsentSheet: View {
    let reason: ConsentReason
    /// How it goes away, when it isn't the router's sheet (over the syllabus flow, whose editor is the router's sheet).
    var onClose: (() -> Void)? = nil

    @Environment(AppModel.self) private var app
    @State private var alsoPhotos = false

    private var isChild: Bool { app.settings.ageBand == .under13 }
    private var hasConsent: Bool { app.hasCloudConsent }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CLSpace.xl) {
                header
                if isChild {
                    Text("Cloud AI isn't available for accounts under 13. Questions, grades and Cap's answers come from your iPhone.")
                        .clFont(.body)
                        .foregroundStyle(CLColor.ink2)
                } else {
                    VStack(alignment: .leading, spacing: CLSpace.l) {
                        ForEach(points, id: \.icon) { point in
                            ConsentPoint(systemImage: point.icon, title: point.title, text: point.text)
                        }
                    }
                    .clCard()
                    if case .cloudAI = reason { photosToggle }
                    if app.settings.isMinor {
                        Text("Cap always starts with hints for accounts under 18, with or without Cloud AI.")
                            .clFont(.footnote)
                            .foregroundStyle(CLColor.ink2)
                    }
                }
            }
            .padding(.horizontal, CLSpace.gutter)
            .padding(.top, CLSpace.xxl)
            .padding(.bottom, CLSpace.l)
            .frame(maxWidth: CLMetrics.readableWidth)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) { actions }
        .clScreenBackground()
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        // Sheets don't inherit the root's font choice (RootView sets it inside the modifier that presents them).
        .environment(\.clDyslexicFont, app.settings.dyslexicFont)
    }

    // MARK: Parts

    private var header: some View {
        HStack(alignment: .top, spacing: CLSpace.m) {
            CapFace(size: 48)
            VStack(alignment: .leading, spacing: CLSpace.xs) {
                Text(title)
                    .clFont(.title2)
                    .foregroundStyle(CLColor.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(lead)
                    .clFont(.callout)
                    .foregroundStyle(CLColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var photosToggle: some View {
        Toggle(isOn: $alsoPhotos) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Also send page photos").clFont(.bodyEmphasis).foregroundStyle(CLColor.ink)
                Text("For handwriting, math and diagrams. Photos of the pages you scan go along with their text. You can change this later.")
                    .clFont(.footnote)
                    .foregroundStyle(CLColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(CLColor.mint)
        .clCard(padding: 16)
        .onAppear { alsoPhotos = app.settings.sendPhotos }
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
            app.allowCloudAI(sendPhotos: alsoPhotos)
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

    private var lead: String {
        switch reason {
        case .cloudAI(let feature):
            "\(feature) with Cloud AI. It's your choice."
        case .photos:
            "Cloud AI can read handwriting, math and diagrams from a photo of the page, not just its text."
        }
    }

    private var allowTitle: String {
        switch reason {
        case .cloudAI: "Allow Cloud AI"
        case .photos: hasConsent ? "Send page photos" : "Allow Cloud AI and photos"
        }
    }

    private struct Point { var icon: String; var title: LocalizedStringResource; var text: LocalizedStringResource }

    private var points: [Point] {
        let sent: [Point]
        switch reason {
        case .cloudAI:
            sent = [
                Point(icon: "doc.text", title: AIConsent.Words.addedTitle, text: AIConsent.Words.added),
                Point(icon: "bubble.left.and.text.bubble.right", title: AIConsent.Words.askedTitle, text: AIConsent.Words.asked),
                Point(icon: "checkmark.bubble", title: AIConsent.Words.answeredTitle, text: AIConsent.Words.answered),
            ]
        case .photos:
            sent = [Point(icon: "doc.text", title: "What's sent", text: hasConsent
                ? "Photos of the pages you scan, made smaller first, along with their text, for as long as this switch is on."
                : "Photos of the pages you scan, made smaller first, along with their text, for as long as this switch is on. This also turns on Cloud AI, so your notes, your answers and your questions to Cap go too.")]
        }
        return sent + [
            Point(icon: "server.rack", title: "Who reads it",
                  text: "\(AIConsent.processor), through Capling's own server, never straight from your phone to an AI company. Our server doesn't keep what you send."),
            Point(icon: "hand.raised", title: "Never used for training",
                  text: "Your notes and answers are never used to train AI models."),
            Point(icon: "switch.2", title: "Your choice",
                  text: "Turn it off any time in Settings, AI and privacy. Without it, Capling still works: questions and grades come from your iPhone, in less detail."),
        ]
    }
}

/// One point of the consent sheet: an icon, a short title and a plain sentence or two.
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
