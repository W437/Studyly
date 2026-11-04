import Foundation
import FoundationModels
import NaturalLanguage
#if canImport(UIKit)
import UIKit
#endif

#if DEBUG
/// Measures what the offline tutor and this iPhone's model cost on the device it runs on (DEBUG only), for what a Mac cannot tell: how long the first
/// question takes (the system's models load), how long the next ones take, how much memory they hold, how hot the phone gets, and what the model
/// does with the passages it is handed. Launch it with the variable set; nothing else of the app is used and nothing leaves the phone:
///
///     xcrun devicectl device copy to --device <id> --source in.json --destination Documents/offline_bench_in.json \
///         --domain-type appDataContainer --domain-identifier com.loopware.Capling
///     xcrun devicectl device process launch --device <id> --terminate-existing \
///         --environment-variables '{"CRAMLESS_OFFLINE_BENCH":"1"}' com.loopware.Capling
///     xcrun devicectl device copy from --device <id> --source Documents/offline_bench_out.json --destination out.json ...
///
/// `Documents/offline_bench_in.json`: `{"libraries": [{"name": "...", "material": [{"title": "...", "pages": [{"label": "1", "lines": ["..."]}]}],
/// "questions": ["..."], "pipeline": true}]}`. With `"pipeline": true` every question also goes through what the router does when Cloud AI is out of reach:
/// the keyword search, the sentence search, this iPhone's model on the passages of the best sentences, the checks on its reply, and the offline
/// tutor's own reply behind it; the report keeps each reply to score against the lines that answer. The report, `Documents/offline_bench_out.json`,
/// is written again after every step, so a phone that is stopped part way leaves what it measured. `"choose": true` also lets the model choose the answering
/// sentence among the search's best (`OnDevicePickCall`) and keeps both offline replies, before and after; `"skipFreeForm": true` leaves out the model's own answer.
enum OfflineBench {
    static func runIfRequested() {
        guard ProcessInfo.processInfo.environment["CRAMLESS_OFFLINE_BENCH"] == "1" else { return }
        Task.detached(priority: .userInitiated) { await run() }
    }

    // MARK: Measures

    /// The app's memory footprint in megabytes (what Jetsam counts).
    static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
    }

    static var thermal: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "unknown"
        }
    }

    static var machine: String {
        var system = utsname()
        uname(&system)
        return withUnsafePointer(to: &system.machine) { $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) } }
    }

    /// The highest footprint seen while it runs, sampled every 20 ms.
    final class PeakSampler: @unchecked Sendable {
        private let lock = NSLock()
        private var peak = 0.0
        private var running = true
        init() {
            Thread.detachNewThread { [self] in
                while true {
                    lock.lock(); let go = running; if go { peak = max(peak, OfflineBench.footprintMB()) }; lock.unlock()
                    if !go { return }
                    Thread.sleep(forTimeInterval: 0.02)
                }
            }
        }
        var value: Double { lock.lock(); defer { lock.unlock() }; return peak }
        func reset() { lock.lock(); peak = OfflineBench.footprintMB(); lock.unlock() }
        func stop() { lock.lock(); running = false; lock.unlock() }
    }

    private static func seconds(_ block: () -> Void) -> Double {
        let start = Date()
        block()
        return Date().timeIntervalSince(start)
    }

    private static func percentile(_ values: [Double], _ p: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        return sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * p))]
    }

    // MARK: Run

    static func run() async {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let inputURL = docs.appendingPathComponent("offline_bench_in.json")
        let outputURL = docs.appendingPathComponent("offline_bench_out.json")
        let sampler = PeakSampler()
        // The phone must stay awake and in front: an app that goes to the background is suspended, and the run stops with it.
        #if canImport(UIKit)
        await MainActor.run { UIApplication.shared.isIdleTimerDisabled = true }
        #endif
        var report: [String: Any] = [
            "machine": machine, "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "memoryGB": Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824,
            "lowPower": ProcessInfo.processInfo.isLowPowerModeEnabled, "thermalAtStart": thermal, "footprintAtStartMB": footprintMB(),
            "started": ISO8601DateFormatter().string(from: Date()), "finished": false,
        ]
        func save() {
            report["peakFootprintMB"] = sampler.value
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: outputURL) }
        }
        save()
        guard let data = try? Data(contentsOf: inputURL), let input = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let libraries = input["libraries"] as? [[String: Any]] else {
            report["error"] = "no readable Documents/offline_bench_in.json"
            report["finished"] = true
            save(); sampler.stop(); return
        }
        let capability = await MainActor.run { SystemOnDeviceProbe(allowed: true, buildEnabled: true).capability() }
        report["modelAvailability"] = "\(capability.availability)"
        report["modelContextSize"] = capability.contextSize
        var results: [[String: Any]] = []
        for library in libraries {
            results.append(await measure(library, capability: capability, sampler: sampler))
            report["libraries"] = results
            report["thermalNow"] = thermal
            save()
        }
        report["thermalAtEnd"] = thermal
        report["footprintAtEndMB"] = footprintMB()
        report["finished"] = true
        report["ended"] = ISO8601DateFormatter().string(from: Date())
        save()
        sampler.stop()
        #if canImport(UIKit)
        await MainActor.run { UIApplication.shared.isIdleTimerDisabled = false }
        #endif
    }

    private static func material(from library: [String: Any]) -> [TutorMaterial] {
        (library["material"] as? [[String: Any]] ?? []).map { source in
            let pages = (source["pages"] as? [[String: Any]] ?? []).enumerated().map { i, page in
                PageText(index: i, label: page["label"] as? String ?? "\(i + 1)",
                         lines: (page["lines"] as? [String] ?? []).enumerated().map { TextLine(id: "p\(i).l\($0.offset)", text: $0.element, box: nil) })
            }
            return TutorMaterial(sourceID: UUID(), title: source["title"] as? String ?? "Notes", kind: .text, pages: pages)
        }
    }

    /// What the router does for a tutor question once Cloud AI is out of reach, question by question: the iPhone model's tier as it ships.
    private static func pipeline(_ questions: [String], retriever: LocalRetriever, budget: OnDeviceBudget, name: String, choose: Bool, skipFreeForm: Bool) async -> [[String: Any]] {
        var rows: [[String: Any]] = []
        for question in questions {
            var row: [String: Any] = ["q": question]
            let started = Date()
            let retrieval = await MainActor.run { AIRouter.retrieve(retriever, messages: [TutorMessage(role: .user, text: question)], context: nil, limit: 4) }
            let terms = retriever.weightedTerms(retrieval.searchText)
            let local = LocalTutor.reply(question: question, mode: .explain, hits: retrieval.hits, context: nil, terms: terms,
                                         hasMaterial: !retriever.passages.isEmpty, topic: nil, limitReached: false, ranking: nil)
            row["asksAModel"] = local.asksAModel
            row["oldGrounded"] = local.grounded
            // This iPhone's model reads English only (the router's language gate).
            let modelMayRead = OnDeviceLanguageGate.verdict(for: question, supportsLocale: { SystemLanguageModel.default.supportsLocale($0) }).isSupported
            row["modelMayRead"] = modelMayRead
            var ranking = retriever.rankSentences(for: question)
            row["convincing"] = ranking.isConvincing
            if choose {
                row["rulesReplyBefore"] = LocalTutor.reply(question: question, mode: .explain, hits: retrieval.hits, context: nil, terms: terms,
                                                           hasMaterial: !retriever.passages.isEmpty, topic: nil, limitReached: false, ranking: ranking).text
                let shown = Array(ranking.candidates.prefix(OnDeviceWindow.pickAmong))
                if modelMayRead, ranking.isConvincing, shown.count >= 2 {
                    let start = Date()
                    let call = OnDevicePickCall(question: question, earlier: nil, sentences: shown.map(\.sentence))
                    let output = await OnDeviceRunner.run(call, on: FoundationModelsBackend(), budget: budget)
                    row["pickSeconds"] = Date().timeIntervalSince(start)
                    row["pick"] = output?.number ?? NSNull()
                    if let number = output?.number, (2...shown.count).contains(number) {
                        ranking.candidates.insert(ranking.candidates.remove(at: number - 1), at: 0)
                        ranking.alsoClose = nil
                    }
                }
            }
            row["rulesReply"] = LocalTutor.reply(question: question, mode: .explain, hits: retrieval.hits, context: nil, terms: terms,
                                                 hasMaterial: !retriever.passages.isEmpty, topic: nil, limitReached: false, ranking: ranking).text
            var answered = "rules"
            if !skipFreeForm, local.asksAModel, modelMayRead, local.grounded || ranking.isConvincing {
                var window = retrieval.hits.prefix(3).enumerated().map { n, hit in
                    TutorSource(id: "s\(n + 1)", title: hit.passage.title, label: hit.passage.label, text: hit.passage.text)
                }
                var closest: [String] = []
                if ranking.isConvincing {
                    let picked = OnDeviceWindow.passages(ranking: ranking, keyword: retrieval.hits.map(\.passage))
                    if !picked.isEmpty {
                        window = picked.enumerated().map { n, p in TutorSource(id: "s\(n + 1)", title: p.title, label: p.label, text: p.text) }
                        closest = OnDeviceWindow.closest(in: ranking)
                    }
                }
                let call = OnDeviceTutorCall(question: question, mode: .explain, passages: window, context: nil)
                let start = Date()
                let output = await OnDeviceRunner.run(call, on: FoundationModelsBackend(), budget: budget)
                row["tutorSeconds"] = Date().timeIntervalSince(start)
                if let output {
                    row["covered"] = output.covered
                    row["modelReply"] = output.reply
                    row["modelQuotes"] = output.quotes
                    if let accepted = OnDeviceTutoring.reply(from: output, passages: window, terms: terms, closest: closest) {
                        answered = "model"
                        row["acceptedReply"] = accepted.text
                        row["acceptedQuotes"] = accepted.quotes.map(\.quote)
                    }
                } else {
                    row["modelReply"] = NSNull()
                }
            }
            row["answeredBy"] = answered
            row["totalSeconds"] = Date().timeIntervalSince(started)
            rows.append(row)
            let progress = "\(name): question \(rows.count) of \(questions.count), \(ISO8601DateFormatter().string(from: Date()))"
            try? progress.write(to: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("offline_bench_progress.txt"),
                                atomically: true, encoding: .utf8)
        }
        return rows
    }

    /// One library: how long it takes to index and to answer, what it holds in memory, and what the model does with it.
    private static func measure(_ library: [String: Any], capability: OnDeviceCapability, sampler: PeakSampler) async -> [String: Any] {
        var out: [String: Any] = ["name": library["name"] as? String ?? "library"]
        let questions = library["questions"] as? [String] ?? []
        let notes = material(from: library)
        out["words"] = notes.reduce(0) { $0 + $1.pages.reduce(0) { $0 + $1.lines.reduce(0) { $0 + $1.text.split(separator: " ").count } } }
        OfflineSearch.reset()
        sampler.reset()
        out["footprintBeforeMB"] = footprintMB()
        var retriever: LocalRetriever!
        out["retrieverSeconds"] = seconds { retriever = LocalRetriever(material: notes) }
        out["passages"] = retriever.passages.count
        out["footprintAfterRetrieverMB"] = footprintMB()
        // The first search of a launch: the index of every sentence, the word vectors, the contextual model.
        let first = questions.first ?? "what is this about?"
        var firstRanking = OfflineRanking()
        out["firstQuestionSeconds"] = seconds { firstRanking = retriever.rankSentences(for: first) }
        out["firstQuestionStages"] = ["firstStage": firstRanking.stageSeconds.first, "reading": firstRanking.stageSeconds.reading]
        out["usedContextualModel"] = firstRanking.usedMeaning
        out["usedWordVectors"] = firstRanking.usedWordVectors
        out["footprintAfterFirstQuestionMB"] = footprintMB()
        out["peakAfterFirstQuestionMB"] = sampler.value
        // The rest, one after the other.
        var times: [Double] = []
        var rows: [[String: Any]] = []
        for question in questions {
            var ranking = OfflineRanking()
            let took = seconds { ranking = retriever.rankSentences(for: question) }
            times.append(took)
            var row: [String: Any] = ["q": question, "seconds": took, "convincing": ranking.isConvincing, "usedMeaning": ranking.usedMeaning,
                                      "top": ranking.candidates.prefix(3).map { String($0.sentence.prefix(120)) }]
            if let s = ranking.evidence.similarity { row["similarity"] = s }
            rows.append(row)
        }
        out["questions"] = rows
        out["warmQuestionMeanSeconds"] = times.isEmpty ? 0 : times.reduce(0, +) / Double(times.count)
        out["warmQuestionP90Seconds"] = percentile(times, 0.9)
        out["warmQuestionMaxSeconds"] = times.max() ?? 0
        out["footprintAfterQuestionsMB"] = footprintMB()
        out["peakFootprintMB"] = sampler.value
        out["thermal"] = thermal
        // The model: the answer from the three passages of the best sentences.
        guard capability.availability.isAvailable else { out["model"] = "not available: \(capability.availability)"; return out }
        let budget = OnDeviceBudget(contextSize: capability.contextSize)
        if library["pipeline"] as? Bool == true {
            out["pipeline"] = await pipeline(questions, retriever: retriever, budget: budget, name: out["name"] as? String ?? "library",
                                             choose: library["choose"] as? Bool == true, skipFreeForm: library["skipFreeForm"] as? Bool == true)
            out["footprintAfterPipelineMB"] = footprintMB()
            out["peakFootprintMB"] = sampler.value
            out["thermalAfterPipeline"] = thermal
            return out
        }
        var model: [[String: Any]] = []
        for question in questions.prefix(4) {
            var row: [String: Any] = ["q": question]
            let ranking = retriever.rankSentences(for: question)
            let window = OnDeviceWindow.passages(ranking: ranking, keyword: []).enumerated().map { n, p in
                TutorSource(id: "s\(n + 1)", title: p.title, label: p.label, text: p.text)
            }
            if !window.isEmpty {
                let call = OnDeviceTutorCall(question: question, mode: .explain, passages: window, context: nil)
                let start = Date()
                let reply = await OnDeviceRunner.run(call, on: FoundationModelsBackend(), budget: budget)
                row["tutorSeconds"] = Date().timeIntervalSince(start)
                if let reply {
                    row["covered"] = reply.covered
                    row["reply"] = String(reply.reply.prefix(200))
                    row["accepted"] = OnDeviceTutoring.reply(from: reply, passages: window, terms: retriever.weightedTerms(question),
                                                             closest: OnDeviceWindow.closest(in: ranking)) != nil
                } else {
                    row["reply"] = NSNull()
                }
            }
            model.append(row)
        }
        out["model"] = model
        out["footprintAfterModelMB"] = footprintMB()
        out["peakFootprintMB"] = sampler.value
        out["thermalAfterModel"] = thermal
        return out
    }
}
#endif
