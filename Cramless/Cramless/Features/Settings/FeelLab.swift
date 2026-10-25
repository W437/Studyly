#if DEBUG
import SwiftUI

/// Settings ▸ Debug ▸ Feel lab (DEBUG builds only), for auditioning on a phone (haptics can only be felt there) and
/// for films:
/// - Sounds: every cue's sound and haptic on each palette, and a 30-second session.
/// - Cap: each moment's pose and motion, with its sound.
/// - Cast: every pose with its clip, one after another, and how long each took to reach the screen. Tap Cap, or a pose's
///   "Tap" button, to see his reaction, squish and words for that pose.
/// - Celebrations: each size of celebration, as a session's summary plays it.
///
/// Harness: `CRAMLESS_FEELLAB=sounds|cap|cast|confetti` opens that section and plays everything in it in turn. The harness
/// is silent unless `CRAMLESS_SOUNDS=1`, and Cap stays a still unless `CRAMLESS_CAP_CLIPS=1`; `scripts/film.sh` scores the
/// film from the cue log. `CRAMLESS_SOUND_PALETTE=marimba|kalimba|glass` picks the palette. With `CRAMLESS_CAST_POKE=1` the
/// cast taps each pose after its clip (and `CRAMLESS_CAP_SEED=n` makes the rolls repeat).
struct FeelLab: View {
    enum Section: String, CaseIterable {
        case sounds, cap, cast, confetti
    }

    /// A moment of Cap's, as the lab plays it.
    struct CapDemo {
        var name: String
        var moment: CapMoment
        var cues: [CLCue]
    }

    @Environment(AppModel.self) private var app
    @State private var section = Section(rawValue: TestHarness.value("CRAMLESS_FEELLAB") ?? "") ?? .sounds
    @State private var paletteID = CLSound.shared.palette.id
    @State private var playing: String?
    @State private var run: Task<Void, Never>?
    @State private var capDemo = 0
    @State private var capPlays = 0
    @State private var castIndex = 0
    @State private var castPlays = 0
    @State private var castPokes = 0
    @State private var celebration: Celebration?
    @State private var fires = 0

    static let capDemos: [CapDemo] = [
        CapDemo(name: "Nice!", moment: .nice, cues: [.right(combo: 1)]),
        CapDemo(name: "Almost.", moment: .almost, cues: [.almost]),
        CapDemo(name: "Not yet.", moment: .notYet, cues: [.notYet]),
        CapDemo(name: "Here's the answer.", moment: .answerShown, cues: [.revealed]),
        CapDemo(name: "Five in a row", moment: .runMilestone, cues: [.right(combo: 5), .flourish]),
        CapDemo(name: "Saved it.", moment: .saved, cues: [.saved]),
        CapDemo(name: "Checking…", moment: .working, cues: []),
        CapDemo(name: "Session done", moment: .finished, cues: [.done]),
        CapDemo(name: "Milestone", moment: .milestone, cues: []),
        CapDemo(name: "Streak at risk", moment: .streakAtRisk, cues: []),
        CapDemo(name: "Goodnight", moment: .goodnight, cues: [.goodnight]),
    ]

    var body: some View {
        SettingsScroll(title: "Feel lab") {
            Picker("Section", selection: $section) {
                Text(verbatim: "Sounds").tag(Section.sounds)
                Text(verbatim: "Cap").tag(Section.cap)
                Text(verbatim: "Cast").tag(Section.cast)
                Text(verbatim: "Celebrations").tag(Section.confetti)
            }
            .pickerStyle(.segmented)
            .padding(.top, 14)
            .onChange(of: section) { run?.cancel() }

            switch section {
            case .sounds: sounds
            case .cap: cap
            case .cast: cast
            case .confetti: celebrations
            }
        }
        .overlay {
            if let burst = celebration.flatMap(Self.burst) {
                CLConfetti(burst: burst, seed: 7, trigger: fires)
                    .ignoresSafeArea()
            }
        }
        .task {
            CLFeel.prepare()
            guard let asked = TestHarness.value("CRAMLESS_FEELLAB").flatMap(Section.init(rawValue:)) else { return }
            try? await nap(1200)
            switch asked {
            case .sounds: await playEveryCue()
            case .cap: await playEveryMoment()
            case .cast: await playEveryPose()
            case .confetti: await playEveryCelebration()
            }
        }
        .onDisappear { run?.cancel() }
    }

    // MARK: Sounds

    @ViewBuilder private var sounds: some View {
        Picker("Palette", selection: $paletteID) {
            ForEach(CLSynth.Palette.all) { Text($0.name).tag($0.id) }
        }
        .pickerStyle(.segmented)
        .padding(.top, 14)
        .onChange(of: paletteID) { _, id in
            CLSound.shared.palette = .named(id) ?? .standard
            CLFeel.prepare()
        }

        nowPlaying

        SettingsGroup(title: "A session", footer: "Sounds follow Settings ▸ Accessibility ▸ Sounds and the Silent switch.") {
            SettingsActionRow(icon: "play.fill", tint: .mint, title: "Play a 30-second session",
                              subtitle: "A run climbing, an almost, five in a row, a miss, a save, the finish") {
                start { await playSession() }
            }
        }

        SettingsGroup(title: "Every cue") {
            ForEach(CLCue.all, id: \.key) { cue in
                Button {
                    start { await play(cue) }
                } label: {
                    row(icon: playing == cue.key ? "speaker.wave.2.fill" : "music.note", title: Self.title(cue),
                        detail: cue.key, active: playing == cue.key)
                }
                .buttonStyle(.pressable)
            }
        }
    }

    /// What's sounding now, large enough to read in a film (the list below doesn't scroll to it).
    private var nowPlaying: some View {
        let cue = playing.flatMap(CLCue.init(key:))
        return HStack(spacing: 14) {
            Image(systemName: cue == nil ? "waveform" : "speaker.wave.2.fill")
                .font(.title2)
                .foregroundStyle(cue == nil ? CLColor.ink4 : CLColor.mintInk)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 3) {
                // Text switches at once: a cross-fade would catch two names in every frame of a film.
                Text(verbatim: cue.map(Self.title) ?? "Tap a cue to hear it")
                    .clFont(.title3)
                    .foregroundStyle(cue == nil ? CLColor.ink3 : CLColor.ink)
                    .contentTransition(.identity)
                Text(verbatim: cue.map { "\($0.key) · \(CLSound.shared.palette.name)" } ?? "Sound and haptic together")
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(CLColor.ink3)
                    .contentTransition(.identity)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cue == nil ? CLColor.surface : CLColor.mintSoft, in: RoundedRectangle(cornerRadius: CLRadius.card))
        .animation(CLMotion.snap, value: playing)
        .padding(.top, 14)
    }

    private func playEveryCue() async {
        for cue in CLCue.all {
            guard !Task.isCancelled else { return }
            await play(cue)
            try? await nap(Self.gap(after: cue))
        }
        try? await nap(800)
        await playSession()
    }

    /// Plays a cue and waits for it to ring out. The card keeps showing it until the next one.
    private func play(_ cue: CLCue) async {
        playing = cue.key
        CLFeel.play(cue)
        try? await nap(Int(Self.length(of: cue) * 1000))
    }

    private func playSession() async {
        var elapsed = 0.0
        for event in CLSynth.sampleSession {
            try? await nap(Int((event.time - elapsed) * 1000))
            guard !Task.isCancelled else { return }
            elapsed = event.time
            playing = event.cue.key
            CLFeel.play(event.cue)
        }
    }

    // MARK: Cap

    @ViewBuilder private var cap: some View {
        let demo = Self.capDemos[capDemo]
        stage(title: demo.name, detail: Self.detail(demo.moment)) {
            CapView(demo.moment, size: 190, trigger: capPlays)
        }

        SettingsGroup(title: .verbatim("Moments"),
                      footer: .verbatim("Poses still to draw show a drawn one for now; the line under the name says which.")) {
            ForEach(Self.capDemos.indices, id: \.self) { index in
                let item = Self.capDemos[index]
                Button {
                    start { await playMoment(index) }
                } label: {
                    row(icon: index == capDemo ? "figure.wave" : "circle", title: item.name,
                        detail: Self.detail(item.moment), active: index == capDemo)
                }
                .buttonStyle(.pressable)
            }
        }
    }

    private func playEveryMoment() async {
        for index in Self.capDemos.indices {
            guard !Task.isCancelled else { return }
            await playMoment(index)
            let moment = Self.capDemos[index].moment
            try? await nap(moment.idle != nil ? 2600 : moment.sparkles ? 1700 : 1400)
        }
    }

    private func playMoment(_ index: Int) async {
        capDemo = index
        capPlays += 1
        CLFeel.play(Self.capDemos[index].cues)
        try? await nap(100)
    }

    /// "nice (celebrate until drawn) · hop · sparkles".
    private static func detail(_ moment: CapMoment) -> String {
        let pose = moment.pose.shown == moment.pose ? moment.pose.rawValue
            : "\(moment.pose.rawValue) (\(moment.pose.shown.rawValue) until drawn)"
        var parts = [pose]
        if let motion = moment.motion { parts.append(motion.rawValue) }
        if moment.sparkles { parts.append("sparkles") }
        if let idle = moment.idle { parts.append(idle == .doze ? "dozing" : "breathing") }
        return parts.joined(separator: " · ")
    }

    // MARK: Cast

    /// Each pose, large, as it plays its clip: a reaction plays once as he appears, a waiting pose loops.
    @ViewBuilder private var cast: some View {
        let pose = CapPose.allCases[castIndex]
        let clip = CapClipCatalog.shared.clip(for: pose)
        stage(title: pose.rawValue, detail: Self.detail(pose: pose, clip: clip)) {
            CapView(pose: pose, size: 190, idle: clip?.role == .idle ? .breathe : nil, trigger: castPlays, poke: castPokes)
        }

        SettingsGroup(title: .verbatim("Every pose"),
                      footer: .verbatim("A clip starts and ends on its pose's drawing, so changing pose is a cross-fade between drawings.")) {
            ForEach(CapPose.allCases.indices, id: \.self) { index in
                let item = CapPose.allCases[index]
                Button {
                    start { await playPose(index) }
                } label: {
                    row(icon: index == castIndex ? "figure.wave" : "circle", title: item.rawValue,
                        detail: Self.detail(pose: item, clip: CapClipCatalog.shared.clip(for: item)), active: index == castIndex)
                }
                .buttonStyle(.pressable)
            }
        }
    }

    private func playEveryPose() async {
        for index in CapPose.allCases.indices {
            guard !Task.isCancelled else { return }
            await playPose(index)
            let pose = CapPose.allCases[index]
            let clip = CapClipCatalog.shared.clip(for: pose)
            try? await nap(Int(((clip?.duration ?? 2) + (clip?.role == .idle ? 0.6 : 1.0)) * 1000))
            if TestHarness.value("CRAMLESS_CAST_POKE") == "1" {
                // Tap him: his reaction, the squish and his words, then a moment to read them.
                castPokes += 1
                try? await nap(Int(((CapClipCatalog.shared.poke(for: pose)?.duration ?? 1.2) + 1.5) * 1000))
            }
        }
    }

    private func playPose(_ index: Int) async {
        castIndex = index
        castPlays += 1
        try? await nap(100)
    }

    /// "performance · 5.0 s · 1.7 MB · first frame in 41 ms".
    private static func detail(pose: CapPose, clip: CapClip?) -> String {
        guard let clip else { return "no clip: a drawing" }
        var parts = [clip.role.rawValue, String(format: "%.1f s", clip.duration),
                     String(format: "%.1f MB", Double(clip.bytes) / 1_048_576)]
        if let poke = CapClipCatalog.shared.poke(for: pose) { parts.append(String(format: "tap clip %.1f s", poke.duration)) }
        if let latency = CapClipPlayer.latencies[clip.id] { parts.append(String(format: "first frame in %.0f ms", latency * 1000)) }
        return parts.joined(separator: " · ")
    }

    // MARK: Celebrations

    @ViewBuilder private var celebrations: some View {
        let size = celebration ?? .none
        stage(title: celebration.map { $0.rawValue.capitalized } ?? "Tap a size", detail: Self.detail(for: size)) {
            CapView(Self.moment(for: size), size: 190, trigger: fires)
        }

        SettingsGroup(title: .verbatim("Sizes"),
                      footer: .verbatim("A summary picks one (CelebrationPolicy). Exam eve and quiet hours are calm, and a big one plays at most once a day.")) {
            ForEach([Celebration.nudge, .small, .medium, .big, .calm], id: \.self) { size in
                Button {
                    start { await celebrate(size) }
                } label: {
                    row(icon: size == celebration ? "sparkles" : "circle", title: size.rawValue.capitalized,
                        detail: Self.detail(for: size), active: size == celebration)
                }
                .buttonStyle(.pressable)
            }
        }
    }

    private func playEveryCelebration() async {
        for size in [Celebration.small, .medium, .big, .calm, .nudge] {
            guard !Task.isCancelled else { return }
            await celebrate(size)
            try? await nap(size == .big ? 4200 : size.hasConfetti ? 3300 : 2000)
        }
    }

    private func celebrate(_ size: Celebration) async {
        celebration = size
        fires += 1
        try? await nap(100)
    }

    /// Cap in a summary's celebration of `size` (the summary's own mapping).
    private static func moment(for size: Celebration) -> CapMoment {
        switch size {
        case .none: CapMoment(pose: .celebrate)
        case .calm: CapMoment(pose: .celebrate, sparkles: true)
        case .nudge, .small: CapMoment(pose: .celebrate, motion: .hop)
        case .medium, .big: CapMoment(pose: .celebrate, motion: .hop, sparkles: true)
        }
    }

    private static func burst(_ size: Celebration) -> ConfettiField.Burst? {
        switch size {
        case .small: .puff(CGPoint(x: 0.5, y: 0.24))
        case .medium: .burst(CGPoint(x: 0.5, y: 0.22))
        case .big: .cannons
        case .none, .nudge, .calm: nil
        }
    }

    private static func detail(for size: Celebration) -> String {
        switch size {
        case .none: "Nothing yet"
        case .nudge: "Cap hops as the streak rolls over"
        case .small: "A puff of confetti, Cap hops: a perfect session, 3 days"
        case .medium: "A burst and sparkles: 7 days, a goal reached, a mix-up fixed"
        case .big: "Both corners, once a day at most: the first session, 30 days"
        case .calm: "No confetti: exam eve and quiet hours"
        }
    }

    // MARK: Parts

    /// The big card at the top: what's playing, large enough to read in a film.
    private func stage<Content: View>(title: String, detail: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 10) {
            content()
                .frame(height: 210)
            Text(verbatim: title)
                .clFont(.title2)
                .foregroundStyle(CLColor.ink)
                .contentTransition(.identity)
            Text(verbatim: detail)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(CLColor.ink3)
                .multilineTextAlignment(.center)
                .contentTransition(.identity)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(CLColor.surface, in: RoundedRectangle(cornerRadius: CLRadius.card))
        .padding(.top, 14)
    }

    private func row(icon: String, title: String, detail: String, active: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(active ? CLColor.mintInk : CLColor.ink3)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title).clFont(.bodyEmphasis).foregroundStyle(CLColor.ink)
                Text(verbatim: detail).font(.system(.footnote, design: .monospaced)).foregroundStyle(CLColor.ink3)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(minHeight: CLMetrics.minHitTarget)
        .background(active ? CLColor.mintSoft : .clear)
        .animation(CLMotion.snap, value: active)
        .contentShape(Rectangle())
    }

    private func start(_ work: @escaping @MainActor () async -> Void) {
        run?.cancel()
        run = Task { await work() }
    }

    private static func length(of cue: CLCue) -> Double {
        let score = CLSynth.score(for: cue)
        return min(1.2, (score.notes.map(\.time).max() ?? 0) + 0.5)
    }

    private static func gap(after cue: CLCue) -> Int {
        switch cue {
        case .right, .cardOut, .flip, .rated: 250
        default: 500
        }
    }

    static func title(_ cue: CLCue) -> String {
        switch cue {
        case .right(let combo): combo == 1 ? "Right" : "Right, \(combo) in a row"
        case .almost: "Almost"
        case .notYet: "Not yet"
        case .revealed: "Here's the answer"
        case .flip: "Card flips"
        case .rated: "Card rated"
        case .saved: "Saved it"
        case .flourish: "Five in a row"
        case .done: "Session done"
        case .cardOut(let n): "Card \(n + 1) leaves the page"
        case .listenOn: "Cap starts listening"
        case .listenOff: "Cap stops listening"
        case .goodnight: "Goodnight"
        }
    }
}
#endif
