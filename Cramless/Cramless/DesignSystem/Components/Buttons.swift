import SwiftUI

/// The app's button styles. Capsules with Night ink on brand fills. A filled button stands on a darker edge (4, 3
/// or 2 pt by size, inside the same height) and sinks onto it when pressed, then springs back; text-only and
/// disabled buttons are flat.
///
///     Button("Start") { … }.buttonStyle(.cl(.primary))
///     Button("Continue") { … }.buttonStyle(.cl(.verdict(.mint)))     // the answer panel's Continue
///     Button("Later") { … }.buttonStyle(.cl(.ghost, size: .small, fullWidth: false))
///
/// Floating controls over content (the + button, scanner controls) use the system's `.glass` styles instead.
struct CLButtonStyle: ButtonStyle {
    enum Kind: Sendable {
        /// Tangerine: the one action that moves the person forward.
        case primary
        /// Ink fill: a strong secondary action ("Fix it now").
        case dark
        /// A quiet filled action.
        case soft
        /// White fill on dark or photographic backgrounds.
        case white
        /// Text only.
        case ghost
        /// Destructive, quiet.
        case destructive
        /// The answer panel's Continue, in the verdict's colour (`FeedbackTone.button`).
        case verdict(FeedbackTone)
    }

    enum Size: Sendable { case regular, medium, small }

    var kind: Kind
    var size: Size = .regular
    var fullWidth: Bool = true

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.dynamicTypeSize) private var typeSize

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let depth = isEnabled ? edgeDepth : 0
        configuration.label
            .clFont(size == .small ? .subheadlineEmphasis : .headline)
            // One line normally; at accessibility sizes the label wraps instead of shrinking or truncating.
            .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
            .multilineTextAlignment(.center)
            .minimumScaleFactor(typeSize.isAccessibilitySize ? 1 : 0.85)
            .padding(.vertical, typeSize.isAccessibilitySize ? 10 : 0)
            .padding(.horizontal, horizontalPadding)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(minHeight: height - depth)
            .foregroundStyle(foreground)
            .background(background(pressed: pressed), in: shape)
            // The face sinks onto its edge while pressed; the edge stays put underneath.
            .offset(y: pressed ? depth : 0)
            .background {
                if depth > 0 { shape.fill(edge).offset(y: depth) }
            }
            .padding(.bottom, depth)
            // The small size draws 38 pt but takes taps over 44 pt, the minimum target.
            .frame(minHeight: CLMetrics.minHitTarget)
            .contentShape(Rectangle())
            .scaleEffect(pressed && depth == 0 ? 0.965 : 1)
            .opacity(isEnabled ? 1 : 0.4)
            .animation(pressed ? CLMotion.press : CLMotion.release, value: pressed)
    }

    /// A capsule; at the accessibility sizes, where a label can take two or three lines, a rounded box that keeps its corners off the words.
    private var shape: AnyShape {
        typeSize.isAccessibilitySize ? AnyShape(RoundedRectangle(cornerRadius: 24, style: .continuous)) : AnyShape(Capsule())
    }

    /// How far the face stands above its edge.
    private var edgeDepth: CGFloat {
        switch kind {
        case .ghost: 0
        default:
            switch size {
            case .regular: 4
            case .medium: 3
            case .small: 2
            }
        }
    }

    private var edge: Color {
        switch kind {
        case .primary: CLColor.tangerineEdge
        case .dark: CLColor.inkEdge
        case .soft: CLColor.surfaceEdge
        case .white: CLColor.whiteEdge
        case .ghost: .clear
        case .destructive: CLColor.roseEdge.opacity(0.35)
        case .verdict(let tone): tone.buttonEdge
        }
    }

    private var height: CGFloat {
        switch size {
        case .regular: CLMetrics.buttonHeight
        case .medium: CLMetrics.buttonHeightMedium
        case .small: CLMetrics.buttonHeightSmall
        }
    }

    private var horizontalPadding: CGFloat {
        switch size {
        case .regular: 24
        case .medium: 20
        case .small: 16
        }
    }

    private var foreground: Color {
        switch kind {
        case .primary: CLColor.onFill
        case .dark: CLColor.background
        case .soft: CLColor.ink
        case .white: CLColor.night
        case .ghost: CLColor.ink2
        case .destructive: CLColor.roseInk
        case .verdict: CLColor.onFill
        }
    }

    private func background(pressed: Bool) -> Color {
        switch kind {
        case .primary: pressed ? CLColor.tangerinePressed : CLColor.tangerine
        case .dark: CLColor.ink.opacity(pressed ? 0.85 : 1)
        case .soft: pressed ? CLColor.surface3.opacity(0.7) : CLColor.surface3
        case .white: Color.white.opacity(pressed ? 0.85 : 1)
        case .ghost: pressed ? CLColor.surface3.opacity(0.6) : .clear
        case .destructive: pressed ? CLColor.roseSoft.opacity(1.4) : CLColor.roseSoft
        case .verdict(let tone): tone.button
        }
    }
}

extension ButtonStyle where Self == CLButtonStyle {
    static func cl(_ kind: CLButtonStyle.Kind, size: CLButtonStyle.Size = .regular, fullWidth: Bool = true) -> CLButtonStyle {
        CLButtonStyle(kind: kind, size: size, fullWidth: fullWidth)
    }
}

/// A plain style that scales a little when pressed: cards and rows that are tappable as a whole. With a `depth`
/// (answer options, rating tiles) the label instead stands on an edge of that colour and sinks onto it when pressed.
struct CLPressableStyle: ButtonStyle {
    var scale: CGFloat = 0.985
    var depth: CGFloat = 0
    var edge: Color = CLColor.surfaceEdge
    var cornerRadius: CGFloat = CLRadius.option

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        if depth > 0 {
            configuration.label
                .offset(y: pressed ? depth : 0)
                .background {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(edge).offset(y: depth)
                }
                .padding(.bottom, depth)
                .contentShape(Rectangle())
                .animation(pressed ? CLMotion.press : CLMotion.release, value: pressed)
        } else {
            configuration.label
                .contentShape(Rectangle())
                .scaleEffect(pressed ? scale : 1)
                .animation(CLMotion.snap, value: pressed)
        }
    }
}

extension ButtonStyle where Self == CLPressableStyle {
    static var pressable: CLPressableStyle { CLPressableStyle() }

    /// Pressable with depth: the label sinks onto an `edge` of the given shape.
    static func pressable(depth: CGFloat, edge: Color = CLColor.surfaceEdge,
                          cornerRadius: CGFloat = CLRadius.option) -> CLPressableStyle {
        CLPressableStyle(depth: depth, edge: edge, cornerRadius: cornerRadius)
    }
}

/// A round icon button (close, back, more). 44 pt tap area whatever the drawn size.
struct CLIconButton: View {
    let systemImage: String
    let label: String
    var filled: Bool = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(CLColor.ink)
                .frame(width: 34, height: 34)
                .background(filled ? CLColor.surface3 : .clear, in: Circle())
                .frame(width: CLMetrics.minHitTarget, height: CLMetrics.minHitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
