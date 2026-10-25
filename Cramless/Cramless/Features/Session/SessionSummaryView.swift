import SwiftUI

/// The end of a session, inside the cover: Cap celebrating, minutes and answers, first-try accuracy, the next
/// exam's readiness climbing from before to after, the streak (+1, a freeze earned or used), the topics touched,
/// and a mix-up found in this session offered as a 2-minute fix. Exam eve ends differently: Cap asleep, "That's
/// enough. Sleep is part of studying." A fix ends by saying whether the mix-up is fixed.
///
/// It plays in order: Cap arrives, the session's sound, the numbers count up, the ring climbs, the streak rolls
/// over, and last the celebration `CelebrationPolicy` picked (confetti, Cap's hop and sparkles), if one is earned.
///
/// DEBUG: `CRAMLESS_CELEBRATION=none|nudge|small|medium|big|calm` sets the celebration's size (the reason, and so the
/// title, stays the real one).
struct SessionSummaryView: View {
    let runner: SessionRunner
    let summary: SessionSummary
    let onDone: () -> Void
    /// Starts another session in the same cover (a fix, a bonus round).
    let onStart: (SessionRequest) -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.clReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var ring: Double?
    @State private var streakShown: Int?
    @State private var info: Info?
    @State private var mixUp: MixUp?
    @State private var mixUpHandled = false
    @State private var fixed = false
    @State private var decision = CelebrationDecision.none
    /// How far the numbers have counted: `countStep` of `countSteps`.
    @State private var countStep = 0
    @State private var celebrated = false
    @State private var skyShown = false

    struct Info {
        var examTitle: String?
        var examDate: Date?
        var daysLeft: Int?
        var target: Double = 0.9
        var projected: Double?
        var topics: [TopicRow] = []
        var nextSession: String?
        var bonus: SessionRequest?
        var bonusCount = 0
        var freezeEarned = false
        var freezeUsedYesterday = false
    }

    struct TopicRow: Identifiable {
        var id: UUID
        var name: String
        var missed: Bool
        var detail: String
    }

    struct MixUp {
        var candidate: ConfusionCandidate
        var explained: ConfusionOut?
        var origin: ItemOrigin
        var name: String { explained?.name ?? candidate.name }
        var explanation: String {
            explained?.explanation ?? "You've missed these \(candidate.missCount) times in the last two weeks."
        }
    }

    private var isEve: Bool { summary.stopNow || summary.kind == .examEve }
    private var isFix: Bool { summary.kind == .fix }

    var body: some View {
        QuestionScroll {
            VStack(spacing: 16) {
                hero
                if isEve {
                    eveCard
                } else {
                    stats
                    if hasSkyLine { skyLine }
                    if summary.readinessBefore != nil, summary.readinessAfter != nil, info?.examTitle != nil {
                        readinessCard
                    }
                    if let mixUp, !mixUpHandled {
                        mixUpCard(mixUp)
                            .transition(.opacity.combined(with: .offset(y: 12)))
                    }
                    notes
                }
                AccessibilityOnly { secondary }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
        }
        .sessionFooter(primary: { footer }, secondary: { secondary })
        .overlay {
            if celebrated, let burst = confettiBurst {
                CLConfetti(burst: burst, seed: StableRandom.seed(summary.sessionID, day: 0))
                    .ignoresSafeArea()
            }
        }
        .task { await prepare() }
    }

    // MARK: Hero

    private var hero: some View {
        VStack(spacing: 6) {
            // Cap arrives once the summary knows what it's celebrating (a fix's verdict decides the pose).
            ZStack {
                if info != nil { CapView(capMoment, size: capSize) }
            }
            .frame(width: capSize, height: capSize)
            Text(title)
                .clFont(.brandTitle(32))
                .foregroundStyle(CLColor.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .clFont(.callout)
                .foregroundStyle(CLColor.ink2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    private var capSize: CGFloat { isEve ? 200 : 180 }

    /// Cap arrives, then hops (with sparkles for a medium or big celebration) when the celebration plays.
    private var capMoment: CapMoment {
        if isEve { return .goodnight }
        if isFix && !fixed { return CapMoment(pose: .study, motion: .arrive) }
        guard celebrated else { return .finished }
        var pose = CapPose.celebrate
        if case .streakMilestone = decision.reason { pose = .proud }
        switch decision.size {
        case .none: return .finished
        case .calm: return CapMoment(pose: pose, sparkles: decision.reason != nil)
        case .nudge, .small: return CapMoment(pose: pose, motion: .hop)
        case .medium, .big: return CapMoment(pose: pose, motion: .hop, sparkles: true)
        }
    }

    private var confettiBurst: ConfettiField.Burst? {
        switch decision.size {
        case .small: .puff(CGPoint(x: 0.5, y: 0.24))
        case .medium: .burst(CGPoint(x: 0.5, y: 0.22))
        case .big: .cannons
        case .none, .nudge, .calm: nil
        }
    }

    private var title: LocalizedStringResource {
        if isEve { return "That's enough." }
        if isFix { return fixed ? "Mix-up fixed" : "Getting there" }
        switch decision.reason {
        case .firstSession: return "First session done"
        case .streakMilestone(let days): return "\(days) days in a row"
        case .readinessGoal: return "Goal reached"
        case .perfect: return "All right first time"
        case .mixUpFixed: return "Mix-up fixed"
        case .badge, nil: return "Session done"
        }
    }

    private var subtitle: LocalizedStringResource {
        if isEve { return "Sleep is part of studying." }
        let n = summary.itemsReviewed
        if isFix {
            let pair = runner.built.weakSpots.first.map { SessionCopy.mixUpPair($0.name) } ?? "them"
            return fixed ? "You told \(pair) apart \(summary.correctFirstTry) of \(n) times."
                : "\(summary.correctFirstTry) of \(n) right. Cap will bring these back in a few days."
        }
        if decision.reason == .readinessGoal, let exam = info?.examTitle, let after = summary.readinessAfter {
            return "\(exam) is now \(CLFormat.percent(after)) ready."
        }
        return "\(SessionCopy.questions(n)) in about \(SessionCopy.minutes(max(1, summary.minutes)))"
    }

    // MARK: Stats

    private var stats: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 10))
            : AnyLayout(HStackLayout(spacing: 10))
        let steps = countSteps
        return layout {
            statTile(final: "\(summary.correctFirstTry)/\(summary.itemsReviewed)", label: "right first time",
                     color: CLColor.ink) {
                CLCountingText(value: summary.correctFirstTry, step: countStep, steps: steps) {
                    "\($0)/\(summary.itemsReviewed)"
                }
            }
            if let delta = summary.readinessDelta {
                let points = Int((delta * 100).rounded())
                statTile(final: CLFormat.delta(delta), label: "readiness",
                         color: delta > 0.004 ? CLColor.mintInk : delta < -0.004 ? CLColor.roseInk : CLColor.ink2) {
                    if points > 0 {
                        CLCountingText(value: points, step: countStep, steps: steps) { CLFormat.delta(Double($0) / 100) }
                    } else {
                        Text(verbatim: CLFormat.delta(delta))
                    }
                }
            } else {
                statTile(final: "\(summary.newLearned)", label: "new learned", color: CLColor.skyInk) {
                    CLCountingText(value: summary.newLearned, step: countStep, steps: steps)
                }
            }
            streakTile
        }
        .accessibilityElement(children: .contain)
    }

    /// The count-ups' steps: one per unit of the largest number, at most 12.
    private var countSteps: Int {
        let points = summary.readinessDelta.map { max(0, Int(($0 * 100).rounded())) } ?? summary.newLearned
        return CountUp.steps(to: [summary.correctFirstTry, points])
    }

    /// A number and its label. `final` is what VoiceOver reads, so it never catches a number mid-count.
    private func statTile<Value: View>(final: String, label: String, color: Color,
                                       @ViewBuilder value: () -> Value) -> some View {
        VStack(spacing: 6) {
            value()
                .clFont(.number(24))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .clFont(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(CLColor.ink2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CLColor.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: CLColor.night.opacity(0.05), radius: 1, y: 1)
        .shadow(color: CLColor.night.opacity(0.06), radius: 12, y: 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(final) \(label)"))
    }

    private var streakTile: some View {
        let current = summary.streak.current
        return VStack(spacing: 6) {
            Text("\(streakShown ?? current)")
                .clFont(.number(24))
                .foregroundStyle(CLColor.tangerineInk)
                .contentTransition(.numericText(value: Double(streakShown ?? current)))
            Text("day streak")
                .clFont(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(CLColor.ink2)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CLColor.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if summary.streakExtended {
                CLPill(text: "+1", tone: .tangerine)
                    .offset(x: -6, y: 6)
                    .scaleEffect(streakShown == current ? 1 : 0.4)
                    .opacity(streakShown == current ? 1 : 0)
                    .accessibilityHidden(true)
            }
        }
        .shadow(color: CLColor.night.opacity(0.05), radius: 1, y: 1)
        .shadow(color: CLColor.night.opacity(0.06), radius: 12, y: 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(current) day streak" + (summary.streakExtended ? ", one more day" : ""))
    }

    // MARK: The sky

    private var hasSkyLine: Bool { !isEve && (summary.starsRelit > 0 || summary.starsSaved > 0) }

    /// "Relit 12 stars · 3 saved": what the session did to the memory sky.
    private var skyText: String {
        var parts: [String] = []
        if summary.starsRelit > 0 { parts.append(String(localized: SkyCopy.relit(summary.starsRelit))) }
        if summary.starsSaved > 0 { parts.append(String(localized: SkyCopy.saved(summary.starsSaved))) }
        return parts.joined(separator: " · ")
    }

    /// Closes the summary and shows the sky, which plays the relight on arrival.
    private func openSky() {
        app.router.dismissCover()
        app.router.push(.sky, on: .progress)
    }

    /// A night strip under the numbers that opens the sky, where the stars it names are lit again. It keeps its
    /// room from the start and fades in when the choreography reaches it.
    private var skyLine: some View {
        Button(action: openSky) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(CLColor.sun)
                    .accessibilityHidden(true)
                Text(verbatim: skyText)
                    .clFont(.subheadlineEmphasis)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("See the sky")
                    .clFont(.footnote)
                    .foregroundStyle(.white.opacity(0.7))
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 56)
            .background(CLColor.night, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(CLPressableStyle())
        .opacity(skyShown ? 1 : 0)
        .offset(y: skyShown ? 0 : 10)
        .accessibilityHidden(!skyShown)
        .accessibilityLabel(Text(verbatim: skyText))
        .accessibilityHint(Text("Opens your memory sky"))
    }

    // MARK: Readiness

    private var readinessCard: some View {
        let before = summary.readinessBefore ?? 0
        let after = summary.readinessAfter ?? 0
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 16))
        return layout {
            ReadinessRing(value: ring ?? before, size: 92, lineWidth: 11)
            VStack(alignment: .leading, spacing: 4) {
                Text(info?.examTitle ?? summary.examTitle ?? "Your exam")
                    .clFont(.headline)
                    .foregroundStyle(CLColor.ink)
                Text(readinessLine(before: before, after: after))
                    .clFont(.subheadline)
                    .foregroundStyle(CLColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                if let pill = projectionPill {
                    CLPill(text: .verbatim(pill.text), tone: pill.tone, systemImage: pill.symbol)
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .clCard()
        .accessibilityElement(children: .combine)
    }

    private func readinessLine(before: Double, after: Double) -> String {
        let change = "\(CLFormat.percent(before)) → \(CLFormat.percent(after)) ready"
        guard let days = info?.daysLeft else { return change }
        return "\(change) · \(SessionCopy.unbroken(days == 1 ? "1 day left" : "\(days) days left"))"
    }

    private var projectionPill: (text: String, tone: CLPill.Tone, symbol: String)? {
        guard let info, let projected = info.projected else { return nil }
        let target = CLFormat.percent(info.target)
        if projected >= info.target - 0.0001 {
            return ("On track for \(target)", .mint, "chart.line.uptrend.xyaxis")
        }
        let by = info.examDate.map { " by \($0.formatted(.dateTime.month(.abbreviated).day()))" } ?? ""
        return ("Projected \(CLFormat.percent(projected))\(by)", .sun, "chart.line.uptrend.xyaxis")
    }

    // MARK: Notes (streak, topics, next session)

    @ViewBuilder private var notes: some View {
        let rows = noteRows
        if !rows.isEmpty {
            CLList {
                ForEach(rows) { row in
                    CLRow(icon: row.icon, tint: row.tint, title: .verbatim(row.title), subtitle: .verbatim(row.subtitle)) { EmptyView() }
                }
            }
        }
    }

    private struct NoteRow: Identifiable {
        var id: String
        var icon: String
        var tint: CourseColor
        var title: String
        var subtitle: String
    }

    private var noteRows: [NoteRow] {
        var rows: [NoteRow] = []
        if info?.freezeEarned == true {
            let n = summary.streak.freezesAvailable
            rows.append(NoteRow(id: "freeze", icon: "snowflake", tint: .sky, title: "You earned a streak freeze",
                                subtitle: "You have \(n). A freeze covers a day you miss."))
        } else if info?.freezeUsedYesterday == true, summary.streakExtended {
            rows.append(NoteRow(id: "freeze-used", icon: "snowflake", tint: .sky, title: "A freeze covered yesterday",
                                subtitle: "So your streak kept going. Nice to have you back."))
        }
        if let day = summary.repairedDay {
            rows.append(NoteRow(id: "repair", icon: "bandage", tint: .mint,
                                title: "You repaired \(day.formatted(.dateTime.weekday(.wide)))",
                                subtitle: "A double session joined your streak back up."))
        }
        for topic in (info?.topics ?? []).prefix(3) {
            rows.append(NoteRow(id: topic.id.uuidString, icon: topic.missed ? "arrow.counterclockwise" : "checkmark.circle",
                                tint: topic.missed ? .sun : .mint, title: topic.name, subtitle: topic.detail))
        }
        if let next = info?.nextSession {
            rows.append(NoteRow(id: "next", icon: "bell", tint: .sky, title: "Next session", subtitle: next))
        }
        return rows
    }

    // MARK: Mix-up

    private func mixUpCard(_ offer: MixUp) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                CapFace(size: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text(SessionCopy.mixUpLine(offer.name))
                        .clFont(.headline)
                        .foregroundStyle(CLColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(offer.explanation)
                        .clFont(.subheadline)
                        .foregroundStyle(CLColor.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 8) {
                Button("Fix it now · 2 min") { fix(offer) }
                    .buttonStyle(.cl(.dark, size: .medium, fullWidth: false))
                Button("Not now") { later(offer) }
                    .buttonStyle(.cl(.ghost, size: .medium, fullWidth: false))
            }
            .padding(.leading, 56)
        }
        .clCard()
    }

    private func fix(_ offer: MixUp) {
        CLHaptics.commit()
        let confusion = app.adoptConfusion(offer.candidate, explained: offer.explained, origin: offer.origin,
                                           withFixQuestions: true)
        if let request = app.prepareFix(confusion.id) { onStart(request) }
    }

    private func later(_ offer: MixUp) {
        CLHaptics.tap()
        app.adoptConfusion(offer.candidate, explained: offer.explained, origin: offer.origin, withFixQuestions: false)
        withAnimation(CLMotion.exit) { mixUpHandled = true }
        app.router.toast("Cap will bring it up on Today", systemImage: "clock", tone: .neutral)
    }

    // MARK: Exam eve

    private var eveCard: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 16))
        return layout {
            ReadinessRing(value: ring ?? summary.readinessAfter ?? 0, size: 86, lineWidth: 10)
            VStack(alignment: .leading, spacing: 4) {
                Text(info?.examTitle ?? summary.examTitle ?? "Your exam")
                    .clFont(.headline)
                    .foregroundStyle(CLColor.ink)
                if let date = info?.examDate {
                    Text("\(CLFormat.relativeDays(to: date, from: app.now, calendar: app.calendar).capitalizedSentence) at \(date.formatted(.dateTime.hour().minute()))")
                        .clFont(.subheadline)
                        .foregroundStyle(CLColor.ink2)
                }
                Text("You went over your weak spots. Sleep is when today's studying sticks.")
                    .clFont(.subheadline)
                    .foregroundStyle(CLColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .clCard()
        .accessibilityElement(children: .combine)
    }

    // MARK: Footer

    @ViewBuilder private var footer: some View {
        Button(isEve ? "Good night" : "Done", action: onDone)
            .buttonStyle(.cl(.primary))
    }

    @ViewBuilder private var secondary: some View {
        if !isEve, !isFix, let bonus = info?.bonus, (info?.bonusCount ?? 0) > 0 {
            Button(SessionCopy.moreQuestions(info?.bonusCount ?? 0)) {
                CLHaptics.commit()
                onStart(bonus)
            }
            .buttonStyle(.cl(.ghost, size: .medium))
        }
    }

    // MARK: Preparing

    private func prepare() async {
        guard info == nil else { return }
        if isFix, let confusionID = runner.request.confusionID ?? runner.built.confusionID {
            fixed = app.resolveFix(confusionID: confusionID, summary: summary)
        }
        let made = makeInfo()
        decision = decide(made)
        info = made
        let before = summary.readinessBefore
        let after = summary.readinessAfter
        streakShown = summary.streakExtended ? max(0, summary.streak.current - 1) : summary.streak.current
        ring = isEve ? after : before

        if reduceMotion {
            CLFeel.play(isEve ? .goodnight : .done)
            countStep = countSteps
            ring = after ?? before
            streakShown = summary.streak.current
            skyShown = true
            celebrate()
        } else {
            do { try await playOut(before: before, after: after) } catch { return }
        }
        #if DEBUG
        // `CRAMLESS_SUMMARY_SKY=<ms>` opens the sky that long after the choreography ends, as a tap on the strip would,
        // so a film can follow a real session into the sky it relit.
        if hasSkyLine, let ms = TestHarness.once("CRAMLESS_SUMMARY_SKY").flatMap(Int.init) {
            try? await nap(ms)
            guard !Task.isCancelled else { return }
            openSky()
            return
        }
        #endif
        // Nothing is asked of the AI once the summary has gone.
        guard !Task.isCancelled else { return }
        if !isEve, !isFix, let candidate = app.confusionCandidate(forSession: summary.sessionID) {
            let (explained, origin) = await app.explainConfusion(candidate)
            withAnimation(CLMotion.settle) { mixUp = MixUp(candidate: candidate, explained: explained, origin: origin) }
        }
    }

    /// Cap has arrived (its motion plays as it appears): the session's sound, the numbers counting up, the ring
    /// climbing, the streak rolling over, then the celebration. Stops where it is if the summary closes.
    private func playOut(before: Double?, after: Double?) async throws {
        try await nap(250)
        CLFeel.play(isEve ? .goodnight : .done)
        guard !isEve else { return }
        try await nap(300)
        try await tick(steps: countSteps, over: 0.8) { step in countStep = step }
        if let before, let after, abs(after - before) >= 0.005 {
            try await nap(150)
            withAnimation(CLMotion.fill) { ring = after }
            if after > before {
                try await tick(steps: min(12, Int(((after - before) * 100).rounded())), over: 1.2) { _ in }
            } else {
                try await nap(1200)
            }
        }
        try await nap(150)
        withAnimation(CLMotion.pop) { streakShown = summary.streak.current }
        try await nap(200)
        // The sky says what the session did to it, then the celebration.
        withAnimation(CLMotion.settle) { skyShown = true }
        try await nap(150)
        celebrate()
    }

    /// `steps` light ticks along the fill curve over `duration` seconds (the ring's own curve), calling `step` with
    /// each one's number as it lands.
    private func tick(steps: Int, over duration: Double, step: (Int) -> Void) async throws {
        var elapsed = 0.0
        for (index, at) in CountUp.times(steps: steps, duration: duration).enumerated() {
            try await nap(Int(max(0, at - elapsed) * 1000))
            elapsed = at
            withAnimation(CLMotion.snap) { step(index + 1) }
            CLHaptics.select()
        }
    }

    private func decide(_ info: Info) -> CelebrationDecision {
        var decision = app.celebration(for: summary, streakBefore: runner.streakBefore,
                                       readinessTarget: info.examTitle == nil ? nil : info.target,
                                       mixUpFixed: isFix && fixed)
        #if DEBUG
        if let size = TestHarness.once("CRAMLESS_CELEBRATION").flatMap(Celebration.init(rawValue:)) {
            decision.size = size
        }
        #endif
        return decision
    }

    /// The celebration, last: Cap hops (with sparkles from medium up) and the confetti falls. Exam eve and quiet
    /// hours stay calm.
    private func celebrate() {
        app.noteCelebration(decision)
        celebrated = true
    }

    private func makeInfo() -> Info {
        var info = Info()
        let exam = app.exam(summary.examID)
        if let exam, exam.deletedAt == nil {
            info.examTitle = exam.title
            info.examDate = exam.date
            let readiness = app.readiness(for: exam)
            info.daysLeft = readiness.daysLeft
            info.target = readiness.target
            info.projected = readiness.projected
        }
        info.topics = topicRows()
        info.nextSession = nextSessionLine()
        info.freezeEarned = summary.streak.freezesAvailable > runner.streakBefore.freezesAvailable
        let yesterday = app.calendar.startOfDay(for: app.calendar.adding(days: -1, to: app.now))
        info.freezeUsedYesterday = summary.streak.frozenDays.contains { app.calendar.isDate($0, inSameDayAs: yesterday) }
        if !isEve, !isFix {
            let request = app.todaySummary().sessionReady
                ? SessionRequest(kind: .daily, minutes: 5) : SessionRequest(kind: .practice, minutes: 5)
            info.bonus = request
            info.bonusCount = app.buildSession(request).entries.count
        }
        return info
    }

    /// The topics this session touched: missed ones first ("Back tomorrow"), then strong ones ("Next review in
    /// 4 days").
    private func topicRows() -> [TopicRow] {
        var byTopic: [UUID: (missed: Bool, due: Date?)] = [:]
        var order: [UUID] = []
        for answer in runner.answers {
            guard let topic = answer.entry.topicID else { continue }
            if byTopic[topic] == nil { order.append(topic) }
            var value = byTopic[topic] ?? (false, nil)
            if !answer.review.wasCorrect { value.missed = true }
            if let due = answer.review.after.due { value.due = min(value.due ?? due, due) }
            byTopic[topic] = value
        }
        let rows: [TopicRow] = order.compactMap { id in
            guard let value = byTopic[id], let name = runner.topicName(id) else { return nil }
            let days = value.due.map { max(0, $0.timeIntervalSince(app.now)) / 86_400 }
            let detail: String
            switch (value.missed, days) {
            case (true, let d?) where d < 0.98: detail = "Back later today for another go"
            case (true, let d?): detail = "Back \(SessionCopy.inInterval(days: d)) for another go"
            case (true, nil): detail = "Back soon for another go"
            case (false, let d?) where d < 0.98: detail = "Good start. One more look later today"
            case (false, let d?): detail = "Strong. Next review \(SessionCopy.inInterval(days: d))"
            case (false, nil): detail = "Strong"
            }
            return TopicRow(id: id, name: name, missed: value.missed, detail: detail)
        }
        return rows.filter(\.missed) + rows.filter { !$0.missed }
    }

    private func nextSessionLine() -> String? {
        let forecast = app.dueForecast(days: 2)
        let tomorrow = forecast.count > 1 ? forecast[1].count : 0
        var parts: [String] = []
        if let minutes = app.settings.reminderMinutes,
           let time = app.calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: app.now) {
            parts.append("Tomorrow at \(time.formatted(.dateTime.hour().minute()))")
        } else {
            parts.append("Tomorrow")
        }
        if tomorrow > 0 { parts.append(tomorrow == 1 ? "1 review due" : "\(tomorrow) reviews due") }
        return parts.joined(separator: " · ")
    }
}

private extension String {
    var capitalizedSentence: String { prefix(1).uppercased() + dropFirst() }
}
