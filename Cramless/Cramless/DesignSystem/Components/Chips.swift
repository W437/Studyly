import SwiftUI

/// A capsule chip: filters, suggestions, topic tags. `selected` inverts it (ink fill).
struct CLChip: View {
    let title: LocalizedStringResource
    var systemImage: String?
    var selected = false

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 13, weight: .semibold))
            }
            Text(title).clFont(.footnoteEmphasis).lineLimit(1)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 32)
        .foregroundStyle(selected ? CLColor.background : CLColor.ink2)
        .background(selected ? CLColor.ink : CLColor.surface2, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A source chip: "p. 87 · Anaphase", "Lecture 6 · 12:05". Every generated question and tutor answer carries one.
struct CLSourceChip: View {
    let label: String
    var systemImage: String = "book.pages"

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage).font(.system(size: 11, weight: .semibold))
            Text(label).clFont(.caption).fontWeight(.semibold).lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 26)
        .foregroundStyle(CLColor.skyInk)
        .background(CLColor.skySoft, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Source: \(label)"))
    }
}

/// A small status pill: "+5% this week", "soon", "New".
struct CLPill: View {
    enum Tone: Sendable { case mint, rose, sun, sky, tangerine, neutral }

    let text: LocalizedStringResource
    var tone: Tone = .neutral
    var systemImage: String?

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage).font(.system(size: 10, weight: .bold)) }
            Text(text).font(.system(.caption, design: .rounded, weight: .bold)).lineLimit(1)
        }
        .padding(.horizontal, 9)
        .frame(minHeight: 24)
        .foregroundStyle(ink)
        .background(fill, in: Capsule())
    }

    private var ink: Color {
        switch tone {
        case .mint: CLColor.mintInk
        case .rose: CLColor.roseInk
        case .sun: CLColor.sunInk
        case .sky: CLColor.skyInk
        case .tangerine: CLColor.tangerineInk
        case .neutral: CLColor.ink2
        }
    }

    private var fill: Color {
        switch tone {
        case .mint: CLColor.mintSoft
        case .rose: CLColor.roseSoft
        case .sun: CLColor.sunSoft
        case .sky: CLColor.skySoft
        case .tangerine: CLColor.tangerineSoft
        case .neutral: CLColor.surface3
        }
    }
}

/// A wrapping row of chips.
struct CLFlow: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = Self.fitted(view, to: width)
            if x > 0, x + size.width > width {
                x = 0; y += lineHeight + lineSpacing; lineHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: proposal.width ?? maxX, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for view in subviews {
            let size = Self.fitted(view, to: bounds.width)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX; y += lineHeight + lineSpacing; lineHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }

    /// A subview at its own size, but never wider than a line (a chip too long for one at the largest text sizes truncates instead of
    /// running off the edge).
    private static func fitted(_ view: LayoutSubview, to width: CGFloat) -> CGSize {
        let size = view.sizeThatFits(.unspecified)
        return CGSize(width: min(size.width, width), height: size.height)
    }
}
