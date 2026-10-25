import AVFoundation
import SwiftUI
import UIKit

// How Cap's clips reach the screen. A clip is HEVC video with an alpha channel, so Cap moves on whatever is behind him.
// The view that shows him (`CapView`) keeps the still under the video and swaps between them with no visible change,
// because every clip starts and ends on its pose's still. Nothing here decides *which* clip plays: that is `CapScript`.

/// A clear view backed by an `AVPlayerLayer`.
final class CapPlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
        playerLayer.videoGravity = .resizeAspect
        playerLayer.backgroundColor = nil
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

/// Hosts a player's view in SwiftUI.
struct CapClipSurface: UIViewRepresentable {
    let player: CapClipPlayer

    func makeUIView(context: Context) -> CapPlayerLayerView { player.view }
    func updateUIView(_ view: CapPlayerLayerView, context: Context) {}
}

/// The assets behind the clips, kept so that playing one starts at once.
@MainActor
enum CapClipLibrary {
    private static var assets: [String: AVURLAsset] = [:]

    static func asset(for clip: CapClip) -> AVURLAsset? {
        if let asset = assets[clip.id] { return asset }
        guard let url = clip.url else { return nil }
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        assets[clip.id] = asset
        return asset
    }

    /// Loads a pose's reaction to a tap ahead of time, so the first tap isn't the one that pays for opening the file.
    static func prewarmPoke(for pose: CapPose, catalog: CapClipCatalog = .shared) {
        guard let clip = catalog.poke(for: pose), let asset = asset(for: clip) else { return }
        Task { _ = try? await asset.load(.isPlayable, .tracks) }
    }

    /// Loads these poses' clips ahead of time (a session does it for Cap's reactions), so the first play isn't the one that
    /// pays for opening the file.
    static func prewarm(_ poses: [CapPose], catalog: CapClipCatalog = .shared) {
        for pose in poses {
            guard let clip = catalog.clip(for: pose), let asset = asset(for: clip) else { continue }
            Task { _ = try? await asset.load(.isPlayable, .tracks) }
        }
    }
}

/// Plays one clip at a time on one `AVPlayerLayer`. `play` returns when a one-shot reaches its end (true) or when it is
/// stopped or replaced (false); a loop only returns false.
@MainActor
final class CapClipPlayer {
    /// Made on first use, so a Cap that never moves never builds one.
    private(set) lazy var view = CapPlayerLayerView()
    /// Called when the first frame is on screen (true) and when the video is taken down (false).
    var onShowing: ((Bool) -> Void)?
    private(set) var isShowing = false

    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    /// The looper of a loop that is fading out, kept until its frame is taken down (see `finish`).
    private var retiring: AVPlayerLooper?
    /// Watches the playhead, to see when frames are really on the layer.
    private var tick: Any?
    private var endToken: NSObjectProtocol?
    private var waiting: CheckedContinuation<Bool, Never>?
    private var startedAt: CFAbsoluteTime = 0
    /// Counts plays, so a delayed clear never empties the layer of a clip that started after it was asked for.
    private var generation = 0
    /// When the last frame of a clip that has just ended may be taken off the layer. The drawing is brought back by SwiftUI
    /// and the layer is cleared by Core Animation; if the layer is cleared first, by even one frame, Cap is missing for that
    /// frame (it happened at the end of a reaction clip, about one in six, and in the next clip's first frames). A clip that
    /// follows another waits until the drawing has had this long to be on screen.
    private var layerHeldUntil: CFAbsoluteTime = 0
    private static let grace = 0.08

    #if DEBUG
    /// Seconds from `play` to the first frame on screen, for the Feel lab.
    private(set) static var latencies: [String: Double] = [:]
    #endif

    func play(_ clip: CapClip, loops: Bool, rate: Double = 1) async -> Bool {
        finish(completed: false, hold: Self.grace)
        generation += 1
        let made = generation
        let wait = layerHeldUntil - CFAbsoluteTimeGetCurrent()
        if wait > 0 {
            try? await Task.sleep(for: .seconds(wait))
            guard generation == made, !Task.isCancelled else { return false }
        }
        guard let asset = CapClipLibrary.asset(for: clip) else { return false }
        let player = freshPlayer()
        let item = AVPlayerItem(asset: asset)
        startedAt = CFAbsoluteTimeGetCurrent()
        tick = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 60), queue: .main) { [weak self] time in
            let seconds = time.seconds
            Task { @MainActor in self?.framesPlayed(until: seconds, of: clip) }
        }
        // A queue player advances at the end of an item, and with nothing after it that empties the layer in the very instant the
        // clip ends: Cap was out for a frame or two before the drawing came back (the end is told to us a hop later, and
        // SwiftUI a frame after that). Paused, the last frame (his drawing) stays on screen until `finish` takes it down.
        player.actionAtItemEnd = loops ? .advance : .pause
        if loops {
            looper = AVPlayerLooper(player: player, templateItem: item)
        } else {
            player.insert(item, after: nil)
            endToken = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.finish(completed: true, hold: 0.12) }
            }
        }
        if rate == 1 { player.play() } else { player.rate = Float(rate) }
        return await withCheckedContinuation { waiting = $0 }
    }

    /// Takes the video down: the drawing is back at once, and the video's last frame is taken off its layer a moment later.
    func stop() { finish(completed: false, hold: Self.grace) }

    /// Hands back to the still but leaves the video's last frame on its layer while the caller fades it out; the layer is
    /// emptied afterwards (a clip that starts in the meantime has already replaced it).
    func fadeOut() { finish(completed: false, hold: 0.45) }

    /// A new player for every clip, on the same layer. A clip that follows another straight away (a reaction to a tap, then the
    /// loop he was in) would otherwise find the layer still "ready" and the player's clock still at the end of the last one, and
    /// the drawing was hidden for two frames before the new clip had a frame to show: Cap blinked out. A new player starts at
    /// zero and its layer is not ready until it has drawn something.
    private func freshPlayer() -> AVQueuePlayer {
        let old = player
        old?.pause()
        let player = AVQueuePlayer()
        player.isMuted = true
        player.allowsExternalPlayback = false
        player.preventsDisplaySleepDuringVideoPlayback = false
        player.automaticallyWaitsToMinimizeStalling = false
        retiring = nil
        view.playerLayer.player = player
        self.player = player
        return player
    }

    /// The video goes on screen once frames are really flowing: the layer says it is ready and two frames have played.
    /// `isReadyForDisplay` alone can still read true from the clip before this one, which would hide the drawing while
    /// the layer has nothing on it yet (Cap blinking out).
    private func framesPlayed(until seconds: Double, of clip: CapClip) {
        guard seconds >= 2 / max(clip.fps, 1), view.playerLayer.isReadyForDisplay else { return }
        showFirstFrame(of: clip)
    }

    private func showFirstFrame(of clip: CapClip) {
        guard waiting != nil, !isShowing else { return }
        isShowing = true
        #if DEBUG
        Self.latencies[clip.id] = CFAbsoluteTimeGetCurrent() - startedAt
        print("cap-clip \(clip.id): first frame after \(Int(Self.latencies[clip.id]! * 1000)) ms")
        #endif
        onShowing?(true)
    }

    /// Ends the current play. The drawing comes back at once (`onShowing(false)`) and the video's last frame is held on its layer
    /// for `hold` seconds, so the drawing is on screen before the video goes: a clip's last frame is its drawing, so the two are
    /// one. A clip asked for in the meantime waits for `layerHeldUntil`.
    private func finish(completed: Bool, hold: Double) {
        if let tick { player?.removeTimeObserver(tick) }
        tick = nil
        if let endToken { NotificationCenter.default.removeObserver(endToken) }
        endToken = nil
        let wasShowing = isShowing
        isShowing = false
        looper?.disableLooping()
        // A loop's items go off the player the moment its looper is let go, which blanks the layer and cuts a dissolve: keep it
        // until the frame is taken down.
        retiring = looper ?? retiring
        looper = nil
        player?.pause()
        if wasShowing {
            layerHeldUntil = max(layerHeldUntil, CFAbsoluteTimeGetCurrent() + Self.grace)
            let held = player
            let made = generation
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(hold))
                if self.generation == made, self.waiting == nil {
                    self.retiring = nil
                    held?.removeAllItems()
                }
            }
            onShowing?(false)
        } else if CFAbsoluteTimeGetCurrent() >= layerHeldUntil {
            // Nothing of it was on screen and nothing earlier is being held, so nothing to wait for.
            retiring = nil
            player?.removeAllItems()
        }
        let waiter = waiting
        waiting = nil
        waiter?.resume(returning: completed)
    }
}

/// Everything about whether Cap's clips may play right now that isn't a single view's business: the setting, Low Power Mode,
/// and how many are playing at once (a decoder each; a screen of Caps keeps the first few moving and the rest still).
@MainActor
@Observable
final class CapPlayback {
    static let shared = CapPlayback()
    static let maxAtOnce = 3

    /// Settings ▸ Accessibility ▸ Feel ▸ "Cap moves". The harness turns it off unless `CRAMLESS_CAP_CLIPS=1` (screenshots
    /// stay still; films ask for it).
    var isEnabled = true
    private(set) var isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @ObservationIgnored private var playing: Set<ObjectIdentifier> = []

    private init() {
        NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled }
        }
    }

    func policy(reduceMotion: Bool) -> CapPlaybackPolicy {
        CapPlaybackPolicy(clips: isEnabled && !reduceMotion, idles: isEnabled && !reduceMotion && !isLowPower)
    }

    func acquire(_ stage: CapStage) -> Bool {
        if playing.contains(ObjectIdentifier(stage)) { return true }
        guard playing.count < Self.maxAtOnce else { return false }
        playing.insert(ObjectIdentifier(stage))
        return true
    }

    func release(_ stage: CapStage) { playing.remove(ObjectIdentifier(stage)) }
}

/// What one `CapView` does with clips: runs its script on its player and says whether the video is showing.
@MainActor
@Observable
final class CapStage {
    let player = CapClipPlayer()
    /// The video is on screen.
    private(set) var showsVideo = false
    /// The drawing underneath is hidden: a few frames after the video appears, never before. A clip starts on its drawing, so
    /// both together look like one for that long; hiding the drawing in the same frame the video came in could land a frame
    /// ahead of it (the two are drawn by different layers) and leave Cap out for 17 ms. On the way out the drawing is back at
    /// once, and the video's last frame stays under it a moment longer.
    private(set) var hidesStill = false
    private var reveal: Task<Void, Never>?

    init() {
        player.onShowing = { [weak self] on in
            guard let self else { return }
            showsVideo = on
            reveal?.cancel()
            if on {
                reveal = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(60))
                    guard !Task.isCancelled else { return }
                    self?.hidesStill = true
                }
            } else {
                hidesStill = false
            }
        }
    }

    /// Takes any playing clip down. With `fade` and a clip on screen, the video melts away over `CLMotion.fade` (a pose
    /// change: the new drawing fades in as it goes) and this returns true, so the caller can wait out the fade before the
    /// next clip starts. Otherwise it is a hard swap (a clip that ended is already the still).
    @discardableResult
    func interrupt(fade: Bool) -> Bool {
        guard fade, showsVideo else {
            player.stop()
            return false
        }
        withAnimation(CLMotion.fade) { player.fadeOut() }
        return true
    }

    /// Plays what the script asks, then goes back to waiting. `poking` is a tap: his reaction to it plays first, in place of
    /// his arrival (he is already there, so a pose with no reaction just carries on), and he goes back to what he was doing.
    func perform(_ script: CapScript, poking: Bool = false, pace: Double = 1) async {
        guard script.hasClip || (poking && script.poke != nil), CapPlayback.shared.acquire(self) else { return }
        defer { CapPlayback.shared.release(self) }
        if poking {
            if let poke = script.poke {
                guard await player.play(poke, loops: false, rate: pace), !Task.isCancelled else { return }
            }
        } else if let arrival = script.arrival {
            guard await player.play(arrival, loops: false), !Task.isCancelled else { return }
        }
        guard let idle = script.idle else { return }
        guard let gap = script.idleGap else {
            _ = await player.play(idle, loops: true)
            return
        }
        guard await rest(script.firstDelay) else { return }
        while !Task.isCancelled {
            guard await player.play(idle, loops: false), !Task.isCancelled else { return }
            guard await rest(Double.random(in: gap)) else { return }
        }
    }

    private func rest(_ seconds: Double) async -> Bool {
        try? await Task.sleep(for: .seconds(seconds))
        return !Task.isCancelled
    }
}
