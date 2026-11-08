import SwiftUI

/// Settings ▸ More ▸ Help: one line, and "Write to us", which opens Loopware's support page (`StoreCatalog.supportURL`). No reply time is
/// promised. Also a sheet (`AppSheet.help`, and `HelpLink` beside the paywall's footer and the free-limit lines), with a Done button.
///
/// DEBUG: `CRAMLESS_ROUTE=settings:help` opens the page.
struct HelpPage: View {
    /// Shown as a sheet: it has its own Done.
    var inSheet = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        SettingsScroll(title: "Help") {
            VStack(alignment: .leading, spacing: 16) {
                CapView(pose: .wave, size: 96)
                    .accessibilityHidden(true)
                Text(HelpCopy.intro)
                    .clFont(.body)
                    .foregroundStyle(CLColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Button(HelpCopy.writeTitle) {
                    CLHaptics.tap()
                    openURL(StoreCatalog.supportURL)
                }
                .buttonStyle(.cl(.primary))
                .accessibilityHint(Text("Opens Loopware's support page"))
            }
            .padding(.top, 10)
        }
        .toolbar {
            if inSheet {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// Help's words, in one place (a test reads them).
enum HelpCopy {
    static let intro: LocalizedStringResource = "Questions, a bug or a surprise charge? A real person reads every message."
    static let writeTitle: LocalizedStringResource = "Write to us"
    static let linkTitle: LocalizedStringResource = "Questions? Ask a real person"
}

/// The Help page as a sheet of its own.
struct HelpSheet: View {
    var body: some View {
        NavigationStack { HelpPage(inSheet: true) }
    }
}

/// "Questions? Ask a real person": a quiet link to Help, beside a free limit or a price. It opens Help in a sheet of its own, over
/// whatever is showing (the paywall, a capture), so the screen under it stays where it was.
struct HelpLink: View {
    var alignment: HorizontalAlignment = .leading

    @State private var showing = false

    var body: some View {
        Button {
            CLHaptics.tap()
            showing = true
        } label: {
            Label { Text(HelpCopy.linkTitle) } icon: { Image(systemName: "questionmark.bubble") }
                .clFont(.footnoteEmphasis)
                .foregroundStyle(CLColor.skyInk)
                .multilineTextAlignment(alignment == .center ? .center : .leading)
                .frame(minHeight: CLMetrics.minHitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Opens Help, with a way to write to Loopware"))
        .sheet(isPresented: $showing) { HelpSheet() }
    }
}

/// "Restore purchases", with its outcome as a toast (Settings ▸ Subscription, and the paywall for an account under 13).
struct RestorePurchasesRow: View {
    @Environment(AppModel.self) private var app
    @State private var restoring = false

    var body: some View {
        SettingsActionRow(icon: "arrow.clockwise", tint: .sky, title: "Restore purchases",
                          subtitle: "Bought Capling before, on this Apple Account?", busy: restoring) {
            restore()
        }
    }

    private func restore() {
        restoring = true
        Task {
            let outcome = await app.purchases.restore()
            restoring = false
            switch outcome {
            case .restored(let plan):
                CLHaptics.success()
                app.router.toast("Restored. \(plan == .pass ? "Exam Pass" : "Capling \(plan.displayName)") is on.", systemImage: "sparkles")
            case .nothingToRestore:
                app.router.toast("Nothing to restore on this Apple Account.", systemImage: "info.circle", tone: .neutral)
            case .cancelled:
                break
            case .failed:
                app.router.toast("The App Store didn't answer. Try again in a moment.", systemImage: "exclamationmark.triangle.fill", tone: .warning)
            }
        }
    }
}
