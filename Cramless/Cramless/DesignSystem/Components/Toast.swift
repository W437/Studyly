import SwiftUI

/// A short confirmation that floats at the top: "Added 14 questions to Bio 101". One at a time; a new toast
/// replaces the old. Raise one with `router.toast(...)`; RootView hosts the view. It floats over anything (the band, a card, a
/// question), so it sits on the solid surface, with a hairline for a dark page, where glass would let what's under it show through.
struct Toast: Identifiable, Equatable, Sendable {
    enum Tone: Sendable { case neutral, success, warning }

    let id = UUID()
    var message: LocalizedStringResource
    var systemImage: String = "checkmark.circle.fill"
    var tone: Tone = .neutral
    var actionTitle: LocalizedStringResource?
    /// What the button does (with `actionTitle`): RootView's host runs it through the router (`Router.runToastAction()`).
    var action: ToastAction?
    /// Seconds on screen. VoiceOver users get it announced instead of racing the timer.
    var duration: Double = 3

    static func == (lhs: Toast, rhs: Toast) -> Bool { lhs.id == rhs.id }
}

struct ToastView: View {
    let toast: Toast
    var onAction: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: toast.systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(iconColor)
            Text(toast.message)
                .clFont(.subheadlineEmphasis)
                .foregroundStyle(CLColor.ink)
                .lineLimit(2)
            if let title = toast.actionTitle, let onAction {
                Spacer(minLength: 4)
                Button(title, action: onAction)
                    .clFont(.subheadlineEmphasis)
                    .foregroundStyle(CLColor.skyInk)
                    .buttonStyle(.plain)
                    .frame(minWidth: CLMetrics.minHitTarget, minHeight: CLMetrics.minHitTarget)
                    .contentShape(Rectangle())
                    .padding(.vertical, -10)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(CLColor.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(CLColor.hairline, lineWidth: 1))
        .shadow(color: CLColor.night.opacity(0.16), radius: 14, y: 6)
        .padding(.horizontal, 20)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
        .accessibilityActions {
            if let title = toast.actionTitle, let onAction {
                Button(title, action: onAction)
            }
        }
    }

    private var iconColor: Color {
        switch toast.tone {
        case .neutral: CLColor.skyInk
        case .success: CLColor.mintInk
        case .warning: CLColor.sunInk
        }
    }
}
