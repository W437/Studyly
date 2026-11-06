import SwiftUI

/// The processing screen: the page on a stage (the scanner's brackets lock on, a scan sweeps it, the lines the key
/// ideas came from get highlighted, the first questions land with their page chips) above the four real steps from
/// `generateSet`. The motion is the onboarding demo's (`SnapScene`) on the person's own page; `CaptureRun` paces it.
///
/// Under Reduce Motion nothing sweeps or pops: the stage shows its final state as each step lands, and the step list
/// carries the progress. VoiceOver hears each step as it starts, then how many questions are ready.
struct CaptureProcessingView: View {
    let run: CaptureRun
    var title = "Making your study set"
    var onClose: (() -> Void)?

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        GeometryReader { geo in
            ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    CaptureStage(run: run, size: CGSize(width: geo.size.width, height: stageHeight(geo.size)))
                    VStack(spacing: 4) {
                        Text(title)
                            .clFont(.title2)
                            .foregroundStyle(CLColor.ink)
                            .multilineTextAlignment(.center)
                            .accessibilityAddTraits(.isHeader)
                        if !run.subtitle.isEmpty {
                            Text(run.subtitle)
                                .clFont(.subheadline)
                                .foregroundStyle(CLColor.ink2)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 20)
                    .padding(.horizontal, CLSpace.gutter)
                    CaptureSteps(run: run)
                        .padding(.top, 14)
                        .padding(.horizontal, CLSpace.gutter)
                        .frame(maxWidth: CLMetrics.readableWidth)
                    if let line = run.allowanceLine {
                        AllowanceLine(text: line)
                            .multilineTextAlignment(.center)
                            .padding(.top, 12)
                            .padding(.horizontal, CLSpace.gutter)
                            .frame(maxWidth: CLMetrics.readableWidth)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 28)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
            // On a short screen or with large text the steps run past the fold: keep the one under way in view.
            .onChange(of: run.step) { _, step in
                withAnimation(CLMotion.settle) { proxy.scrollTo(min(step, .checking), anchor: nil) }
            }
            }
        }
        .clScreenBackground()
        .safeAreaBar(edge: .top) {
            HStack {
                if let onClose {
                    CaptureGlassButton(systemImage: "xmark", label: "Stop and close", action: onClose)
                        .padding(.leading, 12)
                }
                Spacer()
            }
            .frame(minHeight: 50)
        }
        .onChange(of: run.announcement) { _, text in
            guard !text.isEmpty else { return }
            AccessibilityNotification.Announcement(text).post()
        }
    }

    /// About two fifths of the screen for the page and the questions landing on it; less on a short screen (so the
    /// four steps stay in view on an iPhone SE) and with very large text.
    private func stageHeight(_ size: CGSize) -> CGFloat {
        // Usable height is about 600 pt on an iPhone SE and 730 pt or more on the others.
        let share: CGFloat = typeSize.isAccessibilitySize ? 0.3 : (size.height < 650 ? 0.32 : 0.44)
        return min(440, max(190, size.height * share))
    }
}

// MARK: - The stage

/// The page with the scanner's brackets, the sweep, the highlighter marks and the first questions.
struct CaptureStage: View {
    let run: CaptureRun
    let size: CGSize

    @Environment(\.colorScheme) private var scheme
    @Environment(\.clReduceMotion) private var reduceMotion

    var body: some View {
        let aspect = run.preview?.aspect ?? 2.0 / 3.0
        // The page fills the stage's height above the question cards' overlap, within 64% of the width.
        let pageHeight = min(size.height - 40, size.width * 0.64 / aspect)
        let pageWidth = pageHeight * aspect
        ZStack(alignment: .bottom) {
            page(width: pageWidth, height: pageHeight)
                .overlay { brackets }
                .rotationEffect(.degrees(-1.5))
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 16)
            cardStack
                .frame(width: min(size.width - 2 * CLSpace.gutter, 400))
                .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        }
        .frame(width: size.width, height: size.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(stageDescription))
    }

    private var stageDescription: String {
        if run.step == .done, !run.cards.isEmpty {
            return "Your page, with the lines the first questions came from highlighted."
        }
        return run.locked ? "Your page, being read." : "Your page."
    }

    // MARK: Page

    @ViewBuilder
    private func page(width: CGFloat, height: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        Group {
            if let preview = run.preview, let path = preview.imagePath {
                PageImageView(fileName: path, aspect: preview.aspect)
                    .overlay { marks(preview) }
            } else if let preview = run.preview {
                CaptureTextPaper(lines: Array(preview.lines.prefix(CapturePagePreview.paperLines)), marked: run.marked)
            } else {
                CLColor.paper.overlay {
                    Image(systemName: "doc.richtext")
                        .font(.system(size: 34, weight: .regular))
                        .foregroundStyle(PaperInk.line)
                }
            }
        }
        .frame(width: width, height: height)
        .overlay(alignment: .top) { sweepBand(height: height) }
        .clipShape(shape)
        .overlay(shape.strokeBorder(CLColor.night.opacity(0.08), lineWidth: 0.5))
        .shadow(color: CLColor.night.opacity(scheme == .dark ? 0.5 : 0.18), radius: 16, y: 10)
    }

    private func marks(_ preview: CapturePagePreview) -> some View {
        GeometryReader { geo in
            let byID = Dictionary(preview.lines.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            ForEach(run.marked, id: \.self) { id in
                if let box = byID[id]?.box {
                    HighlighterMark(rect: CGRect(x: box.x * geo.size.width - 3, y: box.y * geo.size.height - 1.5,
                                                 width: box.w * geo.size.width + 6, height: box.h * geo.size.height + 3),
                                    animated: !reduceMotion)
                }
            }
        }
        .allowsHitTesting(false)
    }

    /// The scan line: a band of light trailing a bright edge, strong enough to read on a busy photo.
    private func sweepBand(height: CGFloat) -> some View {
        LinearGradient(colors: [CLColor.sky.opacity(0), CLColor.sky.opacity(0.6)], startPoint: .top, endPoint: .bottom)
            .frame(height: 56)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(CLColor.sky)
                    .frame(height: 3)
                    .shadow(color: CLColor.sky, radius: 6)
            }
            .offset(y: -56 + run.sweep * (height + 56))
            .opacity(run.sweeping ? 1 : 0)
            .allowsHitTesting(false)
    }

    // MARK: Brackets

    private var brackets: some View {
        let out: CGFloat = run.locked ? 10 : 24
        return ZStack {
            corner(.topLeading).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .offset(x: -out, y: -out)
            corner(.topTrailing).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .offset(x: out, y: -out)
            // The lower pair tucks away behind the questions as they land, as in the scanner.
            Group {
                corner(.bottomLeading).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .offset(x: -out, y: out)
                corner(.bottomTrailing).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .offset(x: out, y: out)
            }
            .opacity(run.cards.isEmpty ? 1 : 0)
            .animation(CLMotion.fade, value: run.cards.isEmpty)
        }
        .opacity(run.locked ? 1 : 0)
        .allowsHitTesting(false)
    }

    private func corner(_ corner: BracketCorner.Corner) -> some View {
        BracketCorner(corner: corner)
            .stroke(CLColor.skyInk, style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
            .frame(width: 28, height: 28)
    }

    // MARK: Questions

    /// Three slots (two on a small stage), laid out from the start so nothing moves when they fill; each question
    /// pops into its slot.
    private var cardStack: some View {
        VStack(spacing: 6) {
            ForEach(0..<(size.height < 280 ? 2 : 3), id: \.self) { index in
                ZStack {
                    questionCard(nil).hidden()
                    if index < run.cards.count {
                        questionCard(run.cards[index])
                            .transition(.asymmetric(insertion: .scale(scale: 0.9).combined(with: .offset(y: 30)).combined(with: .opacity),
                                                    removal: .opacity))
                    }
                }
            }
        }
        .padding(.bottom, 2)
    }

    private func questionCard(_ card: CaptureRun.Card?) -> some View {
        HStack(spacing: 8) {
            Text(card?.prompt ?? "A question from your page")
                .clFont(.footnoteEmphasis)
                .foregroundStyle(CLColor.ink)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            CLSourceChip(label: card?.label ?? "p. 1")
        }
        .padding(.leading, 13)
        .padding(.trailing, 8)
        .padding(.vertical, 7)
        .background(scheme == .dark ? CLColor.surface2 : CLColor.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(CLColor.hairline, lineWidth: 0.5))
        .shadow(color: CLColor.night.opacity(scheme == .dark ? 0.4 : 0.16), radius: 12, y: 8)
    }
}

/// One highlighter mark on the page photo, sweeping in from the left like a pen.
private struct HighlighterMark: View {
    let rect: CGRect
    let animated: Bool

    @State private var shown = false

    var body: some View {
        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
            // Paper is paper in both appearances, so the ink is too.
            .fill(CLColor.sun.opacity(0.62))
            .frame(width: rect.width, height: rect.height)
            .scaleEffect(x: shown ? 1 : 0.001, y: 1, anchor: .leading)
            .position(x: rect.midX, y: rect.midY)
            .blendMode(.multiply)
            .onAppear {
                if animated { withAnimation(CLMotion.calm) { shown = true } } else { shown = true }
            }
    }
}

/// Text material on a sheet of paper (pasted text, a PDF's text layer): the real lines, small, with the marked ones
/// highlighted.
struct CaptureTextPaper: View {
    let lines: [TextLine]
    let marked: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(lines) { line in
                Text(line.text)
                    .font(.system(size: 9.5, weight: line.id == lines.first?.id ? .bold : .regular))
                    .foregroundStyle(PaperInk.heading)
                    .lineLimit(2)
                    .padding(.horizontal, 2)
                    .background(alignment: .leading) {
                        TextMark(on: marked.contains(line.id))
                    }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(CLColor.paper)
        .dynamicTypeSize(.large)
        .environment(\.colorScheme, .light)
    }
}

private struct TextMark: View {
    let on: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(PaperInk.highlighter)
            .scaleEffect(x: on ? 1 : 0.001, y: 1, anchor: .leading)
            .opacity(on ? 1 : 0)
            .animation(CLMotion.calm, value: on)
    }
}

// MARK: - The steps

/// The four steps, each with its real detail: pages read, the topics found, questions written, how many match.
struct CaptureSteps: View {
    let run: CaptureRun

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            CaptureStepRow(state: state(.reading), title: CaptureRun.Step.reading.title, detail: run.readingDetail)
                .id(CaptureRun.Step.reading)
            CaptureStepRow(state: state(.ideas), title: CaptureRun.Step.ideas.title,
                           detail: run.topics.isEmpty ? run.whoLine : nil) {
                if !run.topics.isEmpty {
                    CaptureChips(spacing: 6) {
                        ForEach(run.topics, id: \.self) { topic in
                            TopicChip(title: topic)
                        }
                    }
                    .padding(.top, 6)
                }
            }
            .id(CaptureRun.Step.ideas)
            CaptureStepRow(state: state(.writing), title: CaptureRun.Step.writing.title, detail: run.writtenDetail)
                .id(CaptureRun.Step.writing)
            CaptureStepRow(state: state(.checking), title: CaptureRun.Step.checking.title,
                           detail: run.checkLine ?? run.partLine ?? "So nothing made up gets through")
                .id(CaptureRun.Step.checking)
        }
    }

    private func state(_ step: CaptureRun.Step) -> CaptureStepState {
        if run.step == .done || run.step > step { return .done }
        return run.step == step ? .active : .waiting
    }
}

/// A topic found on the page, popping in.
private struct TopicChip: View {
    let title: String

    @State private var shown = false
    @Environment(\.clReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Text(title)
            .clFont(.footnoteEmphasis)
            .foregroundStyle(CLColor.ink2)
            // A long topic wraps at the largest sizes instead of running off the screen.
            .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 11)
            .padding(.vertical, typeSize.isAccessibilitySize ? 4 : 0)
            .frame(minHeight: 28)
            .background(CLColor.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(CLColor.hairline, lineWidth: 0.5))
            .scaleEffect(shown ? 1 : 0.6)
            .opacity(shown ? 1 : 0)
            .onAppear {
                if reduceMotion { shown = true } else { withAnimation(CLMotion.pop) { shown = true } }
            }
    }
}

/// Where one of the four steps is.
enum CaptureStepState: Equatable { case waiting, active, done }

struct CaptureStepRow<Extra: View>: View {
    let state: CaptureStepState
    let title: String
    var detail: String?
    @ViewBuilder var extra: Extra

    @Environment(\.clReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            dot
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .clFont(.headline)
                    .foregroundStyle(CLColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail)
                        .clFont(.subheadline)
                        .foregroundStyle(CLColor.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                        .contentTransition(.numericText())
                }
                extra
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
        .opacity(state == .waiting ? 0.45 : 1)
        .animation(CLMotion.settle, value: state)
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(stateWords))
    }

    private var stateWords: String {
        switch state {
        case .waiting: "Not started"
        case .active: "In progress"
        case .done: "Done"
        }
    }

    private var dot: some View {
        ZStack {
            Circle().fill(state == .done ? CLColor.mint : state == .active ? CLColor.skySoft : CLColor.surface3)
            switch state {
            case .active:
                if reduceMotion {
                    Image(systemName: "ellipsis").font(.system(size: 13, weight: .heavy)).foregroundStyle(CLColor.skyInk)
                } else {
                    ProgressView().controlSize(.small).tint(CLColor.skyInk)
                }
            case .done:
                Image(systemName: "checkmark").font(.system(size: 13, weight: .heavy)).foregroundStyle(CLColor.onFill)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            case .waiting:
                Image(systemName: "checkmark").font(.system(size: 13, weight: .heavy)).foregroundStyle(CLColor.ink4)
            }
        }
        .frame(width: 28, height: 28)
        .padding(.top, 1)
        .accessibilityHidden(true)
    }
}

extension CaptureStepRow where Extra == EmptyView {
    init(state: CaptureStepState, title: String, detail: String?) {
        self.init(state: state, title: title, detail: detail) { EmptyView() }
    }
}
