import Foundation

// scripts/sound_audition/run.sh compiles this with the app's CLSynth.swift.
//
//   sound_audition <folder>                                  every cue on every palette, under <folder>:
//                                                              <palette>/<cue>.wav, <palette>-session.wav, cues.json
//   sound_audition score <palette> <events.json> <out.wav>   a film's soundtrack: [{"t": seconds, "cue": key}]

let args = CommandLine.arguments
let fm = FileManager.default

if args.count == 5, args[1] == "score" {
    guard let palette = CLSynth.Palette.named(args[2]) else {
        FileHandle.standardError.write(Data("unknown palette \(args[2])\n".utf8))
        exit(2)
    }
    let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: args[3]))) as? [[String: Any]] ?? []
    let events: [(time: Double, cue: CLCue)] = raw.compactMap { entry in
        guard let t = entry["t"] as? Double, t >= 0, let key = entry["cue"] as? String, let cue = CLCue(key: key) else { return nil }
        return (t, cue)
    }
    let samples = CLSynth(palette: palette).mix(events)
    try CLSynth.wav(samples.isEmpty ? [0] : samples).write(to: URL(fileURLWithPath: args[4]))
    print("scored \(events.count) cues")
    exit(0)
}

let root = URL(fileURLWithPath: args.count > 1 ? args[1] : "docs/shots/audition")
try fm.createDirectory(at: root, withIntermediateDirectories: true)

for palette in CLSynth.Palette.all {
    let synth = CLSynth(palette: palette)
    let folder = root.appendingPathComponent(palette.id)
    try fm.createDirectory(at: folder, withIntermediateDirectories: true)
    for cue in CLCue.all {
        try CLSynth.wav(synth.render(cue)).write(to: folder.appendingPathComponent("\(cue.key).wav"))
    }
    let session = synth.mix(CLSynth.sampleSession)
    try CLSynth.wav(session).write(to: root.appendingPathComponent("\(palette.id)-session.wav"))
    print("\(palette.name): \(CLCue.all.count) cues, session \(String(format: "%.1f", Double(session.count) / CLSynth.sampleRate)) s")
}

try JSONSerialization.data(withJSONObject: ["palettes": CLSynth.Palette.all.map { ["id": $0.id, "name": $0.name] },
                                            "cues": CLCue.all.map(\.key)], options: [.prettyPrinted, .sortedKeys])
    .write(to: root.appendingPathComponent("cues.json"))
print("Wrote \(root.path)")
