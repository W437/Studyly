import SwiftUI

/// Settings ▸ Help: a way to reach a real person (Loopware's support page, `StoreCatalog.supportURL`), what stays free, restore,
/// and the version to quote. No reply time is promised. Also a sheet (`AppSheet.help`, and `HelpLink` beside the paywall's
/// footer and the free-limit lines), with a Done button.
///
/// DEBUG: `CRAMLESS_ROUTE=settings:help` opens the page.
struct HelpPage: View {
    /// Shown as a sheet: it has its own Done.
    var inSheet = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        SettingsScroll(title: "Help") {
            VStack(alignment: .leading, spacing: 12) {
                CapView(pose: .wave, size: 96)
                    .accessibilityHidden(true)
                Text(HelpCopy.intro)
                    .clFont(.callout)
                    .foregroundStyle(CLColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 10)

            SettingsGroup {
                Button {
                    CLHaptics.tap()
                    openURL(StoreCatalog.supportURL)
                } label: {
                    CLRow(icon: "envelope", tint: .tangerine, title: HelpCopy.writeTitle,
                          subtitle: .verbatim(HelpCopy.supportHost)) {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(CLColor.ink4)
                            .accessibilityHidden(true)
                    }
                }
                .buttonStyle(.pressable)
                .accessibilityHint(Text("Opens Loopware's support page"))
            }
            .padding(.top, 8)

            AlwaysFreeCard()
                .padding(.top, 24)

            SettingsGroup {
                RestorePurchasesRow()
                SettingsValueRow(title: "Version", value: AboutInfo.version)
            }
            .padding(.top, 16)
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
    static let intro: LocalizedStringResource =
        "Questions, a bug, or a charge you didn't expect? Write to us. A real person reads every message."
    static let writeTitle: LocalizedStringResource = "Write to a real person"
    static let linkTitle: LocalizedStringResource = "Questions? Ask a real person"
    /// "loopware.app/support", under the row.
    static var supportHost: String {
        let url = StoreCatalog.supportURL
        return (url.host() ?? "") + url.path()
    }
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

/// "Restore purchases", with its outcome as a toast. (Settings ▸ Subscription and Help.)
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
