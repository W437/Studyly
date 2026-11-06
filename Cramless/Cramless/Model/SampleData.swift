#if DEBUG
import Foundation
import SwiftData

/// The demo world for the harness (`CRAMLESS_UITEST=1`): Maya, a college student with four courses, three
/// exams and three weeks of history. Hand-built and cross-referenced (the streak matches the day records, the
/// reviews match the items' memory, the confusion points at real items), dated relative to the app's clock, and
/// strong but honest: a 12-day streak with one frozen day and a missed day before it, a weak topic, a topic with
/// no material yet. Deterministic: no random numbers, and every id comes from a seeded sequence (`ModelID`), so the
/// world is identical on every launch.
@MainActor
enum SampleData {
    static func seed(into app: AppModel) {
        ModelID.seeded("demo") { build(into: app) }
    }

    private static func build(into app: AppModel) {
        let context = app.context
        guard app.courses.isEmpty else { return }
        let now = app.now
        let cal = app.calendar
        func day(_ offset: Int, hour: Int = 18) -> Date {
            let start = cal.startOfDay(for: now)
            return cal.date(byAdding: .day, value: offset, to: start)!.addingTimeInterval(Double(hour) * 3600)
        }

        // Bio 101: the sample page, a lecture, slides and a Quizlet import.
        let bio = Course(name: "Bio 101", color: .sky, symbol: "leaf", sortOrder: 0, now: day(-40))
        context.insert(bio)
        let topicNames = ["Cell cycle", "Phases of mitosis", "Cytokinesis", "Why mitosis matters", "Chromosome number",
                          "Cell membrane", "Meiosis", "Mendelian genetics", "DNA replication"]
        var topics: [String: Topic] = [:]
        for name in topicNames { topics[name] = ItemFactory.topic(named: name, in: bio, now: day(-40)) }

        let page = SamplePage.makeSource(in: bio, context: context, now: day(-21))
        page.status = .ready
        let pageModel = page.sortedPages.first
        let (_, sampleItems, _) = SamplePage.checkedItems()
        var byFixtureID: [String: StudyItem] = [:]
        for g in sampleItems {
            let item = ItemFactory.makeItem(from: g, course: bio, topicID: topics[g.topic]?.id, source: page, page: pageModel,
                                            origin: .sample, status: .active, now: day(-21))
            item.checkedAt = day(-21)
            context.insert(item)
            bio.items.append(item)
            byFixtureID[g.id] = item
        }

        let lecture = Source(course: bio, kind: .lecture, title: "Lecture 6: Cell division", status: .ready, now: day(-9))
        context.insert(lecture)
        bio.sources.append(lecture)
        if let notes = try? RelayFixtures.load(LectureResponse.self, "lecture") {
            lecture.duration = 52 * 60
            lecture.segments = [
                TranscriptSegment(id: "s1", start: 178, end: 190, text: "OK, so last time we finished interphase. Today: what actually happens when the cell divides."),
                TranscriptSegment(id: "s2", start: 192, end: 338, text: "Prophase first. The chromatin condenses, and you can finally see chromosomes under the microscope."),
                TranscriptSegment(id: "s3", start: 340, end: 458, text: "Then the nuclear envelope breaks down and the spindle starts forming from the centrosomes."),
                TranscriptSegment(id: "s4", start: 460, end: 723, text: "Metaphase is the easy one to spot: everything lines up along the middle, the metaphase plate."),
                TranscriptSegment(id: "s5", start: 725, end: 918, text: "This one will be on the midterm, by the way: anaphase is where the sister chromatids get pulled apart."),
                TranscriptSegment(id: "s6", start: 920, end: 1040, text: "And telophase is basically prophase in reverse. The nuclear envelopes re-form around each set."),
            ]
            lecture.flags = [ExamFlag(id: "f1", time: 725, reason: .phrase, text: notes.examFlags.first?.text ?? "")]
            lecture.notes = LectureNotes(summary: notes.summary, sections: notes.sections, keyTerms: notes.keyTerms, origin: "cloud")
            for g in notes.items {
                let item = ItemFactory.makeItem(from: g, course: bio, topicID: topics[g.topic]?.id, source: lecture, page: nil,
                                                origin: .cloud, status: .active, now: day(-9))
                item.checkedAt = day(-9)
                context.insert(item)
                bio.items.append(item)
            }
        }

        let slides = Source(course: bio, kind: .pdf, title: "Week 5 slides", status: .ready, now: day(-14))
        context.insert(slides)
        bio.sources.append(slides)
        let slideTexts = [
            "The cell membrane\nA phospholipid bilayer with proteins embedded in it.\nIt is selectively permeable: it controls what enters and leaves the cell.\nDiffusion: particles move from high to low concentration.\nOsmosis: water moves across a membrane from dilute to concentrated solution.",
            "Meiosis\nTwo divisions make four cells, each with half the chromosomes of the parent.\nCrossing over in prophase I swaps pieces between homologous chromosomes.\nAnaphase I separates homologous pairs; anaphase II separates sister chromatids.\nMeiosis makes gametes: eggs and sperm.",
        ]
        for (i, text) in slideTexts.enumerated() {
            let lines = text.split(separator: "\n").enumerated().map { TextLine(id: "p\(i).l\($0.offset)", text: String($0.element), box: nil) }
            let p = SourcePage(source: slides, pageIndex: i, label: "\(i + 11)", text: text, lines: lines)
            context.insert(p)
            slides.pages.append(p)
        }

        let quizlet = Source(course: bio, kind: .quizlet, title: "Unit 3 terms (Quizlet)", status: .ready, now: day(-30))
        context.insert(quizlet)
        bio.sources.append(quizlet)

        func add(_ course: Course, _ source: Source?, _ topic: String, _ kind: ItemKind, _ prompt: String, _ answer: String,
                 choices: [Choice] = [], ideas: [KeyIdea] = [], cloze: ClozeSpec? = nil, anchors: [String] = [],
                 page: SourcePage? = nil, origin: ItemOrigin = .cloud) {
            let t = ItemFactory.topic(named: topic, in: course, now: day(-30))
            let g = GeneratedItem(id: ModelID.make().uuidString, kind: kind, topic: topic, prompt: prompt, answer: answer,
                                  keyIdeas: ideas, choices: choices, cloze: cloze, anchors: anchors)
            let item = ItemFactory.makeItem(from: g, course: course, topicID: t?.id, source: source, page: page,
                                            origin: origin, status: .active, now: day(-30))
            item.checkedAt = origin == .cloud ? day(-30) : nil
            context.insert(item)
            course.items.append(item)
        }
        let slide0 = slides.sortedPages.first, slide1 = slides.sortedPages.last
        add(bio, slides, "Cell membrane", .mcq, "What is the cell membrane made of?", "A phospholipid bilayer with proteins",
            choices: [Choice(text: "A phospholipid bilayer with proteins", correct: true), Choice(text: "Cellulose", correct: false),
                      Choice(text: "A single layer of protein", correct: false), Choice(text: "Chromatin", correct: false)],
            anchors: ["p0.l1"], page: slide0)
        add(bio, slides, "Cell membrane", .flashcard, "Selectively permeable", "Controls what enters and leaves the cell.", anchors: ["p0.l2"], page: slide0)
        add(bio, slides, "Cell membrane", .cloze, "Fill in the word.", "osmosis",
            cloze: ClozeSpec(text: "In {{osmosis}}, water moves across a membrane from a dilute to a concentrated solution."), anchors: ["p0.l4"], page: slide0)
        add(bio, slides, "Cell membrane", .recall, "What is diffusion?", "Particles moving from an area of high concentration to one of low concentration.",
            ideas: [KeyIdea(id: "k1", label: "Particles move", terms: ["particles", "molecules", "move", "spread"]),
                    KeyIdea(id: "k2", label: "From high to low concentration", terms: ["high to low", "higher to lower", "down the gradient", "concentration"])],
            anchors: ["p0.l3"], page: slide0)
        add(bio, slides, "Meiosis", .recall, "How is meiosis different from mitosis?", "Meiosis has two divisions and makes four cells with half the chromosomes; mitosis makes two identical cells.",
            ideas: [KeyIdea(id: "k1", label: "Two divisions", terms: ["two divisions", "divides twice", "twice"]),
                    KeyIdea(id: "k2", label: "Four cells", terms: ["four cells", "4 cells", "four"]),
                    KeyIdea(id: "k3", label: "Half the chromosomes", terms: ["half", "haploid", "half the chromosomes"])],
            anchors: ["p1.l1"], page: slide1)
        add(bio, slides, "Meiosis", .mcq, "What does anaphase I separate?", "Homologous pairs",
            choices: [Choice(text: "Homologous pairs", correct: true), Choice(text: "Sister chromatids", correct: false),
                      Choice(text: "Centromeres", correct: false), Choice(text: "Nuclear envelopes", correct: false)],
            anchors: ["p1.l3"], page: slide1)
        add(bio, slides, "Meiosis", .mcq, "What does anaphase II separate?", "Sister chromatids",
            choices: [Choice(text: "Homologous pairs", correct: false), Choice(text: "Sister chromatids", correct: true),
                      Choice(text: "Gametes", correct: false), Choice(text: "Spindle fibres", correct: false)],
            anchors: ["p1.l3"], page: slide1)
        add(bio, slides, "Meiosis", .flashcard, "Crossing over", "Homologous chromosomes swap pieces in prophase I.", anchors: ["p1.l2"], page: slide1)
        add(bio, quizlet, "Cell cycle", .flashcard, "Interphase", "The longest part of the cell cycle, when the cell grows and copies its DNA.", origin: .quizlet)
        add(bio, quizlet, "Cell cycle", .flashcard, "S phase", "The part of interphase when DNA is replicated.", origin: .quizlet)
        add(bio, quizlet, "Cell cycle", .flashcard, "G1 phase", "The first growth phase of interphase.", origin: .quizlet)
        add(bio, quizlet, "Mendelian genetics", .flashcard, "Genotype", "The alleles an organism has, such as Bb.", origin: .quizlet)
        add(bio, quizlet, "Mendelian genetics", .flashcard, "Phenotype", "The trait you can observe, such as brown eyes.", origin: .quizlet)
        add(bio, quizlet, "Mendelian genetics", .flashcard, "Homozygous", "Two identical alleles for a gene, such as BB or bb.", origin: .quizlet)
        add(bio, quizlet, "Mendelian genetics", .flashcard, "Dominant allele", "An allele that shows in the phenotype even with one copy.", origin: .quizlet)

        let midterm = Exam(course: bio, title: "Bio 101 Midterm", date: day(23, hour: 9),
                           format: ExamFormat(multipleChoice: true, shortAnswer: true, essay: false), targetReadiness: 0.9, now: day(-21))
        context.insert(midterm)
        bio.exams.append(midterm)

        if let a = byFixtureID["i4"], let b = byFixtureID["i11"], let fixes = try? RelayFixtures.load(ConfusionsResponse.self, "confusions"),
           let first = fixes.confusions.first {
            var fixIDs: [UUID] = []
            for g in first.questions {
                let item = ItemFactory.makeItem(from: g, course: bio, topicID: topics[g.topic]?.id, source: page, page: pageModel,
                                                origin: .cloud, status: .active, now: day(-2))
                context.insert(item)
                bio.items.append(item)
                fixIDs.append(item.id)
            }
            let confusion = Confusion(course: bio, name: first.name, explanation: first.explanation, itemIDs: [a.id, b.id],
                                      fix: ConfusionFix(lesson: first.lesson, itemIDs: fixIDs), missCount: 3, now: day(-2))
            context.insert(confusion)
            bio.confusions.append(confusion)
        }

        // Chem 110: a quiz on Friday, not ready yet.
        let chem = Course(name: "Chem 110", color: .tangerine, symbol: "flask", sortOrder: 1, now: day(-30))
        context.insert(chem)
        let chemNotes = Source(course: chem, kind: .text, title: "Chapter 3 notes", status: .ready, now: day(-12))
        context.insert(chemNotes)
        chem.sources.append(chemNotes)
        add(chem, chemNotes, "Moles", .flashcard, "Avogadro's number", "6.022 × 10²³ particles in one mole.")
        add(chem, chemNotes, "Moles", .mcq, "How many moles are in 36 g of water (18 g/mol)?", "2",
            choices: [Choice(text: "2", correct: true), Choice(text: "0.5", correct: false), Choice(text: "18", correct: false), Choice(text: "648", correct: false)])
        add(chem, chemNotes, "Moles", .cloze, "Fill in the unit.", "grams per mole", cloze: ClozeSpec(text: "Molar mass is measured in {{grams per mole}}."))
        add(chem, chemNotes, "Stoichiometry", .recall, "What does a balanced equation tell you about the reaction?",
            "The ratio of moles of each reactant and product.",
            ideas: [KeyIdea(id: "k1", label: "Mole ratio", terms: ["ratio", "mole ratio", "proportion"]),
                    KeyIdea(id: "k2", label: "Reactants and products", terms: ["reactant", "product", "each substance"])])
        add(chem, chemNotes, "Stoichiometry", .mcq, "In 2H₂ + O₂ → 2H₂O, how many moles of water come from 4 moles of H₂?", "4",
            choices: [Choice(text: "2", correct: false), Choice(text: "4", correct: true), Choice(text: "8", correct: false), Choice(text: "1", correct: false)])
        add(chem, chemNotes, "Limiting reagents", .flashcard, "Limiting reagent", "The reactant that runs out first and limits how much product forms.")
        add(chem, chemNotes, "Limiting reagents", .recall, "How do you find the limiting reagent?",
            "Convert each reactant to moles, divide by its coefficient, and the smallest result is the limiting reagent.",
            ideas: [KeyIdea(id: "k1", label: "Convert to moles", terms: ["moles", "convert"]),
                    KeyIdea(id: "k2", label: "Compare using the ratio", terms: ["ratio", "coefficient", "divide"]),
                    KeyIdea(id: "k3", label: "Smallest runs out first", terms: ["smallest", "runs out", "least"])])
        let chemQuiz = Exam(course: chem, title: "Chem 110 Quiz", date: day(2, hour: 10),
                            format: ExamFormat(multipleChoice: true, shortAnswer: false), targetReadiness: 0.8, now: day(-10))
        context.insert(chemQuiz)
        chem.exams.append(chemQuiz)

        // AP Psychology: months away, barely started.
        let psych = Course(name: "AP Psychology", color: .mint, symbol: "brain.head.profile", sortOrder: 2, now: day(-25))
        context.insert(psych)
        let myers = Source(course: psych, kind: .pdf, title: "Myers, chapter 7", status: .ready, now: day(-20))
        context.insert(myers)
        psych.sources.append(myers)
        add(psych, myers, "Memory", .flashcard, "Encoding", "Getting information into memory.")
        add(psych, myers, "Memory", .flashcard, "Retrieval", "Getting information out of memory.")
        add(psych, myers, "Memory", .mcq, "Which effect says we remember the first and last items of a list best?", "Serial position effect",
            choices: [Choice(text: "Serial position effect", correct: true), Choice(text: "Spacing effect", correct: false),
                      Choice(text: "Testing effect", correct: false), Choice(text: "Priming", correct: false)])
        add(psych, myers, "Memory", .recall, "Why does spacing out study beat cramming?", "Spaced retrieval strengthens long-term memory more than massed practice.",
            ideas: [KeyIdea(id: "k1", label: "Spaced practice", terms: ["spaced", "spacing", "over time", "spread out"]),
                    KeyIdea(id: "k2", label: "Long-term retention", terms: ["long-term", "remember longer", "retention"])])
        add(psych, myers, "Learning", .flashcard, "Classical conditioning", "Learning to link two stimuli, as in Pavlov's dogs.")
        add(psych, myers, "Learning", .flashcard, "Operant conditioning", "Learning from the consequences of behavior: reinforcement and punishment.")
        add(psych, myers, "Learning", .mcq, "Taking away a chore after good grades is…", "Negative reinforcement",
            choices: [Choice(text: "Negative reinforcement", correct: true), Choice(text: "Positive punishment", correct: false),
                      Choice(text: "Negative punishment", correct: false), Choice(text: "Positive reinforcement", correct: false)])
        add(psych, myers, "Biological bases", .flashcard, "Neurotransmitter", "A chemical messenger that crosses the synapse between neurons.")
        add(psych, myers, "Biological bases", .flashcard, "Myelin sheath", "Fatty layer that speeds up neural impulses.")
        add(psych, myers, "Biological bases", .flashcard, "Amygdala", "Brain structure linked to emotion, especially fear.")
        let ap = Exam(course: psych, title: "AP Psych Exam", date: day(196, hour: 8),
                      format: ExamFormat(multipleChoice: true, shortAnswer: true, essay: true), targetReadiness: 0.9, now: day(-25))
        context.insert(ap)
        psych.exams.append(ap)

        // Spanish II: vocabulary, no exam set.
        let spanish = Course(name: "Spanish II", color: .sun, symbol: "character.bubble", sortOrder: 3, now: day(-60))
        context.insert(spanish)
        let vocab = Source(course: spanish, kind: .quizlet, title: "Unidad 4 vocabulario (Quizlet)", status: .ready, now: day(-50))
        context.insert(vocab)
        spanish.sources.append(vocab)
        for (es, en) in [("la biblioteca", "the library"), ("el examen", "the exam"), ("aprobar", "to pass (an exam)"),
                         ("suspender", "to fail (an exam)"), ("los apuntes", "the notes"), ("repasar", "to review"),
                         ("la tarea", "the homework"), ("el horario", "the schedule"), ("la nota", "the grade"),
                         ("estudiar", "to study")] {
            add(spanish, vocab, "Unidad 4", .flashcard, es, en, origin: .quizlet)
        }

        // Memory: deterministic per item, shaped by topic so the topics read strong, middling and weak.
        let strength: [String: Double] = [
            "Cell cycle": 0.95, "Phases of mitosis": 0.9, "Cytokinesis": 0.86, "Why mitosis matters": 0.9,
            "Chromosome number": 0.9, "Cell membrane": 0.8, "Meiosis": 0.66, "Mendelian genetics": 0.5,
            "Moles": 0.62, "Stoichiometry": 0.45, "Limiting reagents": 0.3, "Memory": 0.55, "Learning": 0.35,
            "Biological bases": 0, "Unidad 4": 0.8,
        ]
        let topicByID = Dictionary(uniqueKeysWithValues: [bio, chem, psych, spanish].flatMap(\.topics).map { ($0.id, $0.name) })
        let w20 = 0.1542
        let factor = pow(0.9, -1 / w20) - 1
        var logs: [(Date, StudyItem, Rating)] = []
        let all = [bio, chem, psych, spanish].flatMap(\.items).filter { $0.status == .active }
        for (index, item) in all.enumerated() {
            let base = strength[item.topicID.flatMap { topicByID[$0] } ?? ""] ?? 0.5
            // Lecture items, the confusion's fix questions (made two days ago) and a third of the weakest topic stay
            // new: material not studied yet.
            let isFixItem = item.origin == .cloud && item.createdAt > day(-3)
            if base == 0 || isFixItem || (item.origin == .cloud && item.sourceRef?.label.hasPrefix("Lecture") == true) || (base < 0.4 && index % 3 == 0) {
                continue
            }
            let wobble = Double((index * 37) % 11 - 5) / 100
            let target = min(0.98, max(0.35, base + wobble))
            let elapsed = Double(1 + (index * 7) % 9)
            let stability = factor * elapsed / (pow(target, -1 / w20) - 1)
            let last = day(-Int(elapsed), hour: 17 + index % 4)
            let reps = 2 + index % 4
            let lapses = target < 0.6 ? 1 + index % 2 : (index % 5 == 0 ? 1 : 0)
            item.memory = MemoryState(state: .review, stability: stability, difficulty: 4 + Double(index % 5) + (target < 0.6 ? 2 : 0),
                                      due: last.addingTimeInterval(stability * 86_400), lastReview: last,
                                      reps: reps, lapses: lapses, step: 0)
            for r in 0..<reps {
                let when = day(-Int(elapsed) - (reps - r - 1) * 3, hour: 17 + index % 4)
                let rating: Rating = (r == 1 && lapses > 0) ? .again : (r == reps - 1 && target < 0.6 ? .hard : .good)
                logs.append((when, item, rating))
            }
        }
        // Each item's earlier reviews are of a learned card (its first one of a new card), so retention statistics
        // have something to read.
        var seenBefore: Set<UUID> = []
        for (when, item, rating) in logs.sorted(by: { $0.0 < $1.0 }) {
            var before = MemoryState.new
            if seenBefore.contains(item.id) {
                before = MemoryState(state: .review, stability: max(1, item.stability * 0.6), difficulty: item.difficulty,
                                     due: when, lastReview: when.addingTimeInterval(-3 * 86_400), reps: 1, lapses: 0, step: 0)
            }
            seenBefore.insert(item.id)
            let log = ReviewLog(itemID: item.id, courseID: item.course?.id, sessionID: nil, reviewedAt: when, rating: rating,
                                score: item.kind.isOwnWords ? (rating == .good ? 0.85 : rating == .hard ? 0.6 : 0.2) : -1,
                                answer: nil, gradedBy: item.kind.isOwnWords ? "cloud" : "person", durationMs: Int(item.kind.typicalSeconds * 1000),
                                before: before, after: item.memory, elapsedDays: 3, scheduledDays: 3)
            context.insert(log)
        }

        // Days: a 12-day streak up to yesterday (day -6 covered by a freeze), a missed day before it, and an
        // uneven fortnight before that.
        for offset in -30...(-1) {
            let date = day(offset, hour: 0)
            let key = cal.dayKey(for: date)
            let studied = offset >= -12 ? offset != -6 : (offset != -13 && ((offset * 7) % 10 + 10) % 10 < 7)
            let frozen = offset == -6
            let minutes = studied ? 9 + (abs(offset) * 5) % 11 : 0
            let record = DayRecord(dayKey: key, day: cal.startOfDay(for: date), studySeconds: Double(minutes * 60),
                                   itemsReviewed: studied ? 14 + (abs(offset) * 3) % 15 : 0, sessions: studied ? 1 : 0,
                                   frozen: frozen)
            context.insert(record)
            if studied {
                let s = StudySession(kind: .daily, startedAt: day(offset, hour: 18), plannedSeconds: 900)
                s.endedAt = s.startedAt.addingTimeInterval(Double(minutes * 60))
                s.activeSeconds = Double(minutes * 60)
                s.itemCount = record.itemsReviewed
                s.correctCount = Int(Double(record.itemsReviewed) * 0.8)
                context.insert(s)
            }
        }

        // A tutor chat about mitosis vs cytokinesis, citing the sample page.
        let thread = ChatThread(courseID: bio.id, title: "Mitosis vs cytokinesis", mode: .hints, now: day(-1, hour: 20))
        context.insert(thread)
        let q = ChatMessage(thread: thread, role: .user, text: "What's the difference between mitosis and cytokinesis?", now: day(-1, hour: 20))
        let a = ChatMessage(thread: thread, role: .assistant,
                            text: "Let's work it out from your page. p. 87 says mitosis copies the DNA and separates it into two new nuclei. Then something else happens to the rest of the cell. What does the page say is divided in cytokinesis?",
                            citations: [Citation(id: "c1", sourceID: page.id, pageIndex: 0, start: nil,
                                                 quote: "During mitosis, the genetic material (DNA) is copied and equally separated into two new nuclei.",
                                                 label: "Textbook p. 87")],
                            origin: "cloud", now: day(-1, hour: 20).addingTimeInterval(8))
        context.insert(q)
        context.insert(a)
        thread.messages.append(contentsOf: [q, a])

        var s = app.settings
        s.firstName = s.firstName.isEmpty ? "Maya" : s.firstName
        s.goal = .aceExams
        s.level = .college
        s.notesLocations = [.paper, .slides, .lectures, .flashcardApps]
        s.dailyMinutes = 15
        s.onboardingCompleted = true
        app.settings = s
        // "Recent" on the Library: two sources opened on this iPhone lately.
        app.noteOpened(sourceID: slides.id, at: day(0, hour: 8))
        app.noteOpened(sourceID: lecture.id, at: day(-3))
        try? context.save()
        _ = app.save()
    }
}
#endif
