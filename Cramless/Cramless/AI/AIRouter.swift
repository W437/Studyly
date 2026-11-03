import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The feature-facing AI service, `app.ai`: the one API screens call for every AI job. It never presents UI and
/// never commits anything: generated sets are drafts, grades are values, tutor answers are a stream.
///
/// Every job runs the same ladder:
///   1. the offline rules' answer (T0), always, at once, never metered;
///   2. then, if the pure routing function allows (`AIRouting.route`), this iPhone's model (T1) and/or the relay
///      (T3), in the job's order, each falling back quietly to the next and finally to the rules' answer.
/// Consent missing where the cloud would help comes back as `suggestion` (the UI shows the consent sheet and runs
/// the job again); a free limit comes back as `limitReached` (the UI shows the paywall). Every cloud request is
/// built from what is true at the moment it is sent: settings are read again after any wait.
///
/// `app` is held weakly (`AppModel` owns this service). Tests replace the collaborators below.
@MainActor
@Observable
final class AIRouter {
    @ObservationIgnored weak var app: AppModel?

    // MARK: Collaborators (built from the app's config; tests replace them)

    /// Replaces the transport the config would build.
    @ObservationIgnored var transportOverride: (any RelayTransport)?
    /// Replaces `config.aiMode`.
    @ObservationIgnored var modeOverride: AppConfig.AIMode?
    @ObservationIgnored var probe: any OnDeviceProbe
    /// How the offline tutor searches the notes (`OfflineSearch`): tests turn the system's models off so that an answer does not depend
    /// on which models the machine they run on has.
    @ObservationIgnored var offlineSearch = OfflineSearch.Options()
    /// T1. Never reached unless the route chose it.
    @ObservationIgnored var onDevice: any OnDeviceBackend = FoundationModelsBackend()
    /// T2: nil in this release (`AIBuild.privateCloudEnabled`).
    @ObservationIgnored var privateCloud: (any OnDeviceBackend)?
    /// Multiplies the mock transport's waits.
    @ObservationIgnored var mockLatencyScale: Double = 1
    /// The pause between the pieces of an answer made at once (offline, on device), so it arrives like the cloud's.
    @ObservationIgnored var streamPause: Duration = .milliseconds(24)
    /// The pause between one drafted card being checked against the notes and the next, so the checks can be watched.
    @ObservationIgnored var assistantBeat: Duration = .milliseconds(130)
    /// After the relay said it has no assistant, Ask Cap doesn't ask again until then.
    @ObservationIgnored var assistantRetryAt: Date?
    /// The relay refused the last cloud request for a limit that isn't a free meter: a paid plan's fair use, or the day's cost cap.
    /// The tutor says so in its note, instead of "couldn't be reached". Cleared before each cloud attempt.
    @ObservationIgnored var cloudRefused = false
    /// The relay's scan window as this run has seen it (`ScanWindow`): a page reading and the question-writing after it are one scan.
    @ObservationIgnored var scanWindow = ScanWindow()

    // MARK: State the UI can read

    /// The server's last word on the free limits (nil before the first refresh, and without a relay).
    private(set) var serverQuota: QuotaStatus?
    /// Cloud requests sent from this iPhone (counted against the free limits), and this iPhone's own model use (kept on the side,
    /// never counted against them).
    private(set) var usage: AIUsageLedger
    /// The latest suggestion a job made.
    private(set) var lastSuggestion: AISuggestion?

    @ObservationIgnored private var serverQuotaFetchedAt: Date?
    /// The relay's own words for each limit it reported.
    @ObservationIgnored private var limitMessages: [QuotaMeter.Key: AISuggestion] = [:]

    init(app: AppModel) {
        self.app = app
        let isTests = app.config.environment["XCTestConfigurationFilePath"] != nil
        self.probe = SystemOnDeviceProbe(allowed: !isTests)
        self.usage = AIUsageLedger.load(from: app.defaults)
        #if DEBUG
        // `CRAMLESS_DEVICE_AI=off` says this iPhone's own model isn't there, whatever the Simulator or the phone has, so a screenshot of an
        // answer with no model to grade it (the self-check) repeats.
        if app.config.environment["CRAMLESS_DEVICE_AI"] == "off" { probe = FixedOnDeviceProbe(.unavailable(.deviceNotEligible)) }
        // `CRAMLESS_MOCK_LATENCY=<scale>` multiplies the mock relay's waits, so a screenshot can catch "Double-checking…" (and the model
        // being let go after `SelfCheck.modelWait`).
        if let scale = app.config.environment["CRAMLESS_MOCK_LATENCY"].flatMap(Double.init) { mockLatencyScale = scale }
        #endif
    }

    // MARK: Mode, transport, consent

    var mode: AppConfig.AIMode { modeOverride ?? app?.config.aiMode ?? .local }

    /// The relay as this run reaches it: HTTP with a configured project, the fixtures in mock mode, none locally.
    var transport: (any RelayTransport)? {
        if let transportOverride { return transportOverride }
        guard let app else { return nil }
        switch mode {
        case .relay:
            guard let url = app.config.supabaseURL, let key = app.config.supabaseAnonKey else { return nil }
            return HTTPRelayTransport(baseURL: url, anonKey: key, tokens: app.account)
        case .mock:
            return MockRelayTransport(latencyScale: mockLatencyScale)
        case .local:
            return nil
        }
    }

    /// This build can reach Cloud AI at all (a relay is configured, or the mock).
    var cloudAvailableInThisBuild: Bool { mode != .local }

    /// Cloud consent as the router counts it. In mock mode it counts as granted (nothing leaves the device),
    /// unless the harness asks to see the consent flow (`CRAMLESS_CONSENT=0`) and the person hasn't allowed it yet.
    var hasCloudConsent: Bool {
        guard let app else { return false }
        if AIConsent.isGranted(app.settings) { return true }
        if mode == .mock { return app.config.environment["CRAMLESS_CONSENT"] != "0" }
        return false
    }

    var onDeviceCapability: OnDeviceCapability { probe.capability() }

    var budget: OnDeviceBudget { OnDeviceBudget(contextSize: probe.capability().contextSize) }

    func backend(for tier: AITier) -> any OnDeviceBackend {
        tier == .privateCloud ? (privateCloud ?? onDevice) : onDevice
    }

    // MARK: Routing

    /// The facts for one job, read now.
    func routeContext(_ job: AIJob, content: String? = nil, promptFits: Bool = true, strongest: Bool = false,
                      preferCloud: Bool = false) -> AIRouteContext {
        let settings = app?.settings ?? AppSettings()
        let capability = probe.capability()
        var fits = promptFits
        if fits, capability.availability.isAvailable, let content {
            fits = languageVerdict(content).isSupported
        }
        return AIRouteContext(job: job, mode: mode, consent: hasCloudConsent, sendPhotos: settings.sendPhotos,
                              onDevice: capability.availability, fitsOnDevice: fits, quota: quotaState(for: job),
                              plan: plan, age: AIAgeGate(settings), strongest: strongest, preferCloud: preferCloud,
                              privateCloud: capability.privateCloudAvailable)
    }

    func route(_ job: AIJob, content: String? = nil, promptFits: Bool = true, strongest: Bool = false,
               preferCloud: Bool = false) -> AIRoute {
        var route = AIRouting.route(routeContext(job, content: content, promptFits: promptFits, strongest: strongest,
                                                 preferCloud: preferCloud))
        // A limit the relay already reported keeps the relay's words.
        if let key = route.limitReached { route.suggestion = limitSuggestion(key, deviceKeepsWorking: route.tiers.contains(.onDevice)) }
        if let suggestion = route.suggestion, suggestion != lastSuggestion { lastSuggestion = suggestion }
        return route
    }

    /// The cloud may still be used for the rest of a job already under way (the check pass after a generate):
    /// consent and the relay, read again after the wait. The job's quota was counted when it started.
    func cloudStillAllowed() -> Bool {
        guard let app, transport != nil else { return false }
        return hasCloudConsent && AIAgeGate(app.settings) != .child
    }

    func languageVerdict(_ text: String) -> OnDeviceLanguageGate.Verdict {
        let probe = self.probe
        return OnDeviceLanguageGate.verdict(for: text, supportsLocale: { probe.supportsLocale($0) })
    }

    func clearSuggestion() {
        if lastSuggestion != nil { lastSuggestion = nil }
    }

    // MARK: Plan and quota

    /// The plan: the store's when paid, else the server's, else free.
    var plan: Plan {
        if let storePlan = app?.purchases.plan, storePlan.isPaid { return storePlan }
        return serverQuota?.plan ?? .free
    }

    /// Whether a job's free limit is reached: Cloud AI use only (the server's count, or this iPhone's own count of the cloud requests
    /// it sent when that is larger: before the first fetch, or after midnight made the server's stale). A limit pays for Cloud AI, so
    /// this iPhone's own model never counts. Reading it changes nothing (safe from a view's body).
    func quotaState(for job: AIJob) -> AIQuotaState {
        guard let key = job.meter else { return .unmetered }
        if plan.isPaid { return .unmetered }
        let server = currentServerMeter(key)
        if let server, server.limit == nil { return .unmetered }
        let limit = server?.limit ?? AIFreeLimits.limit(key)
        let used = cloudUsed(key, server: server, ledger: currentUsage)
        // Writing questions rides for free on a scan window a page reading just opened, even with the week's scans used up.
        if used >= limit, job == .generate, canRideOpenScanWindow { return .available(remaining: 0) }
        return used >= limit ? .exhausted : .available(remaining: limit - used)
    }

    /// A question-writing request would ride on the scan window that is still open (a page reading made a moment ago).
    var canRideOpenScanWindow: Bool {
        guard let app else { return false }
        return scanWindow.canRideGenerate(at: app.now, week: AIUsageLedger.weekKey(app.now, calendar: app.calendar))
    }

    /// Counts a successful scan-metered cloud request the way the relay does: a new scan only when it opens a window.
    func recordScanRequest(_ kind: ScanWindow.Kind, pages: Int) {
        guard let app else { return }
        let week = AIUsageLedger.weekKey(app.now, calendar: app.calendar)
        if scanWindow.record(kind, pages: pages, at: app.now, week: week, pageCap: AIFreeLimits.pagesPerScan(plan)) {
            recordCloudUse(.scans)
        }
    }

    /// How many free Cloud AI uses of a metered job are left in this period, when that is worth telling the person: the free plan, with
    /// Cloud AI allowed on this build for an account that may use it. Nil otherwise (a paid plan, Cloud AI off or not in this build, a
    /// child's account, a job with no meter). 0 once they are used up. Reading it changes nothing (safe from a view's body).
    func freeCloudUsesLeft(for job: AIJob) -> Int? {
        guard cloudAvailableInThisBuild, hasCloudConsent, let app, AIAgeGate(app.settings) != .child else { return nil }
        switch quotaState(for: job) {
        case .available(let remaining): return remaining
        case .exhausted: return 0
        case .unmetered: return nil
        }
    }

    /// The limits as the UI shows them: each meter's Cloud AI use.
    var quotaStatus: QuotaStatus {
        let paid = plan.isPaid
        let ledger = currentUsage
        let meters = AIFreeLimits.keys.map { key -> QuotaMeter in
            let server = currentServerMeter(key)
            let limit: Int? = paid ? nil : (server != nil ? server!.limit : AIFreeLimits.limit(key))
            return QuotaMeter(key: key, used: cloudUsed(key, server: server, ledger: ledger), limit: limit,
                              period: AIFreeLimits.period(key))
        }
        return QuotaStatus(plan: plan, meters: meters)
    }

    /// Cloud requests in the current period: the server's count and this iPhone's own are combined with `max`, never added (the
    /// server's, when current, already includes this iPhone's).
    private func cloudUsed(_ key: QuotaMeter.Key, server: QuotaMeter?, ledger: AIUsageLedger) -> Int {
        max(server?.used ?? 0, ledger.cloudUsed(key))
    }

    /// This iPhone's usage ledger with ended periods cleared, without writing anything.
    private var currentUsage: AIUsageLedger {
        guard let app else { return usage }
        var ledger = usage
        ledger.roll(to: app.now, calendar: app.calendar)
        return ledger
    }

    /// The server's meter, if it is from the current day or week (a count from before midnight is stale).
    private func currentServerMeter(_ key: QuotaMeter.Key) -> QuotaMeter? {
        guard let meter = serverQuota?.meter(key), let fetched = serverQuotaFetchedAt, let app else { return nil }
        let same = AIFreeLimits.period(key) == .day
            ? AIUsageLedger.dayKey(fetched, calendar: app.calendar) == AIUsageLedger.dayKey(app.now, calendar: app.calendar)
            : AIUsageLedger.weekKey(fetched, calendar: app.calendar) == AIUsageLedger.weekKey(app.now, calendar: app.calendar)
        return same ? meter : QuotaMeter(key: key, used: 0, limit: meter.limit, period: meter.period)
    }

    /// One use of this iPhone's model for a metered job, kept on the side (`AIUsageLedger.counts`). It never counts against a free
    /// limit: the model costs nothing to run, and a limit exists to pay for Cloud AI. The rules are never counted either.
    func recordOnDeviceUse(_ key: QuotaMeter.Key?) {
        guard let key, let app, !plan.isPaid else { return }
        usage.record(key, now: app.now, calendar: app.calendar)
        usage.save(to: app.defaults)
    }

    /// One cloud use: counted on this iPhone, and on our copy of the server's meter until the next refresh. Mock
    /// mode keeps no count of its own (its quota story is the fixtures', and demos must not run out).
    func recordCloudUse(_ key: QuotaMeter.Key?) {
        guard let key, let app else { return }
        if mode != .mock {
            usage.recordCloud(key, now: app.now, calendar: app.calendar)
            usage.save(to: app.defaults)
        }
        guard var quota = serverQuota, let i = quota.meters.firstIndex(where: { $0.key == key }) else { return }
        quota.meters[i].used += 1
        serverQuota = quota
    }

    /// A quota error from the relay: keep the server's counts it carried and say which free meter is used up (nil
    /// when it isn't a free limit: a paid plan's fair-use ceiling or the relay's hidden `extras` meter, which just
    /// fall back quietly; a paid plan never sees the paywall).
    func absorbQuotaError(_ error: RelayError, meter: QuotaMeter.Key?) -> QuotaMeter.Key? {
        guard case .quotaExceeded(let status, let message) = error else { return nil }
        cloudRefused = true
        if let status {
            // Only the meters it names change; the others keep their last counts.
            var merged = serverQuota ?? QuotaStatus(plan: status.plan, meters: [])
            merged.plan = status.plan
            for meter in status.meters {
                if let i = merged.meters.firstIndex(where: { $0.key == meter.key }) { merged.meters[i] = meter } else { merged.meters.append(meter) }
            }
            serverQuota = merged
            serverQuotaFetchedAt = app?.now
        }
        if (status?.plan ?? plan).isPaid || plan.isPaid { return nil }
        // A free limit names its meter; a 429 with no meters (`extras`, a rate limit) is a plain failure.
        guard let status, !status.meters.isEmpty, let key = meter ?? status.meters.first?.key else { return nil }
        let suggestion = AISuggestion.upgrade(key, message: message.isEmpty ? AIFreeLimits.message(for: key) : message)
        lastSuggestion = suggestion
        limitMessages[key] = suggestion
        return key
    }

    /// The paywall suggestion for a reached limit: the relay's words when it said them, else the app's, which say that the person marks
    /// or the iPhone's AI carries on. This one is for a job with no iPhone model to carry on.
    func limitSuggestion(_ key: QuotaMeter.Key) -> AISuggestion {
        limitSuggestion(key, deviceKeepsWorking: false)
    }

    /// The same, in words that say whether this iPhone's own AI keeps the job going.
    func limitSuggestion(_ key: QuotaMeter.Key, deviceKeepsWorking: Bool) -> AISuggestion {
        limitMessages[key] ?? .upgrade(key, message: AIFreeLimits.cardLine(for: key, deviceKeepsWorking: deviceKeepsWorking))
    }

    /// Fetches the server's meters (only once Cloud AI is allowed: asking needs an account) and returns the
    /// limits as the UI shows them.
    @discardableResult
    func refreshQuota() async -> QuotaStatus {
        if cloudStillAllowed(), let transport {
            if let status = try? await transport.quota() {
                serverQuota = status
                serverQuotaFetchedAt = app?.now
            }
        }
        return quotaStatus
    }

    #if DEBUG
    /// Tests: set the server's meters as if just fetched.
    func setServerQuota(_ status: QuotaStatus?) {
        serverQuota = status
        serverQuotaFetchedAt = status == nil ? nil : app?.now
    }

    func resetUsage() {
        usage = AIUsageLedger()
        if let app { usage.save(to: app.defaults) }
    }
    #endif

    // MARK: Streaming text made at once

    /// Splits a finished answer into a few words at a time, the way the cloud's arrive.
    static func pieces(of text: String, wordsPerPiece: Int = 3) -> [String] {
        var out: [String] = []
        var current = ""
        var words = 0
        for character in text {
            current.append(character)
            if character == " " {
                words += 1
                if words >= wordsPerPiece { out.append(current); current = ""; words = 0 }
            }
        }
        if !current.isEmpty { out.append(current) }
        return out
    }

    func pause() async {
        guard streamPause > .zero else { return }
        try? await Task.sleep(for: streamPause)
    }
}

/// Page photos as the relay receives them: decoded at the size sent (about 1300 px on the long edge), JPEG at
/// 0.55, base64. Vision models don't need native resolution and the person doesn't need the upload. Off the main
/// thread.
enum AIImagePrep {
    static func base64JPEG(at url: URL, longEdge: Int = 1300, quality: Double = 0.55) async -> String? {
        await Task.detached(priority: .userInitiated) { () -> String? in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: longEdge,
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
            CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { return nil }
            return (data as Data).base64EncodedString()
        }.value
    }
}
