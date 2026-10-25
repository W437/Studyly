import SwiftUI

/// The card for a constellation you tapped in Today's world: its name and how it is doing, and the way to relight it, in one
/// glass row at the foot of the sky. (The full-screen sky has a taller card that also opens the course; here the world is
/// the point and the card stays small.)
struct HeroFocusCard: View {
    let scene: SkyScene
    let index: Int
    var onRelight: () -> Void
    var onClose: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    /// How much of the world's height the card and its gap take: the camera keeps the focused constellation clear of it.
    static let reserved = 108.0

    var body: some View {
        let c = scene.layout.constellations[index]
        let dim = scene.light.dimCount(c)
        let minutes = scene.minutesToRelight(index)
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: c.name)
                    .clFont(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                Text(verbatim: SkyCopy.detail(index, in: scene))
                    .clFont(.footnote)
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onRelight) {
                Text(dim > 0 ? "Relight · \(minutes) min" : "Practice · \(minutes) min")
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .buttonStyle(.cl(.primary, size: .medium))
            .accessibilityLabel(Text(dim > 0 ? SkyCopy.relight(c.name, minutes: minutes) : SkyCopy.practice(c.name, minutes: minutes)))
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 30, height: 30)
                    .background(.white.opacity(0.14), in: Circle())
                    .frame(width: CLMetrics.minHitTarget, height: CLMetrics.minHitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Close"))
        }
        .padding(.leading, 16)
        .padding(.trailing, 4)
        .padding(.vertical, 8)
        .frame(minHeight: 66)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
    }
}
