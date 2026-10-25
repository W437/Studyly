import AVFoundation
import Foundation
import Speech

// The app's own lecture transcription (LectureFileTranscriber, TranscriptionGate, the flag detector) on this Mac's
// on-device speech model. Usage: speech <audio file>
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let gate = await TranscriptionGate.resolve(preferredLanguages: ["en-US"])
print("gate:", gate)
guard case .available(var choice) = gate else { exit(1) }
let terms = CommandLine.arguments.count > 2 ? CommandLine.arguments[2].split(separator: ",").map(String.init) : []
choice = await TranscriptionGate.preferringVocabulary(choice, vocabulary: terms)
print("engine:", choice.backend)
var t = Date()
do { try await LectureSpeechModels.install(choice); print("model ready in \(String(format: "%.1f", Date().timeIntervalSince(t))) s") }
catch { print("install failed:", error); exit(2) }
t = Date()
do {
    let vocabulary = CommandLine.arguments.count > 2 ? CommandLine.arguments[2].split(separator: ",").map(String.init) : []
    print("vocabulary: \(vocabulary.count) terms")
    let segments = try await LectureFileTranscriber.transcribe(url, choice: choice, vocabulary: vocabulary)
    print("transcribed in \(String(format: "%.1f", Date().timeIntervalSince(t))) s · \(segments.count) segments")
    for s in segments { print(String(format: "  [%6.2f–%6.2f] ", s.start, s.end) + s.text) }
    let flags = ExamFlagDetector.phraseFlags(in: segments)
    print("exam flags:", flags.map { "\(String(format: "%.1f", $0.time)) s: \($0.text)" })
} catch { print("transcription failed:", error); exit(3) }
