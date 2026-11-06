import SwiftUI

/// Settings ▸ Accessibility: the dyslexia-friendly font (with a live preview), reading questions aloud, haptics, and
/// what follows the iPhone's own settings (text size, Reduce Motion, VoiceOver).
///
/// Harness: `CRAMLESS_DYSLEXIC=1` turns the font on.
struct AccessibilityPage: View {
    @Environment(AppModel.self) private var app

    private static let sampleQuestion = "In your own words: why do cells divide by mitosis?"
    private static let sampleAnswer = "So the body can grow and repair itself: each new cell gets a full copy of the DNA."

    var body: some View {
        @Bindable var app = app
        SettingsScroll(title: "Accessibility") {
            preview
                .padding(.top, 14)
            SettingsGroup(title: "Reading") {
                SettingsToggleRow(title: "Dyslexia-friendly font",
                                  subtitle: "OpenDyslexic for questions, answers, notes and chats. Headlines and numbers keep their faces.",
                                  isOn: $app.settings.dyslexicFont,
                                  hintOn: "Switches reading text to OpenDyslexic.",
                                  hintOff: "Switches reading text back to the system font.")
                SettingsToggleRow(title: "Read questions aloud",
                                  subtitle: "Each question is read as it appears, in your iPhone's Spoken Content voice.",
                                  isOn: $app.settings.readAloud,
                                  hintOn: "Questions are read aloud as they appear in a session.",
                                  hintOff: "Questions are no longer read aloud. The speaker button still reads one on request.")
                SettingsActionRow(icon: "speaker.wave.2.fill", tint: .sky, title: "Hear an example",
                                  subtitle: "Reads the question above aloud") {
                    app.readAloud(Self.sampleQuestion, force: true)
                }
            }
            SettingsGroup(title: "Feel") {
                SettingsToggleRow(title: "Sounds",
                                  subtitle: app.settings.quietMode ? "Off while Quiet mode is on"
                                      : "Soft notes when you answer and finish. Quiet when your iPhone is on silent.",
                                  isOn: Binding(get: { app.settings.sounds && !app.settings.quietMode },
                                                set: { app.settings.sounds = $0 }),
                                  hintOn: "Plays soft notes for answers and finished sessions.",
                                  hintOff: "Turns off every sound in Capling.")
                    .disabled(app.settings.quietMode)
                SettingsActionRow(icon: "music.note", tint: .mint, title: "Hear an example",
                                  subtitle: "Five right answers in a row") {
                    Self.playExample()
                }
                SettingsToggleRow(title: "Cap moves",
                                  subtitle: "Cap waves, nods and cheers instead of standing still. Always still when Reduce Motion is on.",
                                  isOn: $app.settings.capMoves,
                                  hintOn: "Cap moves on screen.",
                                  hintOff: "Cap stays still.")
                SettingsToggleRow(title: "Cap talks",
                                  subtitle: "Tap Cap and he says something short and silly.",
                                  isOn: $app.settings.capTalks,
                                  hintOn: "Cap speaks when you tap him.",
                                  hintOff: "Cap stays quiet when you tap him.")
                SettingsToggleRow(title: "Haptics",
                                  subtitle: "A light tap when you answer, turn a page or finish a session.",
                                  isOn: $app.settings.haptics,
                                  hintOn: "Turns on taps you can feel for your own actions.",
                                  hintOff: "Turns off every haptic in Capling.")
            }
            SettingsGroup(title: "Follows your iPhone",
                          footer: "Change these in the iPhone's Settings, under Accessibility.") {
                SettingsInfoCard(icon: "textformat.size", tint: .sun, title: "Text size",
                                 text: "Every screen grows with Display & Text Size, up to the largest accessibility sizes.")
                SettingsInfoCard(icon: "figure.walk.motion", tint: .sun, title: "Reduce Motion",
                                 text: "Animations become short fades, and demos rest on their last frame.")
                SettingsInfoCard(icon: "speaker.wave.3", tint: .sun, title: "VoiceOver",
                                 text: "Every control is labelled; Cap's answers are read with their sources.")
            }
        }
    }

    /// A run of five right answers and its flourish, played even with Sounds off so the person can decide (the
    /// Silent switch still silences it).
    private static func playExample() {
        let run: [(ms: Int, cue: CLCue)] = [(0, .right(combo: 1)), (380, .right(combo: 2)), (760, .right(combo: 3)),
                                            (1140, .right(combo: 4)), (1520, .right(combo: 5)), (1610, .flourish)]
        Task { @MainActor in
            var elapsed = 0
            for step in run {
                try? await Task.sleep(for: .milliseconds(step.ms - elapsed))
                elapsed = step.ms
                CLSound.shared.play(step.cue, force: true)
            }
        }
    }

    /// The font as it reads, changing the moment the switch does.
    private var preview: some View {
        VStack(alignment: .leading, spacing: 10) {
            CLEyebrow(text: "Preview")
            Text(Self.sampleQuestion)
                .clFont(.headline)
                .foregroundStyle(CLColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            HighlightedText(text: Self.sampleAnswer,
                            marks: ["grow and repair", "full copy of the DNA"].compactMap {
                                HighlightMark.locate($0, in: Self.sampleAnswer).map { HighlightMark(range: $0, tone: .hit) }
                            },
                            style: .body, color: CLColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .clCard()
        .animation(CLMotion.fade, value: app.settings.dyslexicFont)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Preview: \(Self.sampleQuestion) \(Self.sampleAnswer)"))
    }
}

/// Settings ▸ Appearance: match the iPhone, or always light or dark; the sky behind the stars and the app icon, which weeks of
/// quests and the best streak unlock (`SkyPicker`, `IconPicker`).
struct AppearancePage: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // Three equal columns; one above the other at the accessibility sizes.
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(EqualColumns(spacing: 10))
        SettingsScroll(title: "Appearance") {
            CLSectionHeader(title: "Theme")
            layout {
                ForEach(AppSettings.Theme.allCases, id: \.self) { theme in
                    ThemeOption(theme: theme, selected: app.settings.theme == theme) {
                        guard app.settings.theme != theme else { return }
                        CLHaptics.select()
                        withAnimation(CLMotion.fade) { app.settings.theme = theme }
                    }
                }
            }
            Text("Matching your iPhone follows its Light and Dark setting, including on a schedule.")
                .clFont(.footnote)
                .foregroundStyle(CLColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 6)
                .padding(.top, 12)
            // What the game loop unlocks: skies from weeks of quests, icons from the best streak.
            SkyPicker()
            if app.iconSwitcher.supportsAlternates { IconPicker() }
        }
    }
}

/// Children side by side in equal widths, as tall as the tallest.
private struct EqualColumns: Layout {
    var spacing: CGFloat = 10

    private func columnWidth(_ total: CGFloat, count: Int) -> CGFloat {
        max(0, (total - spacing * CGFloat(max(0, count - 1))) / CGFloat(max(1, count)))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let total = proposal.width ?? 330
        let width = columnWidth(total, count: subviews.count)
        let height = subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height }.max() ?? 0
        return CGSize(width: total, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let width = columnWidth(bounds.width, count: subviews.count)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + CGFloat(index) * (width + spacing), y: bounds.minY),
                          proposal: ProposedViewSize(width: width, height: bounds.height))
        }
    }
}

private struct ThemeOption: View {
    let theme: AppSettings.Theme
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                // The preview takes the column's width; it never sets it.
                Color.clear
                    .frame(height: 96)
                    .overlay { preview }
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(CLColor.hairline, lineWidth: 1))
                HStack(spacing: 6) {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? CLColor.tangerine : CLColor.ink4)
                    Text(title).clFont(.subheadlineEmphasis).foregroundStyle(CLColor.ink)
                        .lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.85)
                }
                .frame(maxHeight: .infinity)
            }
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(CLColor.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(selected ? CLColor.tangerine : .clear, lineWidth: 2.5))
            .animation(CLMotion.snap, value: selected)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private var title: String {
        switch theme {
        case .system: "Match iPhone"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    @ViewBuilder private var preview: some View {
        switch theme {
        case .light: MiniScreen(dark: false)
        case .dark: MiniScreen(dark: true)
        case .system:
            HStack(spacing: 0) {
                MiniScreen(dark: false)
                MiniScreen(dark: true)
            }
        }
    }
}

/// A tiny Today screen in light or dark: a card, a tangerine button, a ring of readiness.
private struct MiniScreen: View {
    let dark: Bool

    var body: some View {
        let bg = dark ? Color(hex: 0x0B1220) : Color(hex: 0xF1F5FA)
        let card = dark ? Color(hex: 0x151E30) : Color.white
        let ink = dark ? Color(hex: 0xEEF3FA) : Color(hex: 0x14213D)
        ZStack(alignment: .topLeading) {
            bg
            VStack(alignment: .leading, spacing: 6) {
                Capsule().fill(ink.opacity(0.85)).frame(width: 26, height: 6)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 4) {
                        Circle().stroke(CLColor.mint, lineWidth: 3).frame(width: 14, height: 14)
                        Capsule().fill(ink.opacity(0.5)).frame(maxWidth: 22).frame(height: 4)
                    }
                    Capsule().fill(CLColor.tangerine).frame(height: 9)
                }
                .padding(5)
                .background(card, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                Capsule().fill(ink.opacity(0.25)).frame(maxWidth: 34).frame(height: 4)
            }
            .padding(7)
        }
        .accessibilityHidden(true)
    }
}
