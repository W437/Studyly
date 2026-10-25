#if DEBUG
import ActivityKit
import AVFoundation
import CoreHaptics
import Foundation
import UIKit
import UserNotifications
import VisionKit

/// What a simulator can't show, measured on a real iPhone (DEBUG only). Launch with
///
///     CRAMLESS_UITEST=1 CRAMLESS_MOCK_AI=0 CRAMLESS_SEED=0 CRAMLESS_PROBE=1
///
/// (`scripts/device_probe.sh <udid>` does it and copies the report off the phone). With no relay configured the
/// AI runs in `local` mode, so on an Apple Intelligence iPhone every AI job below goes to the on-device model through
/// the app's own router: generation from the sample page's text, grading two answers, a tutor question. Then speech
/// (the phone speaks a paragraph into a file with its own voice and the lecture transcriber reads it back), VisionKit,
/// a Live Activity, haptics hardware and notification permission. The report is `Documents/probe-report.json`.
@MainActor
enum DeviceProbe {
    static func runIfRequested(app: AppModel) async {
        guard TestHarness.value("CRAMLESS_PROBE") == "1" else { return }
        var report: [String: Any] = [
            "startedAt": ISO8601DateFormatter().string(from: Date()),
            "device": UIDevice.current.model,
            "system": "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)",
            "aiMode": "\(app.config.aiMode)",
            "onDevice": "\(app.ai.onDeviceCapability)",
        ]
        write(report, done: false)

        // 1. Generation from the sample page's text (not the curated sample: a plain text source).
        let lines = SamplePage.ocr()?.lines ?? []
        let course = Course(name: "Probe Biology", color: .sky, now: app.now)
        app.context.insert(course)
        var started = Date()
        if let source = try? app.createSource(fromText: lines.map(\.text).joined(separator: "\n"),
                                              title: "Probe page", course: course) {
            let outcome = await app.ai.generateSet(app.generationInput(for: source, maxItems: 8))
            report["generate"] = [
                "seconds": Date().timeIntervalSince(started),
                "origin": outcome.origin.rawValue, "model": outcome.model, "checkedBy": outcome.checkedBy.rawValue,
                "note": outcome.note ?? "", "items": outcome.items.count, "dropped": outcome.dropped.count,
                "droppedReasons": outcome.dropped.map { "\($0)" }.prefix(4).map { $0 },
                "sample": outcome.items.prefix(8).map { item in
                    ["kind": item.kind.rawValue, "topic": item.topic, "prompt": item.prompt, "answer": item.answer,
                     "keyIdeas": item.keyIdeas.map(\.label), "choices": item.choices.map(\.text),
                     "anchors": item.anchors.count]
                },
            ]
        } else {
            report["generate"] = ["error": "the probe source could not be made"]
        }
        write(report, done: false)

        // 2. Grading two answers to "why do cells divide by mitosis?".
        if let fixture = SamplePage.generated()?.items.first(where: { $0.id == "i1" }) {
            let subject = GradeSubject(kind: fixture.kind, prompt: fixture.prompt, modelAnswer: fixture.answer,
                                       keyIdeas: fixture.keyIdeas)
            var grades: [[String: Any]] = []
            for answer in ["So the body can grow and repair tissue, making two identical cells.",
                           "To get bigger and fix wounds. Each new cell gets an exact copy of the DNA and the same number of chromosomes."] {
                started = Date()
                let grade = await app.ai.gradeNow(subject, answer: .text(answer))
                grades.append(["answer": answer, "seconds": Date().timeIntervalSince(started),
                               "gradedBy": grade.gradedBy.rawValue, "model": grade.model, "score": grade.score,
                               "verdict": grade.verdict.rawValue, "confidence": grade.confidence,
                               "hits": grade.hitIdeaIDs, "missing": grade.missing.map { "\($0)" },
                               "feedback": grade.feedback, "fix": grade.fix, "marks": grade.marks.count])
            }
            report["grade"] = grades
        }
        write(report, done: false)

        // 3. A tutor question about the probe page.
        started = Date()
        let input = TutorInput(messages: [TutorMessage(role: .user, text: "What's the difference between mitosis and cytokinesis?")],
                               course: course.name, material: app.tutorMaterial(courseID: course.id), context: nil)
        if let reply = await app.ai.tutorReply(input) {
            report["tutor"] = ["seconds": Date().timeIntervalSince(started), "origin": reply.origin.rawValue,
                               "model": reply.model, "mode": reply.mode.rawValue, "grounded": reply.grounded,
                               "citations": reply.citations.map(\.label), "text": reply.text]
        } else {
            report["tutor"] = ["error": "no reply"]
        }
        write(report, done: false)

        // 4. Speech: the phone speaks a paragraph into a file, the lecture transcriber reads it back.
        report["speech"] = await speechRoundTrip()
        write(report, done: false)

        // 5. The rest of the hardware.
        report["visionKitScanner"] = VNDocumentCameraViewController.isSupported
        report["haptics"] = CHHapticEngine.capabilitiesForHardware().supportsHaptics
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        report["notifications"] = "\(settings.authorizationStatus.rawValue)"
        report["liveActivities"] = await liveActivityRoundTrip(app: app)

        report["finishedAt"] = ISO8601DateFormatter().string(from: Date())
        write(report, done: true)
        app.router.toast("Device probe finished", systemImage: "checkmark.seal.fill")
    }

    private static func speechRoundTrip() async -> [String: Any] {
        let gate = await TranscriptionGate.resolve(preferredLanguages: ["en-US"])
        guard case .available(let choice) = gate else { return ["availability": "\(gate)"] }
        var result: [String: Any] = ["availability": "available", "choice": "\(choice)"]
        let started = Date()
        do {
            try await LectureSpeechModels.install(choice)
            result["installSeconds"] = Date().timeIntervalSince(started)
        } catch {
            result["installError"] = "\(error)"
            return result
        }
        let spoken = "Prophase first. The chromatin condenses, and you can see the chromosomes. "
            + "This one will be on the midterm: anaphase is where the sister chromatids get pulled apart."
        let url = FileManager.default.temporaryDirectory.appending(path: "probe-speech.caf")
        guard await synthesize(spoken, to: url) else {
            result["synthesis"] = "failed"
            return result
        }
        let t = Date()
        do {
            let segments = try await LectureFileTranscriber.transcribe(url, choice: choice)
            result["seconds"] = Date().timeIntervalSince(t)
            result["segments"] = segments.count
            result["transcript"] = segments.map(\.text).joined(separator: " ")
            result["flags"] = ExamFlagDetector.phraseFlags(in: segments).map(\.text)
        } catch {
            result["error"] = "\(error)"
        }
        return result
    }

    /// Writes `text` spoken by the system voice into a CAF file.
    private static func synthesize(_ text: String, to url: URL) async -> Bool {
        try? FileManager.default.removeItem(at: url)
        let synthesizer = AVSpeechSynthesizer()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        return await withCheckedContinuation { continuation in
            var file: AVAudioFile?
            var finished = false
            synthesizer.write(utterance) { buffer in
                guard !finished else { return }
                guard let pcm = buffer as? AVAudioPCMBuffer else { return }
                if pcm.frameLength == 0 {
                    finished = true
                    continuation.resume(returning: file != nil)
                    return
                }
                do {
                    if file == nil { file = try AVAudioFile(forWriting: url, settings: pcm.format.settings) }
                    try file?.write(from: pcm)
                } catch {
                    finished = true
                    continuation.resume(returning: false)
                }
            }
        }
    }

    private static func liveActivityRoundTrip(app: AppModel) async -> [String: Any] {
        let enabled = ActivityAuthorizationInfo().areActivitiesEnabled
        app.liveActivities.startSession(title: "Probe session", total: 5, plannedMinutes: 5)
        try? await Task.sleep(for: .seconds(2))
        app.liveActivities.update(answered: 2, correct: 2, topic: "Phases of mitosis")
        try? await Task.sleep(for: .seconds(1))
        let running = Activity<StudySessionAttributes>.activities.count
        app.liveActivities.end()
        return ["enabled": enabled, "runningDuringProbe": running]
    }

    private static func write(_ report: [String: Any], done: Bool) {
        var report = report
        report["done"] = done
        let url = URL.documentsDirectory.appending(path: "probe-report.json")
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
#endif
