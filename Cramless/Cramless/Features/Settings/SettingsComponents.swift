import SwiftUI

// The pieces every Settings page is made of: the page scaffold, a group with a header and footer, switch rows that
// carry their consequence for VoiceOver, plain information cards, and the words for a backend error.

/// A Settings page: a scroll of groups on the screen background, with an inline title.
struct SettingsScroll<Content: View>: View {
    let title: LocalizedStringResource
    @ViewBuilder var content: Content

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    content
                }
                .padding(.horizontal, CLSpace.gutter)
                .padding(.top, 6)
                .padding(.bottom, 40)
                .frame(maxWidth: CLMetrics.readableWidth)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(HarnessScroll.anchor(.top), for: .initialOffset)
            .harnessScroll(proxy)
        }
        .clScreenBackground()
        .navigationTitle(Text(title))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Where a screen starts scrolled. DEBUG: `CRAMLESS_SCROLL=top|bottom` overrides it, so screenshots can show the far
/// end of a long page (Settings pages, a chat).
@MainActor
enum HarnessScroll {
    static func anchor(_ fallback: UnitPoint?) -> UnitPoint? {
        #if DEBUG
        switch TestHarness.value("CRAMLESS_SCROLL") {
        case "top": return .top
        case "bottom": return .bottom
        default: break
        }
        #endif
        return fallback
    }
}

/// A titled group: a header, its rows in a card list, and an optional footnote under it.
struct SettingsGroup<Content: View>: View {
    var title: LocalizedStringResource?
    var footer: LocalizedStringResource?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title { CLSectionHeader(title: title) }
            CLList { content }
            if let footer {
                Text(footer)
                    .clFont(.footnote)
                    .foregroundStyle(CLColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 6)
                    .padding(.top, 10)
            }
        }
    }
}

/// A switch with a title, a line saying what it does, and (for VoiceOver) what turning it on or off means. When
/// `disabledReason` is set the switch is off-limits and the reason replaces the line.
struct SettingsToggleRow: View {
    let title: LocalizedStringResource
    var subtitle: LocalizedStringResource?
    @Binding var isOn: Bool
    /// What turning it on (or off) does, read by VoiceOver.
    var hintOn: LocalizedStringResource?
    var hintOff: LocalizedStringResource?
    var disabledReason: LocalizedStringResource?

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).clFont(.bodyEmphasis).foregroundStyle(CLColor.ink)
                if let line = disabledReason ?? subtitle {
                    Text(line)
                        .clFont(.footnote)
                        .foregroundStyle(CLColor.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .tint(CLColor.mint)
        .disabled(disabledReason != nil)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: CLMetrics.rowMinHeight)
        .accessibilityHint(Text((isOn ? hintOff : hintOn) ?? ""))
    }
}

/// A row with a title and a value on the right ("Version · 1.0 (1)").
struct SettingsValueRow: View {
    let title: LocalizedStringResource
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title).clFont(.bodyEmphasis).foregroundStyle(CLColor.ink)
            Spacer(minLength: 8)
            Text(value).clFont(.body).foregroundStyle(CLColor.ink2).multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: CLMetrics.rowMinHeight)
        .accessibilityElement(children: .combine)
    }
}

/// A row that does something (no chevron): an icon, a title, a line.
struct SettingsActionRow: View {
    let icon: String
    var tint: CourseColor = .sky
    let title: LocalizedStringResource
    var subtitle: LocalizedStringResource?
    var destructive = false
    var busy = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            // CLRow's layout, with the title in Rose ink when the action destroys something.
            HStack(spacing: 12) {
                CLIconBadge(systemImage: icon, tint: destructive ? .rose : tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).clFont(.bodyEmphasis).foregroundStyle(destructive ? CLColor.roseInk : CLColor.ink)
                    if let subtitle {
                        Text(subtitle).clFont(.footnote).foregroundStyle(CLColor.ink2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if busy { ProgressView() }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(minHeight: CLMetrics.rowMinHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .disabled(busy)
        .accessibilityElement(children: .combine)
    }
}

/// A plain explanation: an icon, a title, a few sentences.
struct SettingsInfoCard: View {
    let icon: String
    var tint: CourseColor = .sky
    let title: LocalizedStringResource
    let text: LocalizedStringResource

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CLIconBadge(systemImage: icon, tint: tint, size: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).clFont(.bodyEmphasis).foregroundStyle(CLColor.ink)
                Text(text)
                    .clFont(.subheadline)
                    .foregroundStyle(CLColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// The initials avatar: Night letters on Tangerine (never white on a brand fill).
struct InitialsAvatar: View {
    let name: String
    var size: CGFloat = 56
    var fill: Color = CLColor.tangerine

    var body: some View {
        ZStack {
            Circle().fill(fill)
            if initials.isEmpty {
                Image(systemName: "person.fill").font(.system(size: size * 0.42, weight: .semibold))
            } else {
                Text(initials).font(.system(size: size * 0.36, weight: .heavy, design: .rounded))
            }
        }
        .foregroundStyle(CLColor.onFill)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    var initials: String { Self.initials(name) }

    /// "Maya" → "M", "Maya Rivera" → "MR".
    static func initials(_ name: String) -> String {
        let words = name.split(whereSeparator: { $0.isWhitespace }).prefix(2)
        return words.compactMap { $0.first.map { String($0).uppercased() } }.joined()
    }
}

extension RelayError {
    /// What a settings or Squad screen says when a backend call fails. Nil for a cancelled call (say nothing).
    var friendlyMessage: String? {
        switch self {
        case .notConfigured: "Accounts aren't set up in this build, so this needs a version of Capling that has them."
        case .consentRequired: "Cloud AI is off, so this didn't go out."
        case .unauthorized: "Your sign-in has expired. Sign in again, then try once more."
        case .quotaExceeded(_, let message): message
        case .entitlementRequired: "Inviting friends is part of the Squad plan."
        case .badRequest(let message): message
        case .upstream: "Something went wrong on our side. Try again in a moment."
        case .offline: "You're offline. Try again when you're connected."
        case .decoding: "Something went wrong on our side. Try again in a moment."
        case .cancelled: nil
        }
    }

    /// Any error as the words above (a non-relay error reads as "something went wrong").
    static func message(for error: Error) -> String? {
        if let relay = error as? RelayError { return relay.friendlyMessage }
        if (error as? URLError)?.code == .notConnectedToInternet { return RelayError.offline.friendlyMessage }
        return "Something went wrong. Try again in a moment."
    }
}
