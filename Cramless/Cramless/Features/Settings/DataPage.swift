import SwiftUI

/// Settings ▸ Your data: export the cards as CSV or everything as JSON (through the share sheet), and delete
/// everything on this iPhone.
struct DataPage: View {
    @Environment(AppModel.self) private var app
    @State private var cards: ExportFile?
    @State private var everything: ExportFile?
    @State private var cardCount = 0
    @State private var confirmingWipe = false

    var body: some View {
        let courseCount = app.courses.count
        SettingsScroll(title: "Your data") {
            SettingsGroup(title: "Export", footer: "Files are made on this iPhone and go only where you send them.") {
                if let cards {
                    ShareLink(item: cards, preview: SharePreview(cards.fileName, image: Image(systemName: "tablecells"))) {
                        CLRow(icon: "tablecells", tint: .mint, title: "Cards as CSV",
                              subtitle: "\(CLFormat.count(cardCount, "card")), for a spreadsheet, Anki or Quizlet") {
                            Image(systemName: "square.and.arrow.up").foregroundStyle(CLColor.ink3).accessibilityHidden(true)
                        }
                    }
                    .buttonStyle(.pressable)
                    .disabled(cardCount == 0)
                }
                if let everything {
                    ShareLink(item: everything, preview: SharePreview(everything.fileName, image: Image(systemName: "curlybraces"))) {
                        CLRow(icon: "curlybraces", tint: .sky, title: "Everything as JSON",
                              subtitle: "Courses, notes, cards, reviews, exams, chats and settings") {
                            Image(systemName: "square.and.arrow.up").foregroundStyle(CLColor.ink3).accessibilityHidden(true)
                        }
                    }
                    .buttonStyle(.pressable)
                }
                if cards == nil || everything == nil {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Getting your files ready").clFont(.subheadline).foregroundStyle(CLColor.ink2)
                    }
                    .padding(16)
                }
            }

            SettingsGroup(title: "Delete", footer: "Your account, if you have one, isn't deleted: sign in again and your synced copy comes back. To delete the account too, use Account.") {
                SettingsActionRow(icon: "trash", title: "Delete all data on this iPhone",
                                  subtitle: "\(CLFormat.count(courseCount, "course")), \(CLFormat.count(cardCount, "card")), reviews, lectures, chats and settings",
                                  destructive: true) {
                    confirmingWipe = true
                }
            }
        }
        .task(id: app.revision) { prepare() }
        .confirmationDialog("Delete everything on this iPhone?", isPresented: $confirmingWipe, titleVisibility: .visible) {
            Button("Delete all data", role: .destructive) {
                CLHaptics.commit()
                for thread in app.chatThreads() { AskStreams.shared.discard(thread.id) }
                app.wipeLocalData()
            }
        } message: {
            Text("Every course, card, review, lecture, exam and chat on this iPhone, and your settings. You'll be signed out here, and onboarding starts again. This can't be undone; export first if you want a copy.")
        }
    }

    private func prepare() {
        let rows = DataExport.cardRows(app: app)
        cardCount = rows.count
        cards = ExportFile(data: Data(DataExport.csv(rows).utf8),
                           fileName: DataExport.fileName("Capling cards", ext: "csv", date: app.now))
        if let data = try? DataExport.json(DataExport.archive(app: app)) {
            everything = ExportFile(data: data, fileName: DataExport.fileName("Capling export", ext: "json", date: app.now))
        }
    }
}

/// Settings ▸ More ▸ About: Cap and the wordmark, the version, the Terms and Privacy pages once they exist (never an invented address),
/// and the fonts' licences last.
///
/// Harness: `CRAMLESS_ROUTE=settings:about`.
struct AboutPage: View {
    var body: some View {
        SettingsScroll(title: "About") {
            VStack(spacing: 8) {
                CapView(pose: .wave, size: 120, decorative: false)
                CaplingWordmark(size: 40, color: CLColor.ink)
                Text("Version \(AboutInfo.version)").clFont(.footnote).foregroundStyle(CLColor.ink2)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 16)
            .padding(.bottom, 24)
            .accessibilityElement(children: .combine)

            CLList {
                if let terms = StoreCatalog.termsURL {
                    Link(destination: terms) { CLRow(icon: "doc.text", title: "Terms of Use") { OutLink() } }
                        .buttonStyle(.pressable)
                }
                if let privacy = StoreCatalog.privacyURL {
                    Link(destination: privacy) { CLRow(icon: "hand.raised", title: "Privacy Policy") { OutLink() } }
                        .buttonStyle(.pressable)
                }
                NavigationLink(value: Route.settingsPage(.fontLicences)) {
                    CLRow(icon: SettingsPage.fontLicences.icon, tint: SettingsPage.fontLicences.tint, title: SettingsPage.fontLicences.title)
                }
                .buttonStyle(.pressable)
            }
        }
    }

    /// The mark of a row that opens a web page.
    private struct OutLink: View {
        var body: some View {
            Image(systemName: "arrow.up.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(CLColor.ink4)
                .accessibilityHidden(true)
        }
    }
}

/// Settings ▸ More ▸ About ▸ Font licences: both fonts, each opening its licence in place (both under the SIL Open Font License).
struct FontLicencesPage: View {
    @State private var openLicence: String?

    var body: some View {
        SettingsScroll(title: "Font licences") {
            SettingsGroup(footer: "Both fonts are used under the SIL Open Font License 1.1. OpenDyslexic is unmodified.") {
                licenceRow(name: "Bricolage Grotesque", detail: "Headlines and the wordmark", file: "BricolageGrotesque-OFL")
                licenceRow(name: "OpenDyslexic", detail: "The dyslexia-friendly reading font", file: "OpenDyslexic-OFL")
            }
            .padding(.top, 14)
        }
    }

    @ViewBuilder
    private func licenceRow(name: String, detail: String, file: String) -> some View {
        let open = openLicence == file
        VStack(alignment: .leading, spacing: 0) {
            Button {
                CLHaptics.select()
                withAnimation(CLMotion.settle) { openLicence = open ? nil : file }
            } label: {
                CLRow(icon: "textformat", tint: .capy, title: .verbatim(name), subtitle: "\(detail) · SIL OFL 1.1") {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(CLColor.ink4)
                        .rotationEffect(.degrees(open ? 180 : 0))
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(.pressable)
            .accessibilityHint(Text(open ? "Hides the licence" : "Shows the full licence"))
            if open {
                Text(Self.licence(file))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(CLColor.ink2)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(CLColor.surface2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .transition(.opacity)
            }
        }
    }

    /// The licence file bundled beside the font.
    static func licence(_ name: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "SIL Open Font License, Version 1.1."
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
