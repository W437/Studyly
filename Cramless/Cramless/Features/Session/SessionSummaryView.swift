import StoreKit
import SwiftUI

/// The end of a session, inside the cover, said once each: Cap celebrating, the title, "6 of 9 right first time · 3 min" with the streak
/// in a small pill, one readiness card ("41% → 69% ready" / "On track for 80% · 2 days left"), the quests the session moved, and Done
/// pinned. A mix-up found in this session is offered as "Fix it"; a sky the week lit and a badge earned show when they happen, the badge's
/// name once. The night before ends differently: Cap asleep, "That's enough.", the exam, and the five shakiest ideas to read once, with
/// "Good night" pinned. A fix ends with "Fixed" (or "Not yet") and "Anaphase vs telophase: 5 of 5 right.".
///
/// It plays in order: Cap arrives, the session's sound, the ring climbs as its number counts up, the streak rolls over, the sky line, the
/// quests the session finished tick off (and a sky they lit says so), and last the celebration `CelebrationPolicy` picked (confetti, Cap's
/// hop and sparkles), if one is earned. A streak milestone takes over the hero: its flame, and "30 days.". A good moment (a perfect session,
/// two saves, a milestone) may, rarely, be followed by the system's rating prompt (`ReviewPromptPolicy`).
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
    /// How far the readiness number has counted on its way from before to after: `readinessStep` of `readinessSteps`.
    @State private var readinessStep = 0
    @State private var celebrated = false
    @State private var skyShown = false
    /// What the session did to the game loop: quests finished, a sky lit, badges earned.
    @State private var game = GameOutcome()
    /// Today's quests as they stand after the session; the ones it finished tick off one by one.
    @State private var quests: [QuestRow] = []
    @State private var ticked = 0
    @State private var skyLitShown = false
    @State private var flameBounce = 0
    @State private var scroll = ScrollPosition()
    /// On an eve: what the last look holds, read when the summary opens.
    @State private var lastLook: LastLook?
    @Environment(\.requestReview) private var requestReview

    struct Info {
        var examTitle: String?
        var examDate: Date?
        var daysLeft: Int?
        var target: Double = 0.9
        var projected: Double?
        var bonus: SessionRequest?
        var bonusCount = 0
        var freezeEarned = false
        var freezeUsedYesterday = false
    }

    struct MixUp {
        var candidate: ConfusionCandidate
        var explained: ConfusionOut?
        var origin: ItemOrigin
        var name: String { explained?.name ?? candidate.name }
        var explanation: String {
            explained?.explanation ?? candidate.defaultExplanation
        }
    }

    private var isEve: Bool { summary.stopNow || summary.kind == .examEve }
    private var isFix: Bool { summary.kind == .fix }

    var body: some View {
        QuestionScroll(position: $scroll) {
            VStack(spacing: 16) {
                hero
                if isEve {
                    eveCard
                    if let lastLook, !lastLook.ideas.isEmpty { eveIdeas(lastLook) }
                } else {
                    if hasSkyLine { skyLine }
                    // A fix ends on its own result: no readiness there.
                    if !isFix, summary.readinessBefore != nil, summary.readinessAfter != nil, info?.examTitle != nil {
                        readinessCard
                    }
                    // A fix shows them only when it finished one (the mix-up's own quest).
                    if !movedQuests.isEmpty, !isFix || !game.questsDone.isEmpty { questsCard }
                    if let sky = game.skyLit { skyLitCard(sky) }
                    if !game.badges.isEmpty { badgesCard }
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
            ZStack(alignment: .topTrailing) {
                if info != nil { CapView(capMoment, size: capSize) }
                // A streak milestone brings its flame, which pops in with the celebration and bounces once.
                if let days = milestoneDays {
                    StreakFlame(stage: StreakStage(days: days), size: 60, bounce: reduceMotion ? nil : flameBounce)
                        .scaleEffect(celebrated ? 1 : 0.3, anchor: .bottom)
                        .opacity(celebrated ? 1 : 0)
                        .offset(x: 38, y: 6)
                        .animation(reduceMotion ? nil : CLMotion.pop, value: celebrated)
                }
            }
            .frame(width: capSize, height: capSize)
            Text(title)
                .clFont(.brandTitle(32))
                .foregroundStyle(CLColor.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            subtitleLine
        }
        .frame(maxWidth: .infinity)
    }

    /// The subtitle, and beside it (wrapping under it when there's no room) the streak's small pill.
    @ViewBuilder private var subtitleLine: some View {
        let line = Text(subtitle)
            .clFont(.callout)
            .foregroundStyle(CLColor.ink2)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        if showsStreak {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    line
                    streakPill
                }
                VStack(spacing: 8) {
                    line
                    streakPill
                }
            }
        } else {
            line
        }
    }

    private var capSize: CGFloat { 120 }

    /// The streak's pill: after a session that isn't the night before or a fix, out of Quiet mode, and not on a milestone (the hero's
    /// flame says it then).
    private var showsStreak: Bool {
        !isEve && !isFix && !app.settings.quietMode && summary.streak.current > 0 && milestoneDays == nil
    }

    /// The flame and the streak's days, rolling over to today's as the summary plays.
    private var streakPill: some View {
        let current = summary.streak.current
        let shown = streakShown ?? current
        return HStack(spacing: 3) {
            StreakFlame(stage: StreakStage(days: shown), size: 18, bounce: reduceMotion ? nil : flameBounce)
            Text(verbatim: "\(shown)")
                .clFont(.number(15, .bold))
                .foregroundStyle(CLColor.tangerineInk)
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(shown)))
        }
        .padding(.leading, 6)
        .padding(.trailing, 10)
        .frame(minHeight: 28)
        .background(CLColor.tangerineSoft, in: Capsule())
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(current) day streak"))
        .accessibilityValue(summary.streakExtended ? Text("One more day") : Text(""))
    }

    /// The streak milestone this session reached, when it is what the summary celebrates.
    private var milestoneDays: Int? {
        if case .streakMilestone(let days) = decision.reason { return days }
        return nil
    }

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
        case .small: .puff(CGPoint(x: 0.5, y: 0.2))
        case .medium: .burst(CGPoint(x: 0.5, y: 0.18))
        case .big: .cannons
        case .none, .nudge, .calm: nil
        }
    }

    private var title: LocalizedStringResource {
        if isEve { return "That's enough." }
        if isFix { return fixed ? "Fixed" : "Not yet" }
        switch decision.reason {
        case .firstSession: return "First session done"
        case .streakMilestone(let days): return MilestoneCopy.title(days)
        case .readinessGoal: return "Goal reached"
        case .perfect: return "All right first time"
        case .mixUpFixed: return "Fixed"
        // The badge's name, here and nowhere else on the page.
        case .badge: return game.badges.first?.title ?? "New badge"
        case nil: return "Session done"
        }
    }

    private var subtitle: LocalizedStringResource {
        if isEve { return "Sleep is part of studying." }
        if isFix {
            let name = runner.built.weakSpots.first?.name
            return .verbatim(SessionCopy.fixResult(name, right: summary.correctFirstTry, of: summary.itemsReviewed))
        }
        return .verbatim(SessionCopy.summaryLine(right: summary.correctFirstTry, of: summary.itemsReviewed, minutes: summary.minutes))
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

    // MARK: Quests, a new sky and badges

    /// The quests this session moved: further along than when it started, or finished by it.
    private var movedQuests: [QuestRow] {
        quests.filter { row in
            game.questsDone.contains(row.kind) || row.progress.done > (runner.questsBefore[row.kind] ?? 0)
        }
    }

    /// The moved quests, the ones this session finished showing their check as the choreography reaches them.
    private var shownQuests: [QuestRow] {
        movedQuests.map { row in
            guard let index = game.questsDone.firstIndex(of: row.kind), index >= ticked else { return row }
            var pending = row
            pending.isDone = false
            pending.progress = QuestProgress(done: 0, goal: 1)
            return pending
        }
    }

    private var questsCard: some View {
        let week = min(game.weekAfter, game.weekBefore + ticked)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Today's quests").clFont(.headline).foregroundStyle(CLColor.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Text(QuestCopy.week(week, of: game.weekGoal))
                    .clFont(.footnoteEmphasis)
                    .foregroundStyle(CLColor.ink3)
                    .contentTransition(.numericText(value: Double(week)))
            }
            ForEach(shownQuests) { row in
                QuestRowView(row: row)
            }
        }
        .clCard()
        .opacity(skyShown ? 1 : 0)
        .offset(y: skyShown ? 0 : 10)
        .accessibilityHidden(!skyShown)
    }

    /// A week of quests lit a sky: a swatch of it, and a button that puts it behind the stars.
    private func skyLitCard(_ sky: SkyTheme) -> some View {
        HStack(spacing: 14) {
            SkySwatch(theme: sky, width: 64, height: 64)
            VStack(alignment: .leading, spacing: 2) {
                Text(sky.title).clFont(.headline).foregroundStyle(CLColor.ink)
                Text("A new sky is lit. A week of 12 quests did it.")
                    .clFont(.footnote)
                    .foregroundStyle(CLColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("Use it") {
                CLHaptics.commit()
                app.setSkyTheme(sky)
                app.router.toast("Your sky is \(String(localized: sky.title))", systemImage: "sparkles")
            }
            .buttonStyle(.cl(.soft, size: .small, fullWidth: false))
        }
        .clCard()
        .opacity(skyLitShown ? 1 : 0)
        .offset(y: skyLitShown ? 0 : 10)
        .accessibilityHidden(!skyLitShown)
    }

    private var badgesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CLEyebrow(text: game.badges.count == 1 ? "New badge" : "New badges")
            ForEach(game.badges) { badge in
                Button {
                    CLHaptics.tap()
                    app.router.present(.badge(badge))
                } label: {
                    HStack(spacing: 14) {
                        BadgeMedal(badge: badge, size: 56)
                        VStack(alignment: .leading, spacing: 2) {
                            // The title already names the badge the summary celebrates.
                            if !(decision.reason == .badge && badge == game.badges.first) {
                                Text(badge.title).clFont(.headline).foregroundStyle(CLColor.ink)
                            }
                            Text(badge.earned(saves: app.achievementFacts().saves)).clFont(.subheadline).foregroundStyle(CLColor.ink2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        CLChevron()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(badge.title))
                .accessibilityValue(Text(badge.earned(saves: app.achievementFacts().saves)))
                .accessibilityAddTraits(.isButton)
            }
        }
        .clCard()
        .opacity(skyShown ? 1 : 0)
        .offset(y: skyShown ? 0 : 10)
        .accessibilityHidden(!skyShown)
    }

    // MARK: Readiness

    /// Readiness once: a ring with no number in it (its picture), the exam, "41% → 69% ready" whose second number counts up as the ring
    /// climbs, and "On track for 80% · 2 days left".
    private var readinessCard: some View {
        let before = summary.readinessBefore ?? 0
        let after = summary.readinessAfter ?? 0
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 16))
        return layout {
            ReadinessRing(value: ring ?? before, size: 56, lineWidth: 8, showsLabel: false)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: info?.examTitle ?? summary.examTitle ?? String(localized: "Your exam"))
                    .clFont(.footnoteEmphasis)
                    .foregroundStyle(CLColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: SessionCopy.readinessChange(before: before, after: shownAfter(before: before, after: after)))
                    .clFont(.headline)
                    .foregroundStyle(CLColor.ink)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .accessibilityLabel(Text("\(CLFormat.percent(before)) to \(CLFormat.percent(after)) ready"))
                if let line = outlookLine {
                    Text(verbatim: line.text)
                        .clFont(.subheadline)
                        .foregroundStyle(line.onTrack ? CLColor.mintInk : CLColor.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .clCard()
        .accessibilityElement(children: .combine)
    }

    /// The steps the readiness number counts in: one a point, at most 12.
    private var readinessSteps: Int {
        guard let before = summary.readinessBefore, let after = summary.readinessAfter, after > before else { return 0 }
        return min(CountUp.maxSteps, Int(((after - before) * 100).rounded()))
    }

    /// The after number as it counts up from before (exactly after once it lands).
    private func shownAfter(before: Double, after: Double) -> Double {
        let steps = readinessSteps
        guard steps > 0, readinessStep < steps else { return readinessStep >= steps ? after : before }
        return before + (after - before) * Double(readinessStep) / Double(steps)
    }

    /// "On track for 80% · 2 days left", or "Projected 72% by 12 Nov · 2 days left": the projection, labelled as one.
    private var outlookLine: (text: String, onTrack: Bool)? {
        guard let info else { return nil }
        var parts: [String] = []
        var onTrack = false
        if let projected = info.projected {
            onTrack = projected >= info.target - 0.0001
            if onTrack {
                parts.append(String(localized: "On track for \(CLFormat.percent(info.target))"))
            } else if let date = info.examDate {
                parts.append(String(localized: "Projected \(CLFormat.percent(projected)) by \(date.formatted(.dateTime.day().month(.abbreviated)))"))
            } else {
                parts.append(String(localized: "Projected \(CLFormat.percent(projected))"))
            }
        }
        if let days = info.daysLeft { parts.append(String(localized: "\(days) days left")) }
        return parts.isEmpty ? nil : (parts.joined(separator: " · "), onTrack)
    }

    // MARK: Notes (a streak freeze, a repaired day)

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
        let quiet = app.settings.quietMode
        if quiet {
            // Quiet mode: nothing about the streak.
        } else if info?.freezeEarned == true {
            let n = summary.streak.freezesAvailable
            rows.append(NoteRow(id: "freeze", icon: "snowflake", tint: .sky, title: "You earned a streak freeze",
                                subtitle: "You have \(n). A freeze covers a day you miss."))
        } else if info?.freezeUsedYesterday == true, summary.streakExtended {
            rows.append(NoteRow(id: "freeze-used", icon: "snowflake", tint: .sky, title: "A freeze covered yesterday",
                                subtitle: "So your streak kept going. Nice to have you back."))
        }
        if !quiet, let day = summary.repairedDay {
            rows.append(NoteRow(id: "repair", icon: "bandage", tint: .mint,
                                title: "You repaired \(day.formatted(.dateTime.weekday(.wide)))",
                                subtitle: "A double session joined your streak back up."))
        }
        return rows
    }

    // MARK: Mix-up

    private func mixUpCard(_ offer: MixUp) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                CapFace(size: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text(SessionCopy.mixUpLine(offer.name, questions: offer.candidate.itemIDs.count))
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
                Button { fix(offer) } label: {
                    Text(verbatim: SessionCopy.fixTitle(questions: offer.candidate.itemIDs.count))
                }
                .buttonStyle(.cl(.dark, size: .medium, fullWidth: false))
                Button("Not now") { later(offer) }
                    .buttonStyle(.cl(.ghost, size: .medium, fullWidth: false))
            }
            .padding(.leading, 56)
        }
        .clCard()
    }

    /// The same fix as Cap's card and the mix-up's page: it opens, and its screen gets the lesson written (`AppModel.readyFix`).
    private func fix(_ offer: MixUp) {
        CLHaptics.commit()
        let confusion = app.adoptConfusion(offer.candidate, explained: offer.explained, origin: offer.origin, withFixQuestions: false)
        if let request = app.prepareFix(confusion.id) { onStart(request) }
    }

    private func later(_ offer: MixUp) {
        CLHaptics.tap()
        app.adoptConfusion(offer.candidate, explained: offer.explained, origin: offer.origin, withFixQuestions: false)
        withAnimation(CLMotion.exit) { mixUpHandled = true }
        app.router.toast("Cap will bring it up on Today", systemImage: "clock", tone: .neutral)
    }

    // MARK: The night before

    /// The exam, its readiness and when it is.
    private var eveCard: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 16))
        return layout {
            ReadinessRing(value: ring ?? summary.readinessAfter ?? 0, size: 72, lineWidth: 9)
            VStack(alignment: .leading, spacing: 4) {
                Text(info?.examTitle ?? summary.examTitle ?? "Your exam")
                    .clFont(.headline)
                    .foregroundStyle(CLColor.ink)
                if let date = info?.examDate {
                    Text("\(CLFormat.relativeDays(to: date, from: app.now, calendar: app.calendar).capitalizedSentence) at \(date.formatted(.dateTime.hour().minute()))")
                        .clFont(.subheadline)
                        .foregroundStyle(CLColor.ink2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .clCard()
        .accessibilityElement(children: .combine)
    }

    /// The last look, right here: "Read these once · 2 min" and the shakiest ideas, with "Good night" pinned below.
    private func eveIdeas(_ look: LastLook) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: LastLookCopy.readOnce(minutes: look.minutes))
                .clFont(.headline)
                .foregroundStyle(CLColor.ink)
                .padding(.horizontal, 4)
                .accessibilityAddTraits(.isHeader)
            LastLookIdeas(look: look) { ref in SourceButton(ref: ref) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Footer

    @ViewBuilder private var footer: some View {
        Button(isEve ? "Good night" : "Done", action: onDone)
            .buttonStyle(.cl(.primary))
    }

    @ViewBuilder private var secondary: some View {
        if !isEve, !isFix, let bonus = info?.bonus, (info?.bonusCount ?? 0) > 0 {
            Button(SessionCopy.anotherSession(info?.bonusCount ?? 0)) {
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
        // The quests this session finished, a sky they lit, the badges it earned (after a fix is resolved: that is a quest too).
        game = app.settleGame()
        // Quiet mode: settled all the same, and nothing is said about it.
        if app.settings.quietMode { game = GameOutcome() }
        quests = isEve || app.settings.quietMode ? [] : app.questsToday().rows
        let made = makeInfo()
        decision = decide(made)
        info = made
        if isEve, let examID = summary.examID { lastLook = app.lastLook(for: examID) }
        let before = summary.readinessBefore
        let after = summary.readinessAfter
        streakShown = summary.streakExtended ? max(0, summary.streak.current - 1) : summary.streak.current
        ring = isEve ? after : before

        if reduceMotion {
            CLFeel.play(isEve ? .goodnight : .done)
            readinessStep = readinessSteps
            ring = after ?? before
            streakShown = summary.streak.current
            skyShown = true
            ticked = game.questsDone.count
            skyLitShown = true
            celebrate()
        } else {
            do { try await playOut(before: before, after: after) } catch { return }
        }
        await askForRatingIfDue()
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
        #if DEBUG
        // `CRAMLESS_SUMMARY_SCROLL=<ms>` eases the page down to its end that long after the choreography, so a film or a
        // screenshot sees the quests, the new sky and the badges under the numbers.
        if let ms = TestHarness.once("CRAMLESS_SUMMARY_SCROLL").flatMap(Int.init) {
            try? await nap(ms)
            withAnimation(.easeInOut(duration: 1.6)) { scroll.scrollTo(edge: .bottom) }
        }
        // Then, each that long after the one before: `CRAMLESS_SUMMARY_USE_SKY` puts the sky the week lit behind the stars (as
        // "Use it" would), `CRAMLESS_SUMMARY_BADGE` opens the new badge's sheet, `CRAMLESS_SUMMARY_DONE` presses Done.
        if let ms = TestHarness.once("CRAMLESS_SUMMARY_USE_SKY").flatMap(Int.init), let sky = game.skyLit {
            try? await nap(ms)
            CLHaptics.commit()
            app.setSkyTheme(sky)
            app.router.toast("Your sky is \(String(localized: sky.title))", systemImage: "sparkles")
        }
        if let ms = TestHarness.once("CRAMLESS_SUMMARY_BADGE").flatMap(Int.init), let badge = game.badges.first {
            try? await nap(ms)
            app.router.present(.badge(badge))
        }
        if let ms = TestHarness.once("CRAMLESS_SUMMARY_DONE").flatMap(Int.init) {
            try? await nap(ms)
            onDone()
        }
        #endif
        // Nothing is asked of the AI once the summary has gone.
        guard !Task.isCancelled else { return }
        // The rules name the mix-up here; Cloud AI is asked only after "Fix it now".
        if !isEve, !isFix, let candidate = app.confusionCandidate(forSession: summary.sessionID) {
            let (explained, origin) = app.explainByRules(candidate)
            withAnimation(CLMotion.settle) { mixUp = MixUp(candidate: candidate, explained: explained, origin: origin) }
        }
    }

    /// Cap has arrived (its motion plays as it appears): the session's sound, the ring climbing as the readiness number counts up, the
    /// streak rolling over, then the celebration. Stops where it is if the summary closes.
    private func playOut(before: Double?, after: Double?) async throws {
        try await nap(250)
        CLFeel.play(isEve ? .goodnight : .done)
        guard !isEve else { return }
        try await nap(300)
        if !isFix, let before, let after, abs(after - before) >= 0.005 {
            withAnimation(CLMotion.fill) { ring = after }
            if after > before {
                try await tick(steps: readinessSteps, over: 1.2) { step in readinessStep = step }
            } else {
                try await nap(1200)
            }
        }
        if showsStreak {
            try await nap(150)
            withAnimation(CLMotion.pop) { streakShown = summary.streak.current }
            if summary.streakExtended, !reduceMotion { flameBounce += 1 }
            try await nap(200)
        }
        // The sky says what the session did to it, the quests tick off, then the celebration.
        withAnimation(CLMotion.settle) { skyShown = true }
        try await nap(150)
        if !game.questsDone.isEmpty {
            try await nap(250)
            for _ in game.questsDone {
                withAnimation(CLMotion.pop) { ticked += 1 }
                CLHaptics.select()
                try await nap(380)
            }
        }
        if game.skyLit != nil {
            withAnimation(CLMotion.settle) { skyLitShown = true }
            CLHaptics.land()
            try await nap(300)
        }
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
                                       mixUpFixed: isFix && fixed, badgeEarned: !game.badges.isEmpty)
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
        // A milestone's flame has popped in; a beat later it bounces, once.
        if milestoneDays != nil, !reduceMotion {
            Task {
                try? await nap(320)
                flameBounce += 1
            }
        }
    }

    /// A good moment, rarely: the system's rating prompt, a beat and a half after the streak has rolled over and the
    /// celebration has played (`ReviewPromptPolicy`: not in the first days, not on exam eve, never twice in a season).
    private func askForRatingIfDue() async {
        let facts = app.reviewPromptFacts(for: summary, milestone: milestoneDays)
        guard ReviewPromptPolicy.shouldAsk(facts) else { return }
        try? await nap(1500)
        guard !Task.isCancelled else { return }
        app.noteReviewPrompted()
        requestReview()
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
}

private extension String {
    var capitalizedSentence: String { prefix(1).uppercased() + dropFirst() }
}
