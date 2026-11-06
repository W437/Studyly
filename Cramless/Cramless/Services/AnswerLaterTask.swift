import BackgroundTasks
import OSLog

/// The background refresh that answers questions kept for later while the app is away. The system decides when it runs (hence "when you're
/// online" in the copy, never a time). Registered before launch finishes, in the app delegate; the identifier is in Info.plist's
/// `BGTaskSchedulerPermittedIdentifiers`, with the `fetch` background mode.
enum AnswerLaterTask {
    static let identifier = "com.loopware.Capling.answer-later"
    /// The soonest it is asked for: the system won't run it much sooner than this anyway.
    static let earliest: TimeInterval = 15 * 60

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in await run(refresh) }
        }
    }

    /// Asks for a run, replacing the one asked for before. It fails on the Simulator and with Background App Refresh off: the next launch or
    /// return to the app answers instead.
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: earliest)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            log.notice("answer-later refresh not scheduled: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func cancel() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
    }

    @MainActor
    private static func run(_ task: BGAppRefreshTask) async {
        guard let app = AppModel.live else {
            task.setTaskCompleted(success: false)
            return
        }
        let work = Task { @MainActor in
            // A launch into the background has not started the account (`AppModel.start` runs with the first screen).
            await app.account.start()
            return await app.answerWaitingQuestions(trigger: .background)
        }
        task.expirationHandler = { work.cancel() }
        _ = await work.value
        app.scheduleAnswerLater()
        task.setTaskCompleted(success: !work.isCancelled)
    }

    private static let log = Logger(subsystem: "com.loopware.Capling", category: "answer-later")
}
