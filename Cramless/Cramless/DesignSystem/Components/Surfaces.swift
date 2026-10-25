import SwiftUI

// Cards, grouped lists, section headers, icon badges and the page scaffold.

extension View {
    /// A raised card: surface fill, 28 pt corners, a soft two-layer shadow, 18 pt padding.
    func clCard(padding: CGFloat = 18, radius: CGFloat = CLRadius.card, flat: Bool = false) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(flat ? CLColor.surface2 : CLColor.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: flat ? .clear : CLColor.night.opacity(0.05), radius: 1, y: 1)
            .shadow(color: flat ? .clear : CLColor.night.opacity(0.06), radius: 12, y: 8)
    }

    /// The tinted night card used for "Today's session".
    func clNightCard(padding: CGFloat = 20) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CLColor.night, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .environment(\.colorScheme, .dark)
    }

    /// Page background for every screen.
    func clScreenBackground() -> some View {
        background(CLColor.background.ignoresSafeArea())
    }
}

/// A grouped list in a card, with hairlines inset past the leading icon.
struct CLList<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            Group(subviews: content) { subviews in
                ForEach(Array(subviews.enumerated()), id: \.offset) { index, subview in
                    if index > 0 {
                        Rectangle().fill(CLColor.hairline).frame(height: 0.5).padding(.leading, 62)
                    }
                    subview
                }
            }
        }
        .background(CLColor.surface, in: RoundedRectangle(cornerRadius: CLRadius.list, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: CLRadius.list, style: .continuous))
        .shadow(color: CLColor.night.opacity(0.05), radius: 1, y: 1)
        .shadow(color: CLColor.night.opacity(0.06), radius: 12, y: 8)
    }
}

/// One row of a `CLList`: an icon badge, a title and subtitle, and a trailing accessory.
struct CLRow<Trailing: View>: View {
    var icon: String?
    var tint: CourseColor = .sky
    var title: LocalizedStringResource
    var subtitle: LocalizedStringResource?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            if let icon { CLIconBadge(systemImage: icon, tint: tint) }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).clFont(.bodyEmphasis).foregroundStyle(CLColor.ink)
                if let subtitle {
                    Text(subtitle).clFont(.footnote).foregroundStyle(CLColor.ink2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: CLMetrics.rowMinHeight)
        .contentShape(Rectangle())
    }
}

extension CLRow where Trailing == CLChevron {
    init(icon: String? = nil, tint: CourseColor = .sky, title: LocalizedStringResource, subtitle: LocalizedStringResource? = nil) {
        self.init(icon: icon, tint: tint, title: title, subtitle: subtitle) { CLChevron() }
    }
}

struct CLChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(CLColor.ink4)
            .accessibilityHidden(true)
    }
}

/// A rounded-square icon on a soft tint.
struct CLIconBadge: View {
    let systemImage: String
    var tint: CourseColor = .sky
    var size: CGFloat = 34

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(tint.ink)
            .frame(width: size, height: size)
            .background(tint.soft, in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// "Other exams ……… See all"
struct CLSectionHeader: View {
    let title: LocalizedStringResource
    var actionTitle: LocalizedStringResource?
    var action: (() -> Void)?

    @Environment(\.dynamicTypeSize) private var typeSize

    /// The action sits at the trailing edge, and under the title at the accessibility text sizes, where a long title
    /// would otherwise be squeezed into a word broken by hyphens.
    var body: some View {
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
        layout {
            Text(title).clFont(.title3).foregroundStyle(CLColor.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if !stacked { Spacer() }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .clFont(.subheadlineEmphasis)
                    .foregroundStyle(CLColor.skyInk)
                    .buttonStyle(.plain)
            }
        }
        .padding(.top, 26)
        .padding(.bottom, 10)
        .padding(.horizontal, 2)
    }
}

/// Small uppercase label above a title.
struct CLEyebrow: View {
    let text: LocalizedStringResource
    var color: Color = CLColor.ink3

    var body: some View {
        Text(text).clFont(.eyebrow).foregroundStyle(color)
    }
}

/// A thin horizontal meter (mastery, progress). `value` is 0…1.
struct CLBar: View {
    var value: Double
    var color: Color? = nil
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(CLColor.surface3)
                Capsule()
                    .fill(color ?? CLColor.readiness(value))
                    .frame(width: max(0, min(1, value)) * geo.size.width)
            }
        }
        .frame(height: height)
        .animation(CLMotion.fill, value: value)
        .accessibilityElement()
        .accessibilityValue(Text("\(Int((value * 100).rounded())) percent"))
    }
}
