import SwiftUI

/// A page of a source, with the lines a question came from marked. Pushed from source chips everywhere, so it opens
/// on `pageIndex` with `highlight`'s lines marked; pages swipe sideways; pinch or double-tap zooms (the image is
/// decoded again at the zoomed size); "Recognised text" shows the page's lines; below are the questions from the
/// page (tap one to mark its lines). Typed and PDF-text pages show their lines as text, marked the same way.
struct SourcePageView: View {
    let sourceID: UUID
    let pageIndex: Int
    let highlight: [String]

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var shown: Int?
    @State private var showsText = false
    @State private var markedItem: UUID?
    @State private var zoomed = false
    @State private var revealed = false

    init(sourceID: UUID, pageIndex: Int, highlight: [String]) {
        self.sourceID = sourceID
        self.pageIndex = pageIndex
        self.highlight = highlight
        _shown = State(initialValue: pageIndex)
    }

    var body: some View {
        let _ = app.revision
        if let source = app.source(sourceID), source.deletedAt == nil, !source.pages.isEmpty {
            content(source)
        } else {
            ContentUnavailableView("This page isn't here anymore", systemImage: "doc.questionmark",
                                   description: Text("Its source was deleted."))
                .clScreenBackground()
        }
    }

    private func content(_ source: Source) -> some View {
        let pages = source.sortedPages.map(PageInfo.init)
        let current = pages.first { $0.index == (shown ?? pageIndex) } ?? pages[0]
        let position = (pages.firstIndex { $0.index == current.index } ?? 0)
        let items = app.questions(from: source, pageIndex: current.index).filter { $0.status != .draft }
        let tint = source.course?.color ?? .sky
        let topicNames = Dictionary(uniqueKeysWithValues: (source.course?.liveTopics ?? []).map { ($0.id, $0.name) })
        let marked = items.first { $0.id == markedItem }
        let marks: (PageInfo) -> Set<String> = { page in
            guard revealed else { return [] }
            if let marked, marked.sourceRef?.pageIndex == page.index { return Set(marked.sourceRef?.anchorIDs ?? []) }
            return marked == nil && page.index == pageIndex ? Set(highlight) : []
        }

        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    pager(pages, marks: marks)
                        .id("page")

                    controls(pages: pages, current: current, position: position)
                        .padding(.horizontal, CLSpace.gutter)
                        .padding(.top, 14)

                    if current.hasImage && showsText {
                        RecognisedText(page: current, marks: marks(current))
                            .padding(.horizontal, CLSpace.gutter)
                            .padding(.top, 14)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        CLSectionHeader(title: items.isEmpty ? "From this page" : "\(CLFormat.count(items.count, "question")) from this page")
                            .id("questions")
                        if items.isEmpty {
                            Text("No questions from this page yet.")
                                .clFont(.subheadline)
                                .foregroundStyle(CLColor.ink2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .clCard(padding: 16)
                        } else {
                            CLList {
                                ForEach(items) { item in
                                    PageQuestionRow(item: item, tint: tint,
                                                    detail: item.topicID.flatMap { topicNames[$0] } ?? item.kind.displayName,
                                                    isMarked: markedItem == item.id,
                                                    canMark: item.sourceRef?.anchorIDs.isEmpty == false) {
                                        CLHaptics.select()
                                        withAnimation(CLMotion.calm) {
                                            markedItem = markedItem == item.id ? nil : item.id
                                            proxy.scrollTo("page", anchor: .top)
                                        }
                                    } edit: {
                                        app.router.present(.editItem(item.id))
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, CLSpace.gutter)
                    .padding(.bottom, 36)
                }
            }
            .scrollDisabled(zoomed)
            .harnessScroll(proxy)
        }
        .clScreenBackground()
        .navigationTitle("p. \(current.label)")
        .navigationSubtitle(source.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isCoverRoot {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
        .animation(CLMotion.settle, value: showsText)
        .onChange(of: shown) { _, _ in
            markedItem = nil
            zoomed = false
        }
        .task {
            // The marks arrive a beat after the page, so the eye catches them landing.
            guard !revealed else { return }
            try? await nap(280)
            withAnimation(CLMotion.calm) { revealed = true }
        }
    }

    // MARK: Pager

    private func pager(_ pages: [PageInfo], marks: @escaping (PageInfo) -> Set<String>) -> some View {
        ScrollViewReader { proxy in
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: 0) {
                ForEach(pages) { page in
                    Group {
                        if page.hasImage {
                            ZoomablePage(page: page, marks: marks(page), isZoomed: $zoomed)
                        } else {
                            TextPage(page: page, marks: marks(page))
                        }
                    }
                    .padding(.horizontal, CLSpace.gutter)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                    .containerRelativeFrame(.horizontal)
                    .id(page.index)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $shown)
        .scrollIndicators(.hidden)
        .scrollDisabled(zoomed || pages.count < 2)
        .task {
            // A lazy pager doesn't honour its first position on its own: open on the page asked for.
            guard pageIndex != pages.first?.index else { return }
            proxy.scrollTo(pageIndex, anchor: .leading)
            shown = pageIndex
        }
        }
    }

    private func controls(pages: [PageInfo], current: PageInfo, position: Int) -> some View {
        HStack(spacing: 10) {
            if current.hasImage {
                Button {
                    CLHaptics.select()
                    showsText.toggle()
                } label: {
                    ViewThatFits(in: .horizontal) {
                        CLChip(title: "Recognised text", systemImage: "text.viewfinder", selected: showsText).fixedSize()
                        CLChip(title: "Text", systemImage: "text.viewfinder", selected: showsText).fixedSize()
                    }
                    .frame(minHeight: CLMetrics.minHitTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(showsText ? [.isSelected] : [])
                .accessibilityHint(Text("Shows the text read from this page"))
            }
            if zoomed {
                Button {
                    withAnimation(CLMotion.settle) { zoomed = false }
                } label: {
                    CLChip(title: "Fit page", systemImage: "arrow.down.right.and.arrow.up.left")
                        .frame(minHeight: CLMetrics.minHitTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 4)
            if pages.count > 1 {
                CLIconButton(systemImage: "chevron.left", label: "Previous page") { go(to: position - 1, in: pages) }
                    .disabled(position == 0)
                    .opacity(position == 0 ? 0.35 : 1)
                Text("\(position + 1) of \(pages.count)")
                    .clFont(.footnoteEmphasis)
                    .foregroundStyle(CLColor.ink2)
                    .monospacedDigit()
                    .accessibilityLabel(Text("Page \(position + 1) of \(pages.count)"))
                CLIconButton(systemImage: "chevron.right", label: "Next page") { go(to: position + 1, in: pages) }
                    .disabled(position >= pages.count - 1)
                    .opacity(position >= pages.count - 1 ? 0.35 : 1)
            }
        }
    }

    /// Shown over a session or the tutor (a full-screen cover hosts it at the root of its own stack): no back button,
    /// so it brings its own close.
    private var isCoverRoot: Bool {
        guard app.router.cover != nil else { return false }
        let route = Route.sourcePage(sourceID: sourceID, pageIndex: pageIndex, highlight: highlight)
        return !app.router.paths.values.contains { $0.contains(route) }
    }

    private func go(to position: Int, in pages: [PageInfo]) {
        guard pages.indices.contains(position) else { return }
        CLHaptics.select()
        zoomed = false
        withAnimation(CLMotion.settle) { shown = pages[position].index }
    }
}

// MARK: - Page values

/// What a page view needs, copied from the model once per render.
struct PageInfo: Identifiable, Equatable {
    var index: Int
    var label: String
    var imageFileName: String?
    var size: CGSize
    var lines: [TextLine]
    var read: PageRead?

    var id: Int { index }
    var hasImage: Bool { imageFileName != nil }
    var aspect: CGFloat { size.width > 0 && size.height > 0 ? size.width / size.height : 2.0 / 3.0 }

    init(_ page: SourcePage) {
        index = page.pageIndex
        label = page.label
        imageFileName = page.imageFileName
        size = CGSize(width: page.width, height: page.height)
        lines = page.lines
        read = page.read
    }

    /// How the text was read, in plain words.
    var readLine: String? {
        guard let read else { return nil }
        switch read.engine {
        case .vision: return "Read on this iPhone"
        case .pdfText: return "From the PDF's own text"
        case .typed: return "Typed or pasted"
        case .sample: return "The sample page"
        case .cloud: return "Read from the photo in the cloud"
        }
    }
}

// MARK: - Pieces

/// A page image with its marks, zoomable: pinch, double-tap, or the VoiceOver zoom action. The page is laid out at
/// the committed zoom so its image is decoded at that size, and scaled live while pinching.
private struct ZoomablePage: View {
    let page: PageInfo
    let marks: Set<String>
    @Binding var isZoomed: Bool

    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @GestureState private var pinch: CGFloat = 1
    @GestureState private var drag: CGSize = .zero

    private let maxScale: CGFloat = 4
    private let doubleTapScale: CGFloat = 2.5

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let shown = clamp(CGSize(width: offset.width + drag.width, height: offset.height + drag.height),
                              scale: max(1, scale * pinch), in: size)
            PageCanvas(fileName: page.imageFileName, pageSize: page.size, lines: page.lines, highlighted: marks)
                .frame(width: size.width * scale, height: size.height * scale)
                .scaleEffect(pinch)
                .offset(shown)
                .frame(width: size.width, height: size.height)
                .clipShape(Rectangle().inset(by: scale > 1 || pinch != 1 ? 0 : -24))
                .contentShape(Rectangle())
                .gesture(magnify(in: size))
                .simultaneousGesture(pan(in: size), including: scale > 1 ? .all : .subviews)
                // Simultaneous, so the pinch recogniser never swallows it.
                .simultaneousGesture(SpatialTapGesture(count: 2, coordinateSpace: .local).onEnded { value in
                    CLHaptics.select()
                    withAnimation(CLMotion.settle) { toggleZoom(at: value.location, in: size) }
                })
        }
        .aspectRatio(page.aspect, contentMode: .fit)
        .animation(CLMotion.calm, value: marks)
        .onChange(of: isZoomed) { _, zoomed in
            guard !zoomed, scale != 1 else { return }
            withAnimation(CLMotion.settle) { scale = 1; offset = .zero }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Page \(page.label)"))
        .accessibilityValue(Text(accessibilityValue))
        .accessibilityHint(Text("Zoomable"))
        .accessibilityZoomAction { action in
            withAnimation(CLMotion.settle) {
                switch action.direction {
                case .zoomIn: scale = min(maxScale, scale + 1)
                case .zoomOut: scale = max(1, scale - 1)
                @unknown default: break
                }
                if scale == 1 { offset = .zero }
                isZoomed = scale > 1
            }
        }
    }

    private var accessibilityValue: String {
        let marked = page.lines.filter { marks.contains($0.id) }.map(\.text)
        guard !marked.isEmpty else { return "" }
        return "Marked: " + marked.joined(separator: " ")
    }

    private func magnify(in size: CGSize) -> some Gesture {
        MagnifyGesture()
            .updating($pinch) { value, state, _ in
                state = min(maxScale / scale, max(0.6 / scale, value.magnification))
            }
            .onEnded { value in
                let next = min(maxScale, max(1, scale * value.magnification))
                withAnimation(CLMotion.settle) {
                    offset = clamp(CGSize(width: offset.width * next / scale, height: offset.height * next / scale), scale: next, in: size)
                    scale = next
                    if next == 1 { offset = .zero }
                }
                isZoomed = next > 1
            }
    }

    private func pan(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .updating($drag) { value, state, _ in state = value.translation }
            .onEnded { value in
                offset = clamp(CGSize(width: offset.width + value.translation.width, height: offset.height + value.translation.height),
                               scale: scale, in: size)
            }
    }

    private func toggleZoom(at location: CGPoint, in size: CGSize) {
        if scale > 1 {
            scale = 1
            offset = .zero
            isZoomed = false
        } else {
            let next = doubleTapScale
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            offset = clamp(CGSize(width: (center.x - location.x) * next, height: (center.y - location.y) * next), scale: next, in: size)
            scale = next
            isZoomed = true
        }
    }

    /// Keeps the zoomed page covering the frame.
    private func clamp(_ proposed: CGSize, scale: CGFloat, in size: CGSize) -> CGSize {
        let maxX = max(0, (size.width * scale - size.width) / 2)
        let maxY = max(0, (size.height * scale - size.height) / 2)
        return CGSize(width: min(maxX, max(-maxX, proposed.width)), height: min(maxY, max(-maxY, proposed.height)))
    }
}

/// A page with no image (typed, pasted or PDF text): its lines on a sheet, the marked ones highlighted.
private struct TextPage: View {
    let page: PageInfo
    let marks: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(page.lines.enumerated()), id: \.element.id) { index, line in
                MarkedLine(text: line.text, marked: marks.contains(line.id), style: index == 0 ? .headline : .body)
            }
            if let readLine = page.readLine {
                Text(readLine).clFont(.caption).foregroundStyle(CLColor.ink3).padding(.top, 6)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(CLColor.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: CLColor.night.opacity(0.10), radius: 10, y: 4)
        .animation(CLMotion.calm, value: marks)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Page \(page.label)"))
    }
}

/// The text read from an image page, the marked lines highlighted.
private struct RecognisedText: View {
    let page: PageInfo
    let marks: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Recognised text").clFont(.headline).foregroundStyle(CLColor.ink)
                Spacer()
                if let readLine = page.readLine {
                    Text(readLine).clFont(.caption).foregroundStyle(CLColor.ink3)
                }
            }
            if page.lines.isEmpty {
                Text("No text was read from this page.").clFont(.subheadline).foregroundStyle(CLColor.ink2)
            }
            ForEach(page.lines) { line in
                MarkedLine(text: line.text, marked: marks.contains(line.id), style: .subheadline)
            }
        }
        .clCard(padding: 18)
        .textSelection(.enabled)
    }
}

/// One line of a page, with the highlighter behind it when it's marked.
private struct MarkedLine: View {
    let text: String
    let marked: Bool
    var style: CLTextStyle = .body

    var body: some View {
        Text(text)
            .clFont(style)
            .foregroundStyle(CLColor.ink)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(CLColor.markKey)
                    .scaleEffect(x: marked ? 1 : 0, anchor: .leading)
                    .opacity(marked ? 1 : 0)
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityValue(Text(marked ? "Marked" : ""))
    }
}

/// A question from the page: tap to mark its lines on the page; the pencil edits it.
private struct PageQuestionRow: View {
    let item: StudyItem
    let tint: CourseColor
    let detail: String
    let isMarked: Bool
    let canMark: Bool
    var mark: () -> Void
    var edit: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button(action: canMark ? mark : edit) {
                LibraryItemRow(kind: item.kind,
                               prompt: item.kind == .cloze ? (item.cloze.map { LibraryFormat.clozeDisplay($0.text) } ?? item.prompt) : item.prompt,
                               detail: isMarked ? "Marked on the page" : detail, tint: tint,
                               suspended: item.status == .suspended)
                    .padding(.leading, 16)
                    .padding(.vertical, 10)
            }
            .buttonStyle(LibraryRowButtonStyle())
            .accessibilityHint(Text(canMark ? "Marks its lines on the page" : "Opens the question to edit"))
            .accessibilityAddTraits(isMarked ? [.isSelected] : [])
            Button(action: edit) {
                Image(systemName: "pencil")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(CLColor.ink2)
                    .frame(width: CLMetrics.minHitTarget, height: CLMetrics.minHitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 8)
            .accessibilityLabel(Text("Edit question"))
        }
        .background(isMarked ? CLColor.sunSoft : Color.clear)
    }
}
