import Foundation
import SwiftData
import SwiftUI

/// The app's one model object: the store, the settings, the router and the services. Model mutations happen
/// only in AppModel and its extensions (`AppModel+Study.swift`, `AppModel+Capture.swift`, …), which stamp
/// `updatedAt` and call `save()`. Views read models with @Query or through AppModel's read helpers and never
/// write a model property themselves.
@MainActor
@Observable
final class AppModel {
    /// The running app's model, for App Intents and notification handlers. Tests replace it and put it back.
    nonisolated(unsafe) static weak var live: AppModel?

    let config: AppConfig
    let container: ModelContainer
    let router = Router()

    /// Bumped by every save, so views that compute over the store can depend on one value.
    private(set) var revision = 0

    var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            settings.save(to: defaults)
            applySettings(old: oldValue)
        }
    }

    /// The clock. Tests and the harness freeze it (`CRAMLESS_NOW=2026-10-22T09:00:00Z`).
    @ObservationIgnored var clock: () -> Date = { Date() }
    @ObservationIgnored var calendar: Calendar = .current
    @ObservationIgnored let defaults: UserDefaults

    var now: Date { clock() }
    var context: ModelContext { container.mainContext }

    // MARK: Services (each lane owns its type; built lazily so they can hold the model weakly)

    @ObservationIgnored lazy var ai = AIRouter(app: self)
    @ObservationIgnored lazy var purchases = PurchaseStore(app: self)
    @ObservationIgnored lazy var account = AccountService(app: self)
    @ObservationIgnored lazy var sync = SyncEngine(app: self)
    @ObservationIgnored lazy var notifications = NotificationScheduler(app: self)
    @ObservationIgnored lazy var widgets = WidgetSync(app: self)
    @ObservationIgnored lazy var liveActivities = LiveActivityController(app: self)
    /// Says when the connection comes back, while a question waits to be answered (`AppModel+AnswerLater.swift`).
    @ObservationIgnored lazy var connectivity = Connectivity()
    /// A round of answering kept questions is under way.
    @ObservationIgnored var answeringLater = false

    // MARK: The memory sky (`AppModel+Sky.swift`)

    /// The layout last drawn: it depends on the shape of the library, never on how well it is remembered.
    @ObservationIgnored let skyCache = SkyCache()
    /// What the sessions since the sky was last shown did to it. The sky plays it once, then clears it.
    var pendingSkyRelight: SkyRelight = .none

    // MARK: The game loop (`AppModel+Game.swift`)

    /// What the badges read from the whole log, worked out once per revision.
    @ObservationIgnored let gameCache = GameCache()
    /// The sections of each source (`AppModel+Coverage.swift`), worked out again only when the source changes.
    @ObservationIgnored let coverageCache = CoverageCache()
    /// Every upcoming exam's plan, sharing the daily goal (`AppModel+Insights.swift`), worked out again per revision and hour.
    @ObservationIgnored let examPlanCache = ExamPlanCache()
    /// "Looks wrong?": how a report came out, on its way from the sheet to the open question (`AppModel+Report`).
    var recheckDelivery: RecheckDelivery?
    @ObservationIgnored var rechecksInFlight: Set<UUID> = []
    @ObservationIgnored var recheckReasons: [UUID: String] = [:]
    /// Cap's cards: the ledger and what's worked out once per change (`AppModel+Notices.swift`).
    @ObservationIgnored let noticeCache = NoticeCache()
    @ObservationIgnored let lectureCache = LectureCache()
    /// Who in the Squad has studied today (`AppModel+Squad.swift`). The one line that reads it follows it on its own.
    var squadToday: SquadToday?
    /// "Studied" is on its way to the server.
    @ObservationIgnored var squadSending = false
    /// The last look's quiet job is under way (`AppModel+LastLook.swift`).
    @ObservationIgnored var lastLookPreparing = false
    /// When the calendar says the person is taken: the system's on a real launch, nothing in tests and the harness (`CRAMLESS_NOTICES=busy` gives it a demo one).
    @ObservationIgnored var busyCalendar: any BusyCalendarReading = NoBusyCalendar()
    /// Switches the app icon (the system's, or a fake in tests).
    @ObservationIgnored var iconSwitcher: any AppIconSwitching = SystemIconSwitcher()
    #if DEBUG
    /// `CRAMLESS_UNLOCK=all`: every icon and sky shows as unlocked, for films and screenshots.
    @ObservationIgnored var debugUnlockAll = false
    #endif

    /// Off in unit tests: no widget reloads, notification scheduling, sync or network from `save()`.
    @ObservationIgnored var sideEffectsEnabled: Bool

    @ObservationIgnored private var sideEffectTask: Task<Void, Never>?

    init(config: AppConfig = .resolve(), container: ModelContainer? = nil, defaults: UserDefaults = .standard) {
        self.config = config
        self.defaults = defaults
        self.container = container ?? (try? Persistence.makeContainer(inMemory: config.inMemoryStore))
            ?? (try! Persistence.makeContainer(inMemory: true))
        var loaded = AppSettings.load(from: defaults)
        if loaded.installedAt == nil { loaded.installedAt = Date() }
        self.settings = loaded
        self.sideEffectsEnabled = config.environment["XCTestConfigurationFilePath"] == nil
        if sideEffectsEnabled, !config.isHarness { busyCalendar = LiveBusyCalendar() }
        #if DEBUG
        if let frozen = config.environment["CRAMLESS_NOW"], let date = ISO8601DateFormatter().date(from: frozen) {
            clock = { date }
        }
        if let id = config.environment["CRAMLESS_SOUND_PALETTE"], let palette = CLSynth.Palette.named(id) {
            CLSound.shared.palette = palette
        }
        // A fresh cue log per launch, before the first frame (the film sync flash logs into it).
        if config.isHarness { FeelLog.reset() }
        #endif
        applyFeel()
        loadSquadToday()
        AppModel.live = self
        AppConfig.log.notice("\(config.startupLine, privacy: .public)")
    }

    /// The model for this launch. The screenshot harness gets settings of its own, wiped at every launch, so one
    /// run's theme or answers never leak into the next (the store is already in memory there).
    static func forLaunch() -> AppModel {
        let config = AppConfig.resolve()
        #if DEBUG
        if config.isHarness, let harness = UserDefaults(suiteName: "capling.harness") {
            harness.removePersistentDomain(forName: "capling.harness")
            return AppModel(config: config, defaults: harness)
        }
        #endif
        return AppModel(config: config)
    }

    // MARK: Saving

    /// Saves the context, bumps `revision` and schedules the outward effects (widget snapshot, sync, reminders)
    /// on a short debounce. Returns false when the save failed (the change stays in memory and is retried).
    @discardableResult
    func save() -> Bool {
        do {
            if context.hasChanges { try context.save() }
            revision &+= 1
            scheduleSideEffects()
            return true
        } catch {
            AppConfig.log.error("save failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Stamps a synced model as changed now. Call before `save()` in every mutation.
    func touch(_ course: Course) { course.updatedAt = now }
    func touch(_ item: StudyItem) { item.updatedAt = now }
    func touch(_ exam: Exam) { exam.updatedAt = now }
    func touch(_ topic: Topic) { topic.updatedAt = now }
    func touch(_ source: Source) { source.updatedAt = now }
    func touch(_ confusion: Confusion) { confusion.updatedAt = now }

    private func scheduleSideEffects() {
        guard sideEffectsEnabled else { return }
        sideEffectTask?.cancel()
        sideEffectTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard let self, !Task.isCancelled else { return }
            self.widgets.refresh()
            self.sync.pushSoon()
            self.notifications.reschedule()
        }
    }

    /// Runs the outward effects now (App Intents that finish in the background call this before returning).
    func flushSideEffects() async {
        sideEffectTask?.cancel()
        guard sideEffectsEnabled else { return }
        widgets.refresh()
        notifications.reschedule()
        await sync.pushNow()
    }

    private func applySettings(old: AppSettings) {
        applyFeel()
        guard sideEffectsEnabled else { return }
        if settings.reminderMinutes != old.reminderMinutes || settings.quietHoursStart != old.quietHoursStart
            || settings.quietHoursEnd != old.quietHoursEnd || settings.dailyMinutes != old.dailyMinutes
            || settings.notices != old.notices
            || settings.quietMode != old.quietMode {
            notifications.reschedule()
        }
        widgets.refresh()
    }

    /// Sounds and haptics follow the settings. The harness stays silent unless `CRAMLESS_SOUNDS=1`: films are
    /// scored afterwards from the cue log (`FeelLog`, `scripts/film.sh`).
    private func applyFeel() {
        CLHaptics.isEnabled = settings.haptics
        var sounds = settings.sounds && !settings.quietMode
        #if DEBUG
        if config.isHarness, config.environment["CRAMLESS_SOUNDS"] != "1" { sounds = false }
        #endif
        CLSound.shared.isEnabled = sounds
        CLSound.shared.quietHours = (settings.quietHoursStart, settings.quietHoursEnd)
        // The harness shows Cap still (screenshots must repeat) unless a film asks for his clips: `CRAMLESS_CAP_CLIPS=1`.
        var capMoves = settings.capMoves
        #if DEBUG
        if config.isHarness, config.environment["CRAMLESS_CAP_CLIPS"] != "1" { capMoves = false }
        #endif
        CapPlayback.shared.isEnabled = capMoves
        CapTouch.shared.talks = settings.capTalks
        #if DEBUG
        // The harness gives Cap no memory between launches, and dice that repeat when seeded (screenshots and films must).
        if config.isHarness { CapTouch.shared.configureForHarness(seed: TestHarness.capSeed) }
        #endif
    }

    // MARK: Launch

    /// Called once from the root view's task: seeds the harness world, starts the store and services.
    func start() async {
        #if DEBUG
        if config.seedDemoData { SampleData.seed(into: self) }
        TestHarness.applyLaunchSettings(to: self)
        applyGameHarness()
        applyNoticeHarness()
        if config.isHarness, TestHarness.skipsOnboarding { settings.onboardingCompleted = true }
        #endif
        applyDailyRollover()
        announceRecoveredLectures(await recoverInterruptedLectures())
        guard sideEffectsEnabled else { return }
        await purchases.start()
        await account.start()
        notifications.reschedule()
        widgets.refresh()
    }

    // MARK: Fetch helpers

    func fetch<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) -> [T] {
        (try? context.fetch(descriptor)) ?? []
    }

    func course(_ id: UUID?) -> Course? {
        guard let id else { return nil }
        return fetch(FetchDescriptor<Course>(predicate: #Predicate { $0.id == id })).first
    }

    func exam(_ id: UUID?) -> Exam? {
        guard let id else { return nil }
        return fetch(FetchDescriptor<Exam>(predicate: #Predicate { $0.id == id })).first
    }

    func item(_ id: UUID?) -> StudyItem? {
        guard let id else { return nil }
        return fetch(FetchDescriptor<StudyItem>(predicate: #Predicate { $0.id == id })).first
    }

    func source(_ id: UUID?) -> Source? {
        guard let id else { return nil }
        return fetch(FetchDescriptor<Source>(predicate: #Predicate { $0.id == id })).first
    }

    func confusion(_ id: UUID?) -> Confusion? {
        guard let id else { return nil }
        return fetch(FetchDescriptor<Confusion>(predicate: #Predicate { $0.id == id })).first
    }

    func thread(_ id: UUID?) -> ChatThread? {
        guard let id else { return nil }
        return fetch(FetchDescriptor<ChatThread>(predicate: #Predicate { $0.id == id })).first
    }

    /// Live courses in display order.
    var courses: [Course] {
        fetch(FetchDescriptor<Course>(predicate: #Predicate { $0.deletedAt == nil },
                                      sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)]))
    }

    /// Live exams from today on, soonest first.
    func upcomingExams() -> [Exam] {
        let start = calendar.startOfDay(for: now)
        return fetch(FetchDescriptor<Exam>(predicate: #Predicate { $0.deletedAt == nil && $0.date >= start },
                                           sortBy: [SortDescriptor(\.date)]))
    }
}
