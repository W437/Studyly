import SwiftUI

/// Label a diagram on the person's own page: the page is drawn through `PageCanvas`, zoomed to the labels, with
/// each printed label hidden behind a numbered slot. Tap a slot, then pick its label from the bank (the next
/// empty slot is picked for you). Check marks each slot right or shows the right label.
struct DiagramQuestionView: View {
    let runner: SessionRunner
    let entry: SessionEntry
    let item: StudyItem
    /// DEBUG: fill the slots on appear and check (`"right"` or `"wrong"`), or just fill them (`"filled"`).
    var autoFill: String? = nil
    /// DEBUG: press Continue this many milliseconds after the panel shows (session autoplay).
    var autoContinue: Int? = nil

    @Environment(AppModel.self) private var app

    @State private var page: PageInfo?
    @State private var placed: [String: String] = [:]
    @State private var selected: String?
    @State private var bank: [String] = []
    @State private var grade: GradeOutcome?
    @State private var saved = false
    /// The run this answer makes, fixed when the verdict lands.
    @State private var run = 0
    @State private var durationMs = 0

    struct PageInfo: Equatable {
        var fileName: String?
        var size: CGSize
        var lines: [TextLine]
    }

    private var targets: [DiagramTarget] { item.diagram?.targets ?? [] }

    var body: some View {
        QuestionScroll {
            QuestionCard {
                QuestionHeader(item: item, entry: entry, topic: runner.topicName(entry.topicID))
                Text(item.prompt)
                    .clFont(.title2)
                    .foregroundStyle(CLColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
                    .accessibilityAddTraits(.isHeader)
                if let page {
                    canvas(page)
                        .padding(.top, 16)
                        .padding(.horizontal, -8)
                }
                if grade == nil {
                    labelBank
                        .padding(.top, 16)
                } else if let panel {
                    AccessibilityOnly { FeedbackDetails(feedback: panel).padding(.top, 10) }
                }
            }
            AccessibilityOnly { secondary }
        }
        .sessionFooter(feedback: panel, primary: { footer }, secondary: { secondary })
        .onAppear(perform: prepare)
        .task {
            app.readAloud(question: item)
            guard let autoFill else { return }
            do { try await nap(500) } catch { return }
            var labels = targets.map(\.label)
            if autoFill == "wrong", labels.count > 1 { labels.swapAt(labels.count - 2, labels.count - 1) }
            for (target, label) in zip(targets, labels) { placed[target.anchorID] = label }
            bank = []
            selected = nil
            guard autoFill != "filled" else { return }
            check()
            guard let autoContinue else { return }
            do { try await nap(autoContinue) } catch { return }
            commit()
        }
    }

    // MARK: The page

    private func canvas(_ page: PageInfo) -> some View {
        let aspect = page.size.height > 0 ? page.size.width / page.size.height : 2.0 / 3.0
        let region = Self.region(for: targets, pageAspect: aspect, lines: page.lines)
        let regionAspect = (region.width * aspect) / max(0.01, region.height)
        return GeometryReader { geo in
            let fullWidth = geo.size.width / region.width
            let fullHeight = fullWidth / aspect
            let room = Self.slotRoom(for: targets)
            PageCanvas(fileName: page.fileName, pageSize: page.size, lines: page.lines,
                       slots: targets.map(\.anchorID)) { line in
                slot(line.id, maxWidth: max(48, (room[line.id] ?? 1) * fullWidth - 4))
            }
            .frame(width: fullWidth, height: fullHeight)
            .offset(x: -region.minX * fullWidth, y: -region.minY * fullHeight)
        }
        .aspectRatio(regionAspect, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(CLColor.hairline, lineWidth: 1))
        .dynamicTypeSize(...DynamicTypeSize.large)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Diagram from your page")
    }

    /// The part of the page around the labels, with room for what they label below them; at least half the page
    /// wide, and never taller than it is wide (`pageAspect` is the page's width over its height). Its top and bottom
    /// edges move into the gaps between the page's other text lines, so no line is cut in half.
    static func region(for targets: [DiagramTarget], pageAspect: Double = 2.0 / 3.0, lines: [TextLine] = []) -> CGRect {
        guard !targets.isEmpty else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        let top = targets.map(\.box.y).min() ?? 0
        let bottom = targets.map { $0.box.y + $0.box.h }.max() ?? 1
        var x0 = (targets.map(\.box.x).min() ?? 0) - 0.08
        var x1 = (targets.map { $0.box.x + $0.box.w }.max() ?? 1) + 0.08
        if x1 - x0 < 0.5 {
            let mid = (x0 + x1) / 2
            x0 = mid - 0.25; x1 = mid + 0.25
        }
        x0 = max(0, x0); x1 = min(1, x1)
        let ids = Set(targets.map(\.anchorID))
        let others = lines.compactMap { line -> NormRect? in
            guard !ids.contains(line.id), let box = line.box, box.x < x1, box.x + box.w > x0 else { return nil }
            return box
        }
        // Top: room above the labels for their slots; then below any line the edge would cut (if that still
        // leaves the room), else above it.
        var y0 = max(0, top - 0.04)
        for _ in 0..<6 {
            guard let cut = others.first(where: { $0.y < y0 && $0.y + $0.h > y0 }) else { break }
            let below = cut.y + cut.h + 0.004
            y0 = below < top - 0.035 ? below : max(0, cut.y - 0.004)
        }
        // Bottom: room for the drawing under the labels, pulled up above any line the edge would cut.
        var y1 = min(1, bottom + 0.16)
        if (y1 - y0) > (x1 - x0) * pageAspect { y1 = y0 + (x1 - x0) * pageAspect }
        for _ in 0..<12 {
            guard let cut = others.first(where: { $0.y < y1 && $0.y + $0.h > y1 }) else { break }
            let above = cut.y - 0.004
            y1 = above > bottom + 0.04 ? above : min(1, cut.y + cut.h + 0.004)
        }
        return CGRect(x: x0, y: y0, width: max(0.05, x1 - x0), height: max(0.05, y1 - y0))
    }

    /// How wide each slot may grow, in page widths: the distance to the nearest label on the same row, so slots
    /// never overlap (the whole page width when a label has the row to itself).
    static func slotRoom(for targets: [DiagramTarget]) -> [String: Double] {
        var room: [String: Double] = [:]
        for target in targets {
            let cx = target.box.x + target.box.w / 2
            let neighbours = targets.filter { other in
                other.anchorID != target.anchorID
                    && other.box.y < target.box.y + target.box.h + 0.01 && other.box.y + other.box.h > target.box.y - 0.01
            }
            let nearest = neighbours.map { abs($0.box.x + $0.box.w / 2 - cx) }.min()
            room[target.anchorID] = nearest ?? 1
        }
        return room
    }

    private func slot(_ anchorID: String, maxWidth: CGFloat) -> some View {
        let number = (targets.firstIndex { $0.anchorID == anchorID } ?? 0) + 1
        let label = placed[anchorID]
        let isSelected = selected == anchorID && grade == nil
        let result = resultFor(anchorID)
        let correctLabel = targets.first { $0.anchorID == anchorID }?.label ?? ""
        return Button { tapSlot(anchorID) } label: {
            Group {
                if let result {
                    HStack(spacing: 2) {
                        Image(systemName: result ? "checkmark" : "xmark")
                            .font(.system(size: 9, weight: .heavy))
                        Text(result ? (label ?? correctLabel) : correctLabel)
                    }
                } else if let label {
                    Text(label)
                } else {
                    Text("\(number)")
                        .foregroundStyle(CLColor.night.opacity(isSelected ? 0.9 : 0.45))
                }
            }
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(CLColor.night)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 5)
            .frame(minWidth: min(56, maxWidth), maxWidth: maxWidth, minHeight: 30)
            .fixedSize(horizontal: false, vertical: true)
            .background {
                ZStack {
                    CLColor.paper
                    if let result { (result ? CLColor.mint : CLColor.rose).opacity(0.28) }
                    else if isSelected { CLColor.tangerine.opacity(0.16) }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(slotBorder(result: result, selected: isSelected, filled: label != nil),
                                  style: StrokeStyle(lineWidth: isSelected || result != nil ? 2 : 1.5,
                                                     dash: label == nil && result == nil && !isSelected ? [4, 3] : []))
            }
            .shadow(color: CLColor.night.opacity(0.18), radius: 3, y: 1)
            .padding(7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .allowsHitTesting(grade == nil)
        .accessibilityLabel("Box \(number), \(positionWords(anchorID))")
        .accessibilityValue(slotValue(anchorID, label: label, result: result, correct: correctLabel))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func slotBorder(result: Bool?, selected: Bool, filled: Bool) -> Color {
        if let result { return result ? CLColor.mint : CLColor.rose }
        if selected { return CLColor.tangerine }
        return CLColor.night.opacity(filled ? 0.35 : 0.3)
    }

    private func resultFor(_ anchorID: String) -> Bool? {
        guard let grade, let index = targets.firstIndex(where: { $0.anchorID == anchorID }),
              grade.blankResults.indices.contains(index) else { return nil }
        return grade.blankResults[index]
    }

    private func slotValue(_ anchorID: String, label: String?, result: Bool?, correct: String) -> String {
        if let result {
            return result ? "\(correct), right" : "You put \(label ?? "nothing"); it's \(correct)"
        }
        return label ?? "Empty"
    }

    /// "top left", "middle", for VoiceOver: where the box sits in the picture.
    private func positionWords(_ anchorID: String) -> String {
        guard let box = targets.first(where: { $0.anchorID == anchorID })?.box else { return "" }
        let region = Self.region(for: targets, pageAspect: page.map { $0.size.width / $0.size.height } ?? 2.0 / 3.0,
                                 lines: page?.lines ?? [])
        let x = (box.x + box.w / 2 - region.minX) / region.width
        let y = (box.y + box.h / 2 - region.minY) / region.height
        let horizontal = x < 0.34 ? "left" : x > 0.66 ? "right" : "center"
        let vertical = y < 0.34 ? "top" : y > 0.66 ? "bottom" : "middle"
        return vertical == "middle" && horizontal == "center" ? "center" : "\(vertical) \(horizontal)"
    }

    // MARK: Labels

    private var labelBank: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(bank.isEmpty ? "Every box has a label. Tap a box to change it." : "Tap a box, then its label")
                .clFont(.footnoteEmphasis)
                .foregroundStyle(CLColor.ink3)
            CLFlow(spacing: 8, lineSpacing: 8) {
                ForEach(bank, id: \.self) { label in
                    Button { place(label) } label: {
                        Text(label)
                            .clFont(.subheadlineEmphasis)
                            .foregroundStyle(CLColor.ink)
                            .padding(.horizontal, 14)
                            .frame(minHeight: CLMetrics.minHitTarget)
                            .background(CLColor.surface2, in: Capsule())
                            .overlay(Capsule().strokeBorder(CLColor.surface3, lineWidth: 1))
                    }
                    .buttonStyle(.pressable)
                    .accessibilityHint(selected.map { id in
                        "Puts it in box \((targets.firstIndex { $0.anchorID == id } ?? 0) + 1)"
                    } ?? "")
                }
            }
        }
    }

    /// The answer panel, once checked.
    private var panel: AnswerFeedback? {
        guard let grade else { return nil }
        let outcome = SessionRunner.Outcome(grade.verdict)
        let right = grade.blankResults.filter { $0 }.count
        let message: String
        if grade.isCorrect {
            message = item.explanation.isEmpty ? String(localized: "Every label is in place.") : item.explanation
        } else {
            let lead = String(localized: "\(right) of \(targets.count) right. The red boxes now show the right label.")
            message = [lead, item.explanation].filter { !$0.isEmpty }.joined(separator: " ")
        }
        return AnswerFeedback(tone: FeedbackTone(outcome), headline: SessionCopy.headline(outcome, saved: saved),
                              cap: .verdict(outcome, saved: saved, combo: run),
                              message: message, note: grade.spellingNote, source: item.sourceRef,
                              combo: run)
    }

    @ViewBuilder private var footer: some View {
        if let panel {
            Button("Continue", action: commit)
                .buttonStyle(.cl(.verdict(panel.tone)))
                .keyboardShortcut(.defaultAction)
        } else {
            Button("Check", action: check)
                .buttonStyle(.cl(.primary))
                .disabled(placed.count < targets.count)
        }
    }

    @ViewBuilder private var secondary: some View {
        if let grade {
            if !grade.isCorrect {
                Button {
                    CLHaptics.tap()
                    app.router.present(.explain(itemID: item.id, given: givenLabels.joined(separator: ", ")))
                } label: {
                    Label("Explain my mistake", systemImage: "bubble.left")
                }
                .buttonStyle(.cl(.soft, size: .medium))
            }
            if runner.offersLooksWrong { LooksWrongButton(item: item, given: givenLabels.joined(separator: ", ")) }
        }
    }

    private var givenLabels: [String] { targets.map { placed[$0.anchorID] ?? "" } }

    // MARK: Actions

    private func prepare() {
        guard page == nil, let spec = item.diagram,
              let source = app.source(spec.sourceID),
              let sourcePage = source.sortedPages.first(where: { $0.pageIndex == spec.pageIndex }) else { return }
        page = PageInfo(fileName: sourcePage.imageFileName,
                        size: CGSize(width: max(1, sourcePage.width), height: max(1, sourcePage.height)),
                        lines: sourcePage.lines)
        let labels = targets.map(\.label)
        bank = ChoiceOrder.order(texts: labels, itemID: item.id, day: app.calendar.dayNumber(for: app.now)).map { labels[$0] }
        selected = targets.first?.anchorID
    }

    private func tapSlot(_ anchorID: String) {
        guard grade == nil else { return }
        CLHaptics.select()
        withAnimation(CLMotion.snap) {
            if selected == anchorID, let label = placed[anchorID] {
                // A second tap on a filled, selected box takes its label back.
                placed[anchorID] = nil
                bank.append(label)
            } else {
                selected = anchorID
            }
        }
        runner.hasUnsavedAnswer = !placed.isEmpty
    }

    private func place(_ label: String) {
        guard grade == nil else { return }
        let target = selected ?? targets.first { placed[$0.anchorID] == nil }?.anchorID
        guard let target else { return }
        CLHaptics.select()
        withAnimation(CLMotion.pop) {
            if let old = placed[target] { bank.append(old) }
            placed[target] = label
            bank.removeAll { $0 == label }
            selected = targets.first { placed[$0.anchorID] == nil }?.anchorID
        }
        runner.hasUnsavedAnswer = true
    }

    private func check() {
        guard grade == nil, placed.count == targets.count else { return }
        durationMs = runner.elapsedMs()
        app.stopReadingAloud()
        let outcome = app.ai.instantGrade(app.gradeSubject(for: item), answer: .labels(givenLabels))
        let verdict = SessionRunner.Outcome(outcome.verdict)
        saved = verdict == .right && runner.wouldSave(item)
        run = verdict == .right ? runner.shownRun(adding: .right, kind: item.kind) : 0
        CLFeel.play(runner.cues(for: verdict, item: item, answered: true))
        if saved { runner.flareSave(of: item) }
        withAnimation(CLMotion.snap) {
            grade = outcome
            selected = nil
        }
        runner.setProvisional(verdict)
        let right = outcome.blankResults.filter { $0 }.count
        AccessibilityNotification.Announcement(outcome.isCorrect
            ? "Right. Every label is in place." : "\(right) of \(targets.count) labels right.").post()
    }

    private func commit() {
        guard let grade else { return }
        let rating = AppModel.rating(forScore: grade.score, kind: .diagram, durationMs: durationMs)
        runner.record(rating: rating, score: grade.score, answer: givenLabels.joined(separator: ", "),
                      gradedBy: grade.gradedBy.rawValue, durationMs: durationMs, outcome: SessionRunner.Outcome(grade.verdict))
        CLHaptics.select()
        withAnimation(CLMotion.settle) { runner.advance() }
    }
}
