import Foundation
import SwiftData

/// The rules of "Answer it later": a question asked while Cloud AI could not be reached, kept for when it can. The tutor only, never the
/// assistant: nothing is drafted while the student isn't looking.
enum AnswerLater {
    /// The most questions kept at once.
    static let maxWaiting = 3
    /// A question not answered in this many days is dropped: by then the exam has moved on, and the offline reply stays in the chat.
    static let daysKept = 7

    enum Trigger: Equatable, Sendable {
        case launch, active, reconnected, background
    }

    /// Whether a question kept since `since` has passed its time.
    static func isExpired(since: Date, now: Date, calendar: Calendar) -> Bool {
        guard let last = calendar.date(byAdding: .day, value: daysKept, to: since) else { return false }
        return now >= last
    }
}

extension AppModel {

    // MARK: Reading

    /// The questions kept for later, oldest first.
    func waitingQuestions() -> [ChatMessage] {
        fetch(FetchDescriptor<ChatMessage>(predicate: #Predicate { $0.waitingSince != nil }, sortBy: [SortDescriptor(\.createdAt)]))
            .sorted { ($0.waitingSince ?? .distantPast) < ($1.waitingSince ?? .distantPast) }
    }

    // MARK: Keeping

    /// Keeps a question for later. False when three already wait, or Cloud AI isn't allowed (no consent, under 13): what the student sees is
    /// then decided by `waitingQuestions().count` and the offer's own check.
    @discardableResult
    func keepForLater(questionID: UUID) -> Bool {
        guard let question = fetch(FetchDescriptor<ChatMessage>(predicate: #Predicate { $0.id == questionID })).first,
              question.role == .user, question.contextItemID == nil, question.waitingSince == nil,
              waitingQuestions().count < AnswerLater.maxWaiting, ai.cloudStillAllowed() else { return false }
        question.waitingSince = now
        save()
        watchForConnection()
        scheduleAnswerLater()
        return true
    }

    // MARK: Answering

    /// What `ai.tutor` needs to answer a kept question: the chat as it stood up to that question, so what was said after it plays no part.
    func tutorInput(for thread: ChatThread, upTo question: ChatMessage) -> TutorInput {
        let upTo = thread.sortedMessages.filter { $0.createdAt <= question.createdAt }
        let course = liveCourse(thread.courseID)
        return TutorInput(messages: upTo.map { TutorMessage(role: $0.role, text: $0.text) }, course: course?.name,
                          material: tutorMaterial(courseID: course?.id), context: nil,
                          fromPhoto: upTo.contains(where: \.fromPhoto), lastIsPhotoText: question.fromPhoto)
    }

    /// Answers the questions kept for later, oldest first, for as long as Cloud AI answers. A free limit, no connection or a server error stops
    /// the round and they go on waiting (a free limit lifts at midnight); consent withdrawn or an account under 13 sends nothing. Each answer
    /// is one tutor message on the meter. Returns how many were answered. One round at a time.
    @discardableResult
    func answerWaitingQuestions(trigger: AnswerLater.Trigger) async -> Int {
        guard !answeringLater else { return 0 }
        answeringLater = true
        defer { answeringLater = false }
        dropExpiredQuestions()
        var answered: [ChatThread] = []
        for question in waitingQuestions() {
            if Task.isCancelled { break }
            guard let thread = question.thread, thread.modelContext != nil else { continue }
            // The student is mid-question in this chat: the next trigger takes it.
            if AskStreams.shared.isAnswering(thread.id) { continue }
            guard let outcome = await ai.cloudTutorReply(tutorInput(for: thread, upTo: question)) else { break }
            // Read again after the wait: the chat may be gone.
            guard question.modelContext != nil, question.waitingSince != nil, thread.modelContext != nil else { continue }
            saveLateAnswer(outcome, to: question, in: thread)
            answered.append(thread)
        }
        announce(answered, trigger: trigger)
        syncAnswerLaterWatch()
        return answered.count
    }

    /// The answer goes right after the reply Cap gave at the time, so it reads in order however far the chat has gone on; the chat rises in the
    /// history, and the question stops waiting.
    private func saveLateAnswer(_ outcome: TutorOutcome, to question: ChatMessage, in thread: ChatThread) {
        let sorted = thread.sortedMessages
        let at = sorted.firstIndex { $0.id == question.id } ?? sorted.count - 1
        var previous = at
        if sorted.indices.contains(at + 1), sorted[at + 1].role == .assistant { previous = at + 1 }
        let after = sorted[previous].createdAt
        let time = sorted.indices.contains(previous + 1)
            ? after.addingTimeInterval(sorted[previous + 1].createdAt.timeIntervalSince(after) / 2)
            : max(now, after.addingTimeInterval(0.001))
        let message = ChatMessage(thread: thread, role: .assistant, text: outcome.text.trimmingCharacters(in: .whitespacesAndNewlines),
                                  citations: outcome.citations, origin: outcome.origin.rawValue, answersQuestionID: question.id, now: time)
        context.insert(message)
        thread.messages.append(message)
        question.waitingSince = nil
        thread.updatedAt = now
        save()
    }

    private func dropExpiredQuestions() {
        var dropped = false
        for question in waitingQuestions() where AnswerLater.isExpired(since: question.waitingSince ?? now, now: now, calendar: calendar) {
            question.waitingSince = nil
            dropped = true
        }
        if dropped { save() }
    }

    /// In the app the answer just appears, with a toast; away from it, a quiet notification. Outside the rule for "Cap noticed" notifications:
    /// the student asked for this one.
    private func announce(_ threads: [ChatThread], trigger: AnswerLater.Trigger) {
        guard let last = threads.last else { return }
        if trigger == .background {
            if sideEffectsEnabled { notifications.postAnswered(threads.map { (id: $0.id, title: $0.title) }) }
        } else if router.tab == .ask {
            router.toast("Answered when you were back online", systemImage: "wifi")
        } else {
            router.toast("Answered when you were back online", systemImage: "wifi", actionTitle: "Open", action: .push(.chat(last.id), .ask))
        }
    }

    // MARK: When

    /// The first screen is up: answer what waited, then watch for the connection.
    func answerLaterOnLaunch() async {
        #if DEBUG
        if let ms = OfflineHarness.backOnlineAfter {
            Task {
                try? await nap(ms + 150)
                await answerWaitingQuestions(trigger: .reconnected)
            }
        }
        #endif
        await answerWaitingQuestions(trigger: .launch)
        syncAnswerLaterWatch()
    }

    func answerLaterOnActive() {
        Task { await answerWaitingQuestions(trigger: .active) }
    }

    /// Off the screen: no monitor, and the system's refresh is asked for while anything waits.
    func answerLaterOnBackground() {
        connectivity.stop()
        scheduleAnswerLater()
    }

    /// The connection is only watched while the app is active and a question waits.
    private func syncAnswerLaterWatch() {
        if waitingQuestions().isEmpty {
            connectivity.stop()
            if sideEffectsEnabled { AnswerLaterTask.cancel() }
        } else {
            watchForConnection()
        }
    }

    private func watchForConnection() {
        guard sideEffectsEnabled else { return }
        connectivity.start { [weak self] in
            guard let self else { return }
            Task { await self.answerWaitingQuestions(trigger: .reconnected) }
        }
    }

    func scheduleAnswerLater() {
        guard sideEffectsEnabled, !config.isHarness, !waitingQuestions().isEmpty else { return }
        AnswerLaterTask.schedule()
    }
}
