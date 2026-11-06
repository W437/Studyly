import SwiftUI

/// Cap the capybara. Calm, never guilt-tripping, always in the graduation cap.
///
/// Four poses are drawn today. The rest are art still to render (`../docs/rethink/brand/`); until a pose is drawn
/// it shows its `fallback`, so a moment can name the pose it means now and pick up the art when it lands.
enum CapPose: String, CaseIterable, Codable, Sendable {
    case wave, study, celebrate, sleep
    /// Working and making: thinking it over, pointing at the answer, scanning, planning, at the microphone, resting.
    case think, point, scan, plan, mic, relax
    /// Answer reactions. "Not yet" is kind, never sad.
    case nice, almost, notYet
    /// Teach Cap: listening with a notepad, asking a follow-up.
    case listen, ask
    /// Streaks and milestones.
    case sleepy, proud
    /// Night: under the sky with a telescope, tucking the sky in.
    case stargaze, tuckIn

    /// The poses with art in the asset catalog (`Cap-<rawValue>`). Art goes in together with its name here;
    /// `CapPoseTests` checks both ways.
    static let drawn: Set<CapPose> = [
        .wave, .study, .celebrate, .sleep,
        .think, .point, .scan, .plan, .mic, .relax,
        .nice, .almost, .notYet,
        .listen, .ask,
        .sleepy, .proud,
        .stargaze, .tuckIn,
    ]

    /// The drawn pose that stands in until this one has art.
    var fallback: CapPose {
        switch self {
        case .wave, .study, .celebrate, .sleep: self
        case .think, .point, .scan, .plan, .mic, .listen, .ask, .almost, .notYet: .study
        case .nice, .proud: .celebrate
        case .relax, .stargaze: .wave
        case .sleepy, .tuckIn: .sleep
        }
    }

    /// The pose on screen: this one when it's drawn, else its fallback.
    var shown: CapPose { Self.drawn.contains(self) ? self : fallback }

    var assetName: String { "Cap-\(shown.rawValue)" }

    /// What VoiceOver says: the drawing on screen. A new pose's words come with its art.
    var accessibilityDescription: LocalizedStringResource {
        switch shown {
        case .wave: "Cap the capybara waving hello"
        case .study: "Cap the capybara reading index cards"
        case .celebrate: "Cap the capybara celebrating"
        case .sleep: "Cap the capybara asleep on a pile of index cards"
        case .think: "Cap the capybara thinking it over"
        case .point: "Cap the capybara pointing at an index card"
        case .scan: "Cap the capybara photographing a page of a book"
        case .plan: "Cap the capybara holding a study calendar"
        case .mic: "Cap the capybara holding a microphone"
        case .relax: "Cap the capybara relaxing in a beanbag with a hot drink"
        case .nice: "Cap the capybara cheering with a small fist pump"
        case .almost: "Cap the capybara holding up a paw: nearly there"
        case .notYet: "Cap the capybara reading a book, patiently"
        case .listen: "Cap the capybara listening, pencil and notepad in paw"
        case .ask: "Cap the capybara raising a paw to ask a question"
        case .sleepy: "Cap the capybara yawning"
        case .proud: "Cap the capybara standing proud with a gold star on its chest"
        case .stargaze: "Cap the capybara looking at the stars through a telescope"
        case .tuckIn: "Cap the capybara tucking a starry blanket over a pile of index cards"
        }
    }
}

/// Cap's motion tokens: each plays once when its moment arrives. Under Reduce Motion none of them run, and a change
/// of pose is only a cross-fade. The curves are plain functions of time (`frame(at:)`), so they're tested like the
/// engines.
enum CapMotion: String, CaseIterable, Sendable {
    /// Squash, stretch up, land and settle: a right answer.
    case hop
    /// A wobble from the feet: almost.
    case wiggle
    /// Two small, kind dips: not yet, and listening.
    case nod
    /// Rising from the feet with a little overshoot: the end of a session.
    case arrive

    var duration: Double {
        switch self {
        case .hop: 0.62
        case .wiggle: 0.66
        case .nod: 0.8
        case .arrive: 0.6
        }
    }

    /// Cap's transform `seconds` into the motion. Scales and the tilt pivot on Cap's feet; `lift` is a fraction of
    /// Cap's size. Every motion ends where it started, at rest.
    func frame(at seconds: Double) -> CapFrame {
        guard seconds < duration else { return CapFrame() }
        let t = max(0, seconds)
        var frame = CapFrame()
        switch self {
        case .hop:
            frame.lift = Self.hopLift.value(at: t)
            frame.scaleY = Self.hopScaleY.value(at: t)
            frame.scaleX = Self.hopScaleX.value(at: t)
        case .wiggle:
            frame.tilt = Self.wiggleTilt.value(at: t)
        case .nod:
            frame.lift = Self.nodLift.value(at: t)
            frame.scaleY = Self.nodScaleY.value(at: t)
            frame.tilt = Self.nodTilt.value(at: t)
        case .arrive:
            frame.grow = Self.arriveGrow.value(at: t)
            frame.opacity = Self.arriveOpacity.value(at: t)
            frame.lift = Self.arriveLift.value(at: t)
        }
        return frame
    }

    /// How long a moment's motion runs, with its sparkles.
    static func length(_ motion: CapMotion?, sparkles: Bool) -> Double {
        max(motion?.duration ?? 0, sparkles ? CapSparkles.duration : 0)
    }

    private static let hopLift = MotionCurve([(0, 0, .linear), (0.07, 0, .linear), (0.24, 0.17, .out),
                                              (0.40, 0, .in), (0.62, 0, .linear)])
    private static let hopScaleY = MotionCurve([(0, 1, .linear), (0.07, 0.9, .out), (0.15, 1.08, .out),
                                                (0.30, 1, .inOut), (0.40, 1, .linear), (0.45, 0.92, .out),
                                                (0.54, 1.03, .inOut), (0.62, 1, .inOut)])
    private static let hopScaleX = MotionCurve([(0, 1, .linear), (0.07, 1.07, .out), (0.15, 0.95, .out),
                                                (0.30, 1, .inOut), (0.40, 1, .linear), (0.45, 1.06, .out),
                                                (0.54, 0.98, .inOut), (0.62, 1, .inOut)])
    private static let wiggleTilt = MotionCurve([(0, 0, .linear), (0.09, -7, .out), (0.23, 6, .inOut),
                                                 (0.37, -4, .inOut), (0.50, 2, .inOut), (0.66, 0, .inOut)])
    private static let nodLift = MotionCurve([(0, 0, .linear), (0.14, -0.03, .inOut), (0.30, 0, .inOut),
                                              (0.44, -0.024, .inOut), (0.62, 0, .inOut), (0.8, 0, .linear)])
    private static let nodScaleY = MotionCurve([(0, 1, .linear), (0.14, 0.965, .inOut), (0.30, 1, .inOut),
                                                (0.44, 0.972, .inOut), (0.62, 1, .inOut), (0.8, 1, .linear)])
    private static let nodTilt = MotionCurve([(0, 0, .linear), (0.14, 2.5, .inOut), (0.30, 0, .inOut),
                                              (0.44, 2, .inOut), (0.62, 0, .inOut), (0.8, 0, .linear)])
    private static let arriveGrow = MotionCurve([(0, 0.6, .linear), (0.32, 1.05, .out), (0.46, 0.98, .inOut),
                                                 (0.6, 1, .inOut)])
    private static let arriveOpacity = MotionCurve([(0, 0, .linear), (0.16, 1, .out), (0.6, 1, .linear)])
    private static let arriveLift = MotionCurve([(0, -0.04, .linear), (0.32, 0, .out), (0.6, 0, .linear)])
}

/// How Cap waits: breathing, or dozing with z's drifting up. Loops, so off under Reduce Motion.
enum CapIdle: Sendable {
    case breathe, doze
}

/// One frame of a Cap motion. At rest every value is neutral.
struct CapFrame: Equatable, Sendable {
    var lift: Double = 0
    /// Sideways, as a fraction of Cap's size (a tap's shimmy).
    var sway: Double = 0
    var scaleX: Double = 1
    var scaleY: Double = 1
    var grow: Double = 1
    var tilt: Double = 0
    var opacity: Double = 1
}

/// A value over time: keys joined by eased segments (each key's ease shapes the segment arriving at it).
struct MotionCurve: Sendable {
    enum Ease: Sendable {
        case linear, `in`, out, inOut

        func apply(_ x: Double) -> Double {
            switch self {
            case .linear: x
            case .in: x * x * x
            case .out: 1 - pow(1 - x, 3)
            case .inOut: x * x * (3 - 2 * x)
            }
        }
    }

    struct Key: Sendable {
        var time: Double
        var value: Double
        var ease: Ease
    }

    let keys: [Key]

    init(_ keys: [(Double, Double, Ease)]) {
        self.keys = keys.map { Key(time: $0.0, value: $0.1, ease: $0.2) }
    }

    func value(at t: Double) -> Double {
        guard let first = keys.first, let last = keys.last else { return 0 }
        if t <= first.time { return first.value }
        for (a, b) in zip(keys, keys.dropFirst()) where t <= b.time {
            let x = (t - a.time) / max(b.time - a.time, 1e-9)
            return a.value + (b.value - a.value) * b.ease.apply(x)
        }
        return last.value
    }
}

/// What Cap does at a moment: the pose it means, the motion that plays when the moment arrives, sparkles, and how
/// it waits. `docs/design.md` ▸ Cap has the table.
extension EnvironmentValues {
    /// Cap's bubble sits beside him rather than over his head, for a place too short for words above him.
    @Entry var capSpeaksBeside = false
}

/// A line a screen has Cap say at a moment it chose: `id` rises with each new one, so the same words can be said twice.
struct CapScriptedLine: Equatable, Sendable {
    var id: Int
    var text: LocalizedStringResource

    static func == (a: CapScriptedLine, b: CapScriptedLine) -> Bool { a.id == b.id }
}

struct CapMoment: Equatable, Sendable {
    var pose: CapPose
    var motion: CapMotion?
    var sparkles = false
    var idle: CapIdle?

    /// "Nice!": a right answer.
    static let nice = CapMoment(pose: .nice, motion: .hop)
    /// Five, ten, fifteen right in a row.
    static let runMilestone = CapMoment(pose: .celebrate, motion: .hop, sparkles: true)
    /// A right answer that rescued a fading memory.
    static let saved = CapMoment(pose: .nice, motion: .hop, sparkles: true)
    static let almost = CapMoment(pose: .almost, motion: .wiggle)
    static let notYet = CapMoment(pose: .notYet, motion: .nod)
    /// "I don't know": Cap shows the answer.
    static let answerShown = CapMoment(pose: .point)
    /// The AI is checking or making something.
    static let working = CapMoment(pose: .think, idle: .breathe)
    static let milestone = CapMoment(pose: .proud, sparkles: true)
    static let streakAtRisk = CapMoment(pose: .sleepy, idle: .doze)
    /// A session's end.
    static let finished = CapMoment(pose: .celebrate, motion: .arrive)
    /// Exam eve's end: asleep.
    static let goodnight = CapMoment(pose: .sleep, motion: .arrive, idle: .doze)

    // Today's hero, still and waiting.

    /// At his telescope on the horizon, watching your sky.
    static let watchingTheSky = CapMoment(pose: .stargaze, idle: .breathe)
    /// Nothing due: taking it easy with a hot drink.
    static let relaxed = CapMoment(pose: .relax, idle: .breathe)
    /// The day's work done: hands on hips, pleased.
    static let pleased = CapMoment(pose: .proud, idle: .breathe)
    /// Exam eve with nothing more to do: dozing under the sky.
    static let asleep = CapMoment(pose: .sleep, idle: .doze)
}

struct CapView: View {
    var pose: CapPose
    var size: CGFloat = 140
    /// Plays once when Cap appears, and again whenever the pose, the motion or `trigger` changes.
    var motion: CapMotion? = nil
    /// Stars bursting around Cap's head, with the motion.
    var sparkles = false
    var idle: CapIdle? = nil
    /// Bump to play the motion again with nothing else changing.
    var trigger = 0
    /// Decorative uses (Cap beside text that already says everything) hide it from VoiceOver.
    var decorative = true
    /// A tap squishes him, plays his reaction to it and has him say something. Off where a tap already means something.
    var interactive = true
    /// Bump to tap him from code (the Feel lab and the films).
    var poke = 0
    /// Bump when the sky he stands in has just been refreshed: he reacts like a tap, and says one of his refreshed lines.
    var refreshed = 0
    /// A line a screen has him say at a moment it chose (the welcome's), in his bubble, like the ones a tap draws from his pools.
    var says: CapScriptedLine? = nil

    @State private var plays = 0
    @State private var up = false
    @State private var stage = CapStage()
    /// False while a scroll view has him out of sight: nothing plays that nobody can see.
    @State private var inSight = true
    @State private var lastPose: CapPose?
    // Being tapped: every tap squishes him (`taps`); his reaction clip starts only when the last one has finished (`clipTaps`),
    // so a run of taps never cuts it off.
    @State private var taps = 0
    @State private var clipTaps = 0
    @State private var playedClipTaps = 0
    @State private var squish: CapPoke?
    @State private var line: CapLine?
    @State private var lastTapAt: Date?
    /// Until when his reaction clip is playing: a tap before then only squashes him and has him talk.
    @State private var clipBusyUntil = Date.distantPast
    @State private var run = 0
    /// Where he and his bubble are, while he is talking, so the bubble can stay on screen.
    @State private var capMidX: CGFloat = 0
    @State private var bubbleSize: CGSize = .zero
    @Environment(\.capSpeaksBeside) private var speaksBeside
    @Environment(\.clReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    init(pose: CapPose, size: CGFloat = 140, motion: CapMotion? = nil, sparkles: Bool = false, idle: CapIdle? = nil,
         trigger: Int = 0, decorative: Bool = true, interactive: Bool = true, poke: Int = 0, refreshed: Int = 0,
         says: CapScriptedLine? = nil) {
        self.pose = pose
        self.size = size
        self.motion = motion
        self.sparkles = sparkles
        self.idle = idle
        self.trigger = trigger
        self.decorative = decorative
        self.interactive = interactive
        self.poke = poke
        self.refreshed = refreshed
        self.says = says
    }

    init(_ moment: CapMoment, size: CGFloat = 140, trigger: Int = 0, decorative: Bool = true, interactive: Bool = true, poke: Int = 0,
         refreshed: Int = 0, says: CapScriptedLine? = nil) {
        self.init(pose: moment.pose, size: size, motion: moment.motion, sparkles: moment.sparkles, idle: moment.idle,
                  trigger: trigger, decorative: decorative, interactive: interactive, poke: poke, refreshed: refreshed, says: says)
    }

    /// Past the end of every motion: the frame at rest.
    private static let rest = 1_000.0

    /// What Cap does here and now: his clips when he has them and they may play, else the code's motions.
    private var script: CapScript {
        CapScript.make(pose: pose, motion: motion, sparkles: sparkles, idle: idle,
                       policy: CapPlayback.shared.policy(reduceMotion: reduceMotion))
    }

    var body: some View {
        let script = script
        let length = CapMotion.length(script.motion, sparkles: script.sparkles)
        let squishLength = squish?.duration ?? 0
        // The code bobs Cap only when no clip breathes for him.
        let bobs = idle != nil && !script.hasClip && !reduceMotion
        art(script)
            .offset(y: up ? -size * (idle == .doze ? 0.012 : 0.02) : 0)
            .scaleEffect(up ? (idle == .doze ? 1.008 : 1.012) : 1, anchor: .bottom)
            .keyframeAnimator(initialValue: Self.rest, trigger: plays) { content, seconds in
                content.modifier(CapMotionEffect(motion: script.motion, sparkles: script.sparkles, seconds: seconds, size: size))
            } keyframes: { _ in
                MoveKeyframe(0.0)
                LinearKeyframe(length, duration: length)
                MoveKeyframe(Self.rest)
            }
            // A tap's squash and rock, over whatever else he is doing.
            .keyframeAnimator(initialValue: Self.rest, trigger: taps) { content, seconds in
                content.modifier(CapPokeEffect(poke: squish, seconds: seconds, size: size))
            } keyframes: { _ in
                MoveKeyframe(0.0)
                LinearKeyframe(squishLength, duration: max(squishLength, 0.001))
                MoveKeyframe(Self.rest)
            }
            .overlay {
                if script.dozes, !reduceMotion { DozeZs(size: size) }
            }
            // His bubble sits outside the squash, so the words don't squish with him.
            .overlay(alignment: .top) { speech }
            .overlay {
                if line != nil {
                    Color.clear.onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).midX } action: { capMidX = $0 }
                }
            }
            .contentShape(.interaction, Ellipse())
            .gesture(TapGesture().onEnded { touch() }, including: interactive ? .all : .subviews)
            .accessibilityHidden(decorative)
            .accessibilityLabel(Text(pose.accessibilityDescription))
            .accessibilityAction(named: Text("Say hi to Cap")) { touch() }
            .onAppear {
                play(script)
                if interactive, script.poke != nil { CapClipLibrary.prewarmPoke(for: pose.shown) }
            }
            .onChange(of: "\(pose.rawValue) \(script.motion?.rawValue ?? "-") \(script.sparkles)") { play(script) }
            .onChange(of: trigger) { play(script) }
            .onChange(of: poke) { touch() }
            .onChange(of: refreshed) { touch(says: .refreshed) }
            .onChange(of: says?.id) { if let says { say(CapLine(pool: "script", index: says.id, text: says.text)) } }
            .onChange(of: pose) {
                hideLine()
                if interactive { CapClipLibrary.prewarmPoke(for: pose.shown) }
            }
            .onChange(of: inSight) { if !inSight { hideLine() } }
            .task(id: bobs ? idle : nil) {
                guard let idle = bobs ? idle : nil else {
                    withAnimation(CLMotion.fade) { up = false }
                    return
                }
                withAnimation(.easeInOut(duration: idle == .doze ? 3.2 : 2.2).repeatForever(autoreverses: true)) {
                    up = true
                }
            }
            .task(id: stageKey(script)) {
                // A new pose melts the old clip away; anything else (a trigger, Low Power Mode) just stops it.
                let changedPose = lastPose != nil && lastPose != pose
                lastPose = pose
                let poking = clipTaps != playedClipTaps
                playedClipTaps = clipTaps
                if stage.interrupt(fade: changedPose && !poking) || changedPose {
                    // The old clip (or old drawing) dissolves as the new drawing fades in; the new clip starts when they
                    // have, so it never takes over from a drawing that is still half faded in.
                    try? await Task.sleep(for: .milliseconds(290))
                    guard !Task.isCancelled else { return }
                }
                guard scenePhase == .active, inSight else { return }
                await stage.perform(script, poking: poking, pace: poking ? (squish?.pace ?? 1) : 1)
            }
            .task(id: line?.id) {
                guard let current = line else { return }
                try? await Task.sleep(for: .seconds(current.seconds))
                guard !Task.isCancelled else { return }
                hideLine()
            }
            #if DEBUG
            .task {
                // CRAMLESS_CAP_POKE=3000,6500: tap every Cap on screen at these times (ms after he appears), for films.
                var elapsed = 0
                for time in TestHarness.capPokeTimes {
                    try? await nap(max(0, time - elapsed))
                    elapsed = time
                    guard !Task.isCancelled else { return }
                    touch()
                }
            }
            #endif
            .onScrollVisibilityChange(threshold: 0.05) { inSight = $0 }
            .onDisappear { stage.interrupt(fade: false) }
    }

    /// Changes whenever the clips Cap should be playing do.
    private func stageKey(_ script: CapScript) -> String {
        "\(pose.rawValue) \(trigger) \(clipTaps) \(script.arrival?.id ?? "-") \(script.idle?.id ?? "-") \(script.poke?.id ?? "-") "
            + "\(script.idleGap != nil) \(scenePhase == .active) \(inSight)"
    }

    /// The drawing, cross-fading (and, with motion on, growing from the feet) when the pose changes. A clip plays over it
    /// on its own layer and takes its place while it plays; it starts and ends on the same drawing, so nothing jumps.
    private func art(_ script: CapScript) -> some View {
        // A new drawing grows a little from the feet as it fades in. With a clip on screen the stage fades the drawing in
        // itself (as the clip's last frame fades out), so the transition only grows it: fading twice would thin Cap out
        // halfway through the change.
        let grows = AnyTransition.scale(scale: 0.94, anchor: .bottom)
        let arrival: AnyTransition = reduceMotion ? .opacity : (stage.showsVideo ? grows : .opacity.combined(with: grows))
        return ZStack {
            Image(pose.assetName)
                .resizable()
                .scaledToFit()
                .id(pose.assetName)
                .transition(arrival)
        }
        .opacity(stage.hidesStill ? 0 : 1)
        .frame(width: size, height: size)
        .animation(CLMotion.fade, value: pose.assetName)
        .overlay {
            // 720 px of clip to the pose's 600: the video reaches past the frame, where the pose never does.
            if script.plays {
                CapClipSurface(player: stage.player)
                    .frame(width: size * CapClip.canvasScale, height: size * CapClip.canvasScale)
                    .opacity(stage.showsVideo ? 1 : 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }

    private func play(_ script: CapScript) {
        guard !reduceMotion, script.motion != nil || script.sparkles else { return }
        plays += 1
    }

    // MARK: Being tapped

    /// A tap: he squishes (a fresh roll every time), his reaction plays, he says something and the phone feels it. What he
    /// does follows the settings: "Cap moves" and Reduce Motion decide the squish and the clip, "Cap talks" the words.
    private func touch(says pool: CapLinePool? = nil) {
        guard interactive else { return }
        let moves = CapPlayback.shared.isEnabled && !reduceMotion
        let talks = CapTouch.shared.talks
        guard moves || talks else { return }
        let now = Date()
        run = (lastTapAt.map { now.timeIntervalSince($0) < 1.3 } ?? false) ? run + 1 : 1
        lastTapAt = now
        let shown = pose.shown
        if moves {
            let roll = CapTouch.shared.roll(shown, rapid: run)
            squish = roll
            taps += 1
            CLHaptics.poke(strength: roll.strength)
            // His reaction plays through to its end, where it is on his drawing again. Starting another before then would cut
            // it off mid-gesture and snap him back to the first frame.
            if now >= clipBusyUntil, let clip = script.poke {
                clipBusyUntil = now.addingTimeInterval(clip.duration / max(roll.pace, 0.5) + 0.2)
                clipTaps += 1
            }
        } else {
            CLHaptics.poke(strength: 0.2)
        }
        if talks { say(pool.map { CapTouch.shared.line(in: $0) } ?? CapTouch.shared.line(for: shown, rapid: run)) }
    }

    private func say(_ new: CapLine) {
        withAnimation(CLMotion.pop) { line = new }
        AccessibilityNotification.Announcement(String(localized: new.text)).post()
    }

    private func hideLine() {
        guard line != nil else { return }
        withAnimation(CLMotion.exit) { line = nil }
    }

    /// His bubble, above his head. It is given room of its own (the overlay would hand it only his width, and it would wrap to
    /// three lines), then lifted by its own measured height so its tail ends just over his head.
    @ViewBuilder private var speech: some View {
        if let line {
            CapBubble(text: line.text, tail: -speechShift)
                .onGeometryChange(for: CGSize.self) { $0.size } action: { bubbleSize = $0 }
                .frame(width: 320)
                .offset(x: speechShift, y: speechLift)
                .opacity(bubbleSize.width > 0 && capMidX != 0 ? 1 : 0)
                .transition(reduceMotion ? .opacity : .scale(scale: 0.55, anchor: .bottom).combined(with: .opacity))
                .id(line.id)
        }
    }

    /// How far the bubble moves from over his head to stay inside the screen. Beside him (a short band, where words over his
    /// head would cover the greeting) it starts just past his middle, so its tail still points at him.
    private var speechShift: CGFloat {
        guard bubbleSize.width > 0 else { return 0 }
        let beside = speaksBeside ? bubbleSize.width / 2 + size * 0.12 : 0
        return beside + CGFloat(CapSpeech.shift(capMidX: Double(capMidX + beside), bubbleWidth: Double(bubbleSize.width), screenWidth: Double(CapScreen.width)))
    }

    /// How far the bubble rises: its tail just over his head, or level with his head when it sits beside him.
    private var speechLift: CGFloat {
        speaksBeside ? -bubbleSize.height + size * 0.42 : -(bubbleSize.height + 2) + size * 0.1
    }
}

/// A motion's frame applied to Cap, with the sparkles around (not squashed with) Cap.
private struct CapMotionEffect: ViewModifier {
    let motion: CapMotion?
    let sparkles: Bool
    let seconds: Double
    let size: CGFloat

    func body(content: Content) -> some View {
        let frame = motion?.frame(at: seconds) ?? CapFrame()
        content
            .scaleEffect(x: frame.scaleX * frame.grow, y: frame.scaleY * frame.grow, anchor: .bottom)
            .rotationEffect(.degrees(frame.tilt), anchor: .bottom)
            .offset(y: -frame.lift * size)
            .opacity(frame.opacity)
            .overlay {
                if sparkles, seconds < CapSparkles.duration {
                    CapSparkles(seconds: seconds, size: size)
                }
            }
    }
}

/// Five stars bursting outward around Cap's head and fading, one after another.
struct CapSparkles: View {
    let seconds: Double
    let size: CGFloat

    static let duration = 0.95
    /// Directions from Cap's head (0° points right, −90° up), each star's size as a fraction of Cap's.
    private static let stars: [(angle: Double, scale: Double)] = [(-158, 0.09), (-122, 0.07), (-90, 0.11),
                                                                  (-58, 0.07), (-22, 0.09)]
    private static let life = 0.62
    private static let grow = MotionCurve([(0, 0, .linear), (0.18, 1, .out), (0.62, 0, .in)])
    private static let travel = MotionCurve([(0, 0.3, .linear), (0.62, 0.56, .out)])

    var body: some View {
        ZStack {
            ForEach(0..<Self.stars.count, id: \.self) { index in
                star(index)
            }
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder private func star(_ index: Int) -> some View {
        let local = seconds - Double(index) * 0.06
        if local > 0, local < Self.life {
            let radius = Self.travel.value(at: local) * size
            let angle = Self.stars[index].angle * .pi / 180
            let glyph = max(5, Self.stars[index].scale * size)
            let colour: Color = index.isMultiple(of: 2) ? CLColor.sun : CLColor.tangerine
            Image(systemName: "sparkle")
                .font(.system(size: glyph, weight: .bold))
                .foregroundStyle(colour)
                .scaleEffect(Self.grow.value(at: local))
                .rotationEffect(.degrees(local * 140))
                .offset(x: cos(angle) * radius, y: sin(angle) * radius - size * 0.12)
        }
    }
}

/// Three z's drifting up from a dozing Cap, one after another.
private struct DozeZs: View {
    let size: CGFloat

    private static let cycle = 3.0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<3, id: \.self) { index in
                    z(index, phase: (t / Self.cycle + Double(index) / 3).truncatingRemainder(dividingBy: 1))
                }
            }
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func z(_ index: Int, phase: Double) -> some View {
        let glyph = size * (index.isMultiple(of: 2) ? 0.09 : 0.115)
        let x = size * (0.14 + 0.12 * phase)
        let y = -size * (0.22 + 0.3 * phase)
        return Text(verbatim: "z")
            .font(.system(size: glyph, weight: .heavy, design: .rounded))
            .foregroundStyle(CLColor.ink3)
            .scaleEffect(0.6 + 0.5 * phase)
            .opacity(sin(.pi * phase))
            .offset(x: x, y: y)
    }
}

/// Cap's face in a rounded tile, beside a note ("You keep mixing up anaphase I and II").
struct CapFace: View {
    var size: CGFloat = 44

    var body: some View {
        Image("CapFace")
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .background(CLColor.sky)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.32, style: .continuous))
            .accessibilityHidden(true)
    }
}
