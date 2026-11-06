import Foundation

// The routing decision, as one pure function of plain values: which model tiers may answer a job, in what order,
// and what the UI may offer when a better one isn't allowed. Nothing here reads settings, the clock, a model or
// the network; `AIRouter` gathers the facts into an `AIRouteContext`, and `RouterTests` checks the function against
// an oracle table and walks the whole matrix for its invariants.
//
// The tiers: T0 the offline rules (always, never metered, never listed: it is the floor every job stands on),
// T1 this iPhone's model, T2 Private Cloud Compute (dormant), T3 the relay (cloud).
//
// The rules it keeps:
//   • a free limit reached for a metered job takes the cloud away (and private cloud), and asks for the paywall. The limit
//     pays for Cloud AI, so this iPhone's own model (which costs nothing) keeps the jobs it can do, and the rules always answer;
//   • the cloud needs a relay (or the mock), the person's consent, an account that isn't under 13, and for a
//     photo job the photos switch;
//   • this iPhone's model needs to be available, the job to be one it does, and the text to be English and fit;
//   • generation, the tutor, lecture notes and chat cards prefer the cloud, then the device; grading prefers the
//     device for a short answer and the cloud for a long one, a shaky grade or "Grade again";
//   • when consent (or the photos switch) is all that stands between a job and a cloud that would help, the
//     route carries the suggestion; it never presents anything itself;
//   • under-18: the tutor is always on hints first.

enum AIJob: String, CaseIterable, Sendable {
    case generate, grade, tutor, confusions, lecture, cardsFromChat, transcribeImage

    /// The free limit the job counts against.
    var meter: QuotaMeter.Key? {
        switch self {
        case .generate: .scans
        case .grade: .grades
        case .tutor: .tutor
        case .lecture: .lectures
        case .confusions, .cardsFromChat, .transcribeImage: nil
        }
    }

    /// This iPhone's model can do this job (mistake patterns and handwriting need the cloud).
    var runsOnDevice: Bool {
        switch self {
        case .confusions, .transcribeImage: false
        default: true
        }
    }

    /// What Cloud AI would do, in the consent sheet's words.
    var feature: String {
        switch self {
        case .generate: "Write better questions from your pages"
        case .grade: "Grade answers in your own words more carefully"
        case .tutor: "Let Cap explain with your notes"
        case .confusions: "Find what you keep mixing up"
        case .lecture: "Write notes and questions from your lectures"
        case .cardsFromChat: "Make cards from your chat"
        case .transcribeImage: "Read handwriting, math and diagrams"
        }
    }
}

extension AIJob {
    /// The tutor's consent line when what Cloud AI would do is a problem from a photo.
    static let snapFeature = "Work through a problem from a photo"
}

enum AITier: String, CaseIterable, Sendable {
    case rules, onDevice, privateCloud, cloud

    var origin: ItemOrigin {
        switch self {
        case .rules: .rules
        case .onDevice, .privateCloud: .onDevice
        case .cloud: .cloud
        }
    }
}

enum AIAgeGate: Sendable, CaseIterable {
    case adult
    /// 13 to 17 (or high school): the tutor stays on hints and the request says `minor: true`.
    case minor
    /// Under 13: nothing goes to the cloud and consent is never suggested.
    case child

    init(_ settings: AppSettings) {
        if settings.ageBand == .under13 { self = .child } else if settings.isMinor { self = .minor } else { self = .adult }
    }
}

enum AIQuotaState: Equatable, Sendable {
    /// Not metered: a paid plan, or a job without a meter.
    case unmetered
    case available(remaining: Int)
    case exhausted
}

struct AIRouteContext: Equatable, Sendable {
    var job: AIJob
    var mode: AppConfig.AIMode
    var consent: Bool
    var sendPhotos: Bool
    var onDevice: OnDeviceAvailability
    /// The text is English and the prompt fits this iPhone's window.
    var fitsOnDevice: Bool = true
    var quota: AIQuotaState
    var plan: Plan
    var age: AIAgeGate
    /// "Grade again": the strongest tier first.
    var strongest: Bool = false
    /// The answer is long or the offline grade is unsure: the cloud first.
    var preferCloud: Bool = false
    /// Private Cloud Compute could answer (always false while `AIBuild.privateCloudEnabled` is off).
    var privateCloud: Bool = false
}

struct AIRoute: Equatable, Sendable {
    /// Model tiers to try, in order, after the instant offline answer. Empty: the rules' answer is final.
    var tiers: [AITier]
    var suggestion: AISuggestion?
    /// A free limit took the cloud away from this job (this iPhone's model is still on the route when it can do the job).
    var limitReached: QuotaMeter.Key?
    /// The tutor's mode when it is forced (hints first for under-18 accounts).
    var forcedTutorMode: TutorMode?
    /// With no model tier on the route: why none will answer, for the line that tells a person they mark an answer themselves.
    var whyNoModel: SelfCheckReason?

    var usesCloud: Bool { tiers.contains(.cloud) }
}

enum AIRouting {

    static func route(_ c: AIRouteContext) -> AIRoute {
        let forced: TutorMode? = c.job == .tutor && c.age != .adult ? .hints : nil

        // 1. A free limit takes the cloud away from a metered job and asks for the paywall. It does not touch this iPhone's own
        // model: a limit pays for Cloud AI, and the iPhone's model is free to run, so it keeps the jobs it can do (and the rules
        // always answer).
        let limited: QuotaMeter.Key? = c.plan.isPaid || c.quota != .exhausted ? nil : c.job.meter

        // 2. Who could answer.
        let hasRelay = c.mode == .relay || c.mode == .mock
        let cloudPossible = hasRelay && c.age != .child
        let photosOK = c.job != .transcribeImage || c.sendPhotos
        let cloudOK = cloudPossible && c.consent && photosOK && limited == nil
        let deviceOK = c.job.runsOnDevice && c.onDevice == .available && c.fitsOnDevice
        let privateCloudOK = AIBuild.privateCloudEnabled && c.privateCloud && c.consent && c.age != .child
            && c.job.runsOnDevice && !deviceOK && limited == nil

        // 3. In what order.
        let order: [AITier]
        switch c.job {
        case .grade:
            order = c.strongest || c.preferCloud ? [.cloud, .onDevice] : [.onDevice, .cloud]
        case .confusions, .transcribeImage:
            order = [.cloud]
        case .generate, .tutor, .lecture, .cardsFromChat:
            order = [.cloud, .privateCloud, .onDevice]
        }
        let tiers = order.filter { tier in
            switch tier {
            case .cloud: cloudOK
            case .onDevice: deviceOK
            case .privateCloud: privateCloudOK
            case .rules: false
            }
        }

        // 4. What the UI may offer: the paywall for a limit that was reached, else consent, when that is all that keeps a cloud that
        // would help out of the route.
        var suggestion: AISuggestion?
        if let limited {
            suggestion = .upgrade(limited, message: AIFreeLimits.cardLine(for: limited, deviceKeepsWorking: tiers.contains(.onDevice)))
        } else if cloudPossible, !tiers.contains(.cloud), cloudWouldHelp(c, deviceOK: deviceOK) {
            if !c.consent {
                suggestion = .allowCloud(feature: c.job.feature)
            } else if !photosOK {
                suggestion = .allowPhotos
            }
        }

        // 5. With no model at all, why: what a person who has to do the job themselves is told. Cloud AI being off comes first (it is
        // theirs to turn on), then a free limit; a build with no relay and a child's account never had the cloud to turn on.
        var whyNoModel: SelfCheckReason?
        if tiers.isEmpty {
            if cloudPossible && !c.consent {
                whyNoModel = .cloudOff
            } else if limited != nil {
                whyNoModel = .freeLimit
            } else {
                whyNoModel = .deviceUnavailable
            }
        }
        return AIRoute(tiers: tiers, suggestion: suggestion, limitReached: limited, forcedTutorMode: forced, whyNoModel: whyNoModel)
    }

    /// Offering Cloud AI is worth it: always for the jobs it does far better; for grading only when this iPhone
    /// can't refine the grade, the answer is long or shaky, or the person asked for a second look.
    private static func cloudWouldHelp(_ c: AIRouteContext, deviceOK: Bool) -> Bool {
        switch c.job {
        case .grade: !deviceOK || c.strongest || c.preferCloud
        default: true
        }
    }
}
