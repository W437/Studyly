import SwiftUI

// Small pieces the capture screens share: the floating close button, the tinted option badge, the course picker,
// the honest origin note, and the review's tick box. Built from the design system's tokens.

/// A round Liquid Glass button floating over content: close, back.
struct CaptureGlassButton: View {
    var systemImage = "xmark"
    var label = "Close"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(CLColor.ink)
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .frame(minWidth: CLMetrics.minHitTarget, minHeight: CLMetrics.minHitTarget)
        .accessibilityLabel(label)
    }
}

/// The tint of an option's icon badge. `neutral` is the ink-on-grey badge ("Paste text").
enum CaptureTint: Sendable {
    case tangerine, rose, sky, mint, sun, neutral

    var fill: Color {
        switch self {
        case .tangerine: CLColor.tangerineSoft
        case .rose: CLColor.roseSoft
        case .sky: CLColor.skySoft
        case .mint: CLColor.mintSoft
        case .sun: CLColor.sunSoft
        case .neutral: CLColor.surface3
        }
    }

    var ink: Color {
        switch self {
        case .tangerine: CLColor.tangerineInk
        case .rose: CLColor.roseInk
        case .sky: CLColor.skyInk
        case .mint: CLColor.mintInk
        case .sun: CLColor.sunInk
        case .neutral: CLColor.ink
        }
    }
}

/// A rounded-square icon on a soft tint (the capture options' badges).
struct CaptureBadge: View {
    let systemImage: String
    var tint: CaptureTint = .sky
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.48, weight: .semibold))
            .foregroundStyle(tint.ink)
            .frame(width: size, height: size)
            .background(tint.fill, in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// One option row: badge, title, subtitle, chevron. The whole row is the button.
struct CaptureOptionRow: View {
    let systemImage: String
    var tint: CaptureTint = .sky
    let title: String
    var subtitle: String?
    var trailing: String? = "chevron.right"
    /// A line under the subtitle: what the free AI allowance has left for this kind of material (`AllowanceCopy`).
    var note: LocalizedStringResource? = nil

    var body: some View {
        HStack(spacing: 12) {
            CaptureBadge(systemImage: systemImage, tint: tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).clFont(.bodyEmphasis).foregroundStyle(CLColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle {
                    Text(subtitle).clFont(.footnote).foregroundStyle(CLColor.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let note {
                    AllowanceLine(text: note)
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let trailing {
                Image(systemName: trailing)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(CLColor.ink4)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: CLMetrics.rowMinHeight)
        .contentShape(Rectangle())
    }
}

/// Picks a course, or makes a new one on the spot. The label is the caller's.
struct CaptureCoursePicker<Label: View>: View {
    @Binding var courseID: UUID?
    @ViewBuilder var label: (Course?) -> Label

    @Environment(AppModel.self) private var app
    @State private var naming = false
    @State private var name = ""

    var body: some View {
        Menu {
            let courses = app.courses
            if !courses.isEmpty {
                Section("Courses") {
                    ForEach(courses, id: \.id) { course in
                        Button {
                            CLHaptics.select()
                            courseID = course.id
                        } label: {
                            if course.id == courseID {
                                SwiftUI.Label(course.name, systemImage: "checkmark")
                            } else {
                                Text(course.name)
                            }
                        }
                    }
                }
            }
            Button("New course…", systemImage: "plus") {
                name = ""
                naming = true
            }
        } label: {
            label(app.course(courseID))
        }
        .alert("New course", isPresented: $naming) {
            TextField("Course name", text: $name)
                .textInputAutocapitalization(.words)
            Button("Add") {
                let course = app.createCourse(named: name)
                CLHaptics.select()
                courseID = course.id
            }
            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Like Bio 101 or AP Psychology.")
        }
    }
}

/// "For  Bio 101 ⌄": the picker as a compact capsule. When the words don't fit on one line (the largest text sizes) the prefix goes and
/// the course's name stays whole; VoiceOver still hears both.
struct CaptureCourseLabel: View {
    let course: Course?
    var prefix = "For"

    var body: some View {
        ViewThatFits(in: .horizontal) {
            capsule(showsPrefix: true)
            capsule(showsPrefix: false)
        }
        .contentShape(Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(course.map { "\(prefix) \($0.name)" } ?? "Choose a course"))
        .accessibilityHint(Text("Changes the course"))
    }

    private func capsule(showsPrefix: Bool) -> some View {
        HStack(spacing: 6) {
            if showsPrefix {
                Text(prefix).clFont(.subheadline).foregroundStyle(CLColor.ink2).lineLimit(1).fixedSize()
            }
            if let course {
                Image(systemName: course.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(course.color.ink)
                Text(course.name).clFont(.subheadlineEmphasis).foregroundStyle(CLColor.ink).lineLimit(1)
            } else {
                Text("Choose a course").clFont(.subheadlineEmphasis).foregroundStyle(CLColor.skyInk)
            }
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(CLColor.ink3)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 40)
        .background(CLColor.surface2, in: Capsule())
    }
}

/// The honest line about who made something: who wrote it, who checked it, what to do.
struct CaptureOriginNote: View {
    let systemImage: String
    let text: String
    var tone: CaptureTint = .sky

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tone.ink)
                .accessibilityHidden(true)
            Text(text)
                .clFont(.subheadline)
                .foregroundStyle(CLColor.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tone.fill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// The review's checkbox: a rounded square that fills mint with a Night check.
struct DraftTickBox: View {
    let on: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(CLColor.surface3, lineWidth: 2)
                .opacity(on ? 0 : 1)
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(CLColor.mint)
                .opacity(on ? 1 : 0)
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(CLColor.onFill)
                .scaleEffect(on ? 1 : 0.4)
                .opacity(on ? 1 : 0)
        }
        .frame(width: 26, height: 26)
        .animation(CLMotion.pop, value: on)
    }
}

/// A fill-in's sentence with its blanks shown as the words, underlined: "During __telophase__, …".
func draftClozeText(_ text: String) -> AttributedString {
    var result = AttributedString()
    var rest = Substring(text)
    while let open = rest.range(of: "{{"), let close = rest.range(of: "}}", range: open.upperBound..<rest.endIndex) {
        result += AttributedString(String(rest[..<open.lowerBound]))
        var blank = AttributedString(String(rest[open.upperBound..<close.lowerBound]))
        blank.underlineStyle = .single
        blank.inlinePresentationIntent = .stronglyEmphasized
        result += blank
        rest = rest[close.upperBound...]
    }
    result += AttributedString(String(rest))
    return result
}

/// DEBUG: `CRAMLESS_CANVAS=375x667` draws the capture and lecture screens at that size (an iPhone SE) inside a larger
/// Simulator, to check narrow layouts on one Simulator. A no-op otherwise, and in release builds.
struct CaptureDebugCanvas: ViewModifier {
    /// A sheet that hugs its content keeps its own height: only the width is the small phone's.
    var widthOnly = false

    func body(content: Content) -> some View {
        #if DEBUG
        if let size = Self.size, widthOnly {
            content
                .frame(width: size.width)
                .frame(maxWidth: .infinity)
        } else if let size = Self.size {
            content
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.ignoresSafeArea())
        } else {
            content
        }
        #else
        content
        #endif
    }

    #if DEBUG
    private static var size: CGSize? {
        guard let raw = TestHarness.value("CRAMLESS_CANVAS") else { return nil }
        let parts = raw.split(separator: "x").compactMap { Double($0) }
        return parts.count == 2 ? CGSize(width: parts[0], height: parts[1]) : nil
    }
    #endif
}

extension View {
    func captureDebugCanvas(widthOnly: Bool = false) -> some View { modifier(CaptureDebugCanvas(widthOnly: widthOnly)) }
}

/// Chips in a wrapping row, or in a column at the accessibility text sizes, where a chip can be wider than the screen
/// and has to wrap its own words (`CLFlow` measures each chip on one line).
struct CaptureChips<Content: View>: View {
    var spacing: CGFloat = 8
    @ViewBuilder var content: Content

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: spacing) { content }
        } else {
            CLFlow(spacing: spacing, lineSpacing: spacing) { content }
        }
    }
}

/// One line of the free AI allowance ("2 free AI scans left this week"): small, quiet, said before the work, never a nudge.
struct AllowanceLine: View {
    let text: LocalizedStringResource

    /// The sparkle grows with the words.
    @ScaledMetric(relativeTo: .caption) private var icon: CGFloat = 11

    var body: some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "sparkles").font(.system(size: icon, weight: .semibold))
        }
        .clFont(.caption)
        .foregroundStyle(CLColor.ink3)
        .labelStyle(AllowanceLabelStyle())
    }
}

/// An icon on the first line, the words wrapping beside it.
private struct AllowanceLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            configuration.icon.accessibilityHidden(true)
            configuration.title
        }
    }
}

