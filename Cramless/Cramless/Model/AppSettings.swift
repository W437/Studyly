import Foundation

/// The person's choices, kept in UserDefaults as one JSON value. Read and written only through
/// `AppModel.settings` (which saves on every change); everything else reads it from there.
/// New fields need defaults in `init(from:)` (decodeIfPresent), never a version bump.
struct AppSettings: Codable, Equatable, Sendable {
    enum Goal: String, Codable, CaseIterable, Sendable {
        case passClass, aceExams, keepUp, learn
        var title: String {
            switch self {
            case .passClass: "Pass a hard class"
            case .aceExams: "Ace my exams"
            case .keepUp: "Keep up every week"
            case .learn: "Actually remember it"
            }
        }
    }

    enum Level: String, Codable, CaseIterable, Sendable {
        case highSchool, college, grad, other
        var title: String {
            switch self {
            case .highSchool: "High school"
            case .college: "College"
            case .grad: "Grad or professional school"
            case .other: "Something else"
            }
        }
    }

    enum NotesLocation: String, Codable, CaseIterable, Sendable {
        case paper, slides, lectures, flashcardApps
        var title: String {
            switch self {
            case .paper: "Paper and textbooks"
            case .slides: "Slides and PDFs"
            case .lectures: "In lectures"
            case .flashcardApps: "Quizlet or Anki"
            }
        }
    }

    enum Theme: String, Codable, CaseIterable, Sendable { case system, light, dark }

    /// The day's quests, once picked: which, so they stay the same all day however the day changes.
    struct QuestDay: Codable, Equatable, Sendable {
        var dayKey: String
        var kinds: [QuestKind]
    }

    enum AgeBand: String, Codable, Sendable {
        /// Not asked or not shared.
        case unknown
        case under13, teen, adult
    }

    // Profile
    var firstName = ""
    var goal: Goal?
    var level: Level?
    var notesLocations: [NotesLocation] = []
    var ageBand: AgeBand = .unknown
    /// The next big exam, as onboarding's second question answered it (nil: no exam yet). The plan step turns it
    /// into an `Exam` once there's a course to attach it to.
    var nextExamDate: Date?

    // Study
    var dailyMinutes = 15
    /// Minutes after midnight for the daily reminder; nil means no reminder.
    var reminderMinutes: Int? = 19 * 60
    var quietHoursStart = 22 * 60
    var quietHoursEnd = 7 * 60
    /// FSRS target retention.
    var targetRetention = 0.9
    /// Weekdays (1 = Sunday … 7 = Saturday) that get a lighter load.
    var easyDays: [Int] = []

    // AI and privacy
    /// The consent version the person accepted for cloud AI; 0 means not accepted.
    var cloudConsentVersion = 0
    /// Sending page photos to the cloud is a separate switch.
    var sendPhotos = false
    var tutorMode: TutorMode = .hints
    /// What Ask Cap's assistant may do on its own (nothing, until the person says so, and never under 18).
    var assistant = AssistantSettings()

    // Accessibility and appearance
    var theme: Theme = .system
    var dyslexicFont = false
    var readAloud = false
    var haptics = true
    /// Soft notes for answers and finished sessions (silent with the Silent switch on).
    var sounds = true
    /// Cap's clips: he waves, nods and cheers instead of standing still (always still under Reduce Motion).
    var capMoves = true
    /// Cap says something short when he is tapped.
    var capTalks = true

    // Lifecycle
    var onboardingCompleted = false
    var installedAt: Date?
    /// When the last big celebration played: another one the same day is medium (`CelebrationPolicy`).
    var lastBigCelebrationAt: Date?

    // The game loop (`AppModel+Game.swift`)
    /// Today's quests (this device's picks; the ones finished are in `DayRecord.questMask`, which syncs).
    var questDay: QuestDay?
    /// Weeks in which 12 quests were finished: each lit one of the skies in `SkyTheme.unlockOrder`.
    var litWeeks = 0
    /// The first day (its key) of the week that lit the latest sky, so one week lights only one.
    var lastLitWeek: String?
    /// The sky behind the stars (Settings ▸ Appearance), one of those unlocked.
    var skyTheme: SkyTheme = .night
    /// The app icon the person chose (the icon itself is the system's to switch).
    var appIcon: AppIconChoice = .standard
    /// The badges earned and when. nil until the first launch that knows about badges, which notes what is already earned
    /// without a fuss.
    var badges: [String: Date]?
    /// When, and in which version, the app last asked for a rating (`ReviewPromptPolicy`).
    var reviewPromptedAt: Date?
    var reviewPromptedVersion: String?

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        firstName = try c.decodeIfPresent(String.self, forKey: .firstName) ?? d.firstName
        goal = try c.decodeIfPresent(Goal.self, forKey: .goal)
        level = try c.decodeIfPresent(Level.self, forKey: .level)
        notesLocations = try c.decodeIfPresent([NotesLocation].self, forKey: .notesLocations) ?? d.notesLocations
        ageBand = try c.decodeIfPresent(AgeBand.self, forKey: .ageBand) ?? d.ageBand
        nextExamDate = try c.decodeIfPresent(Date.self, forKey: .nextExamDate)
        dailyMinutes = try c.decodeIfPresent(Int.self, forKey: .dailyMinutes) ?? d.dailyMinutes
        reminderMinutes = try c.decodeIfPresent(Int.self, forKey: .reminderMinutes) ?? d.reminderMinutes
        quietHoursStart = try c.decodeIfPresent(Int.self, forKey: .quietHoursStart) ?? d.quietHoursStart
        quietHoursEnd = try c.decodeIfPresent(Int.self, forKey: .quietHoursEnd) ?? d.quietHoursEnd
        targetRetention = try c.decodeIfPresent(Double.self, forKey: .targetRetention) ?? d.targetRetention
        easyDays = try c.decodeIfPresent([Int].self, forKey: .easyDays) ?? d.easyDays
        cloudConsentVersion = try c.decodeIfPresent(Int.self, forKey: .cloudConsentVersion) ?? d.cloudConsentVersion
        sendPhotos = try c.decodeIfPresent(Bool.self, forKey: .sendPhotos) ?? d.sendPhotos
        tutorMode = try c.decodeIfPresent(TutorMode.self, forKey: .tutorMode) ?? d.tutorMode
        assistant = (try? c.decodeIfPresent(AssistantSettings.self, forKey: .assistant)) ?? d.assistant
        theme = try c.decodeIfPresent(Theme.self, forKey: .theme) ?? d.theme
        dyslexicFont = try c.decodeIfPresent(Bool.self, forKey: .dyslexicFont) ?? d.dyslexicFont
        readAloud = try c.decodeIfPresent(Bool.self, forKey: .readAloud) ?? d.readAloud
        haptics = try c.decodeIfPresent(Bool.self, forKey: .haptics) ?? d.haptics
        sounds = try c.decodeIfPresent(Bool.self, forKey: .sounds) ?? d.sounds
        capMoves = try c.decodeIfPresent(Bool.self, forKey: .capMoves) ?? d.capMoves
        capTalks = try c.decodeIfPresent(Bool.self, forKey: .capTalks) ?? d.capTalks
        onboardingCompleted = try c.decodeIfPresent(Bool.self, forKey: .onboardingCompleted) ?? d.onboardingCompleted
        installedAt = try c.decodeIfPresent(Date.self, forKey: .installedAt)
        lastBigCelebrationAt = try c.decodeIfPresent(Date.self, forKey: .lastBigCelebrationAt)
        questDay = try? c.decodeIfPresent(QuestDay.self, forKey: .questDay)
        litWeeks = try c.decodeIfPresent(Int.self, forKey: .litWeeks) ?? d.litWeeks
        lastLitWeek = try c.decodeIfPresent(String.self, forKey: .lastLitWeek)
        // A choice this version doesn't know (a sky or icon from a later one) falls back to the default.
        skyTheme = (try? c.decodeIfPresent(SkyTheme.self, forKey: .skyTheme)) ?? d.skyTheme
        appIcon = (try? c.decodeIfPresent(AppIconChoice.self, forKey: .appIcon)) ?? d.appIcon
        badges = try c.decodeIfPresent([String: Date].self, forKey: .badges)
        reviewPromptedAt = try c.decodeIfPresent(Date.self, forKey: .reviewPromptedAt)
        reviewPromptedVersion = try c.decodeIfPresent(String.self, forKey: .reviewPromptedVersion)
    }

    /// Under-18 accounts keep the tutor on hints first and inside the teen-safe scope.
    var isMinor: Bool { ageBand == .teen || ageBand == .under13 || level == .highSchool }

    /// The tutor mode actually used: a minor is always on hints first.
    var effectiveTutorMode: TutorMode { isMinor ? .hints : tutorMode }

    static let defaultsKey = "capling.settings.v1"

    static func load(from defaults: UserDefaults = .standard) -> AppSettings {
        guard let data = defaults.data(forKey: defaultsKey),
              let value = try? JSONDecoder.cramless.decode(AppSettings.self, from: data) else { return AppSettings() }
        return value
    }

    func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder.cramless.encode(self) { defaults.set(data, forKey: Self.defaultsKey) }
    }
}
