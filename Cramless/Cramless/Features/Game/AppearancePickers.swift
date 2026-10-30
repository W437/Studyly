import SwiftUI

/// Settings ▸ Appearance ▸ Sky: the skies that weeks of quests have lit, and the ones still dark. The sky behind the stars is
/// Night until a different one is picked; picking one changes Today's world and the full sky at once.
struct SkyPicker: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let unlocked = app.unlockedSkies
        let chosen = app.skyTheme
        let columns = [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 150 : 96), spacing: 12, alignment: .top)]
        CLSectionHeader(title: "Sky")
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(SkyTheme.allCases) { theme in
                let isUnlocked = unlocked.contains(theme)
                Button {
                    guard isUnlocked else {
                        CLHaptics.tap()
                        return
                    }
                    guard theme != chosen else { return }
                    CLHaptics.select()
                    withAnimation(CLMotion.fade) { _ = app.setSkyTheme(theme) }
                } label: {
                    PickerOption(selected: theme == chosen, locked: !isUnlocked, title: theme.title,
                                 caption: isUnlocked ? nil : theme.lockedLine) {
                        SkySwatch(theme: theme, width: 96, height: 120, locked: !isUnlocked)
                    }
                }
                .buttonStyle(.pressable)
                .accessibilityLabel(Text(theme.title))
                .accessibilityValue(isUnlocked ? (theme == chosen ? Text("Selected") : Text("")) : Text(theme.lockedLine))
                .accessibilityAddTraits(theme == chosen ? [.isButton, .isSelected] : .isButton)
            }
        }
        // With every sky lit there is no next one to promise.
        let note: LocalizedStringResource = unlocked.count < SkyTheme.allCases.count
            ? "Finish 12 daily quests in a week and the next sky is lit."
            : "Every sky is lit. Pick the one you like."
        Text(note)
            .clFont(.footnote)
            .foregroundStyle(CLColor.ink2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 6)
            .padding(.top, 4)
    }
}

/// Settings ▸ Appearance ▸ App icon: Cap on blue, and four more a streak unlocks. An icon unlocked stays unlocked, so a
/// streak that breaks takes nothing away. Hidden where the system has no alternate icons.
struct IconPicker: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let unlocked = app.unlockedIcons
        let chosen = app.settings.appIcon
        let columns = [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 150 : 96), spacing: 12, alignment: .top)]
        CLSectionHeader(title: "App icon")
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(AppIconChoice.allCases) { icon in
                let isUnlocked = unlocked.contains(icon)
                Button {
                    guard isUnlocked else {
                        CLHaptics.tap()
                        return
                    }
                    guard icon != chosen else { return }
                    CLHaptics.select()
                    Task { await app.setAppIcon(icon) }
                } label: {
                    PickerOption(selected: icon == chosen, locked: !isUnlocked, title: icon.title,
                                 caption: isUnlocked ? nil : icon.lockedLine) {
                        IconPreview(icon: icon, size: 84, locked: !isUnlocked)
                    }
                }
                .buttonStyle(.pressable)
                .accessibilityLabel(Text(icon.title))
                .accessibilityValue(isUnlocked ? (icon == chosen ? Text("Selected") : Text("")) : Text(icon.lockedLine))
                .accessibilityAddTraits(icon == chosen ? [.isButton, .isSelected] : .isButton)
            }
        }
        Text("Your best streak unlocks a new icon at 7, 30, 100 and 365 days. They stay yours.")
            .clFont(.footnote)
            .foregroundStyle(CLColor.ink2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 6)
            .padding(.top, 4)
    }
}

/// An icon's picture, from its preview image set (the icon sets themselves can't be loaded by name): a rounded square as the
/// system draws it. A locked one is a grey shape with a lock.
struct IconPreview: View {
    let icon: AppIconChoice
    var size: CGFloat = 84
    var locked = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
        ZStack {
            if UIImage(named: icon.previewName) != nil {
                Image(icon.previewName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(shape)
                    .saturation(locked ? 0 : 1)
                    .opacity(locked ? 0.35 : 1)
            } else {
                shape.fill(CLColor.surface3).frame(width: size, height: size)
            }
            if locked {
                Image(systemName: "lock.fill")
                    .font(.system(size: size * 0.26, weight: .semibold))
                    .foregroundStyle(CLColor.ink2)
            }
        }
        .frame(width: size, height: size)
        .overlay(shape.strokeBorder(CLColor.hairline, lineWidth: 1))
        .accessibilityHidden(true)
    }
}

/// A picture over its name (and, when it is still dark, what lights it), ringed in tangerine while it is the one in use.
private struct PickerOption<Picture: View>: View {
    let selected: Bool
    let locked: Bool
    let title: LocalizedStringResource
    var caption: LocalizedStringResource?
    @ViewBuilder var picture: Picture

    var body: some View {
        VStack(spacing: 8) {
            picture
                .padding(4)
                .overlay {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(selected ? CLColor.tangerine : .clear, lineWidth: 3)
                }
                .overlay(alignment: .bottomTrailing) {
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(CLColor.tangerine, CLColor.surface)
                            .offset(x: 4, y: 4)
                    }
                }
            Text(title)
                .clFont(.subheadlineEmphasis)
                .foregroundStyle(locked ? CLColor.ink3 : CLColor.ink)
                .multilineTextAlignment(.center)
            if let caption {
                Text(caption)
                    .clFont(.caption)
                    .foregroundStyle(CLColor.ink3)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(CLMotion.snap, value: selected)
    }
}
