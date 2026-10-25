import AVFoundation
import UIKit
import XCTest
@testable import Cramless

/// Cap's clips as files: one for every pose, transparent, the size the player expects, and starting and ending on the pose's
/// own still, so a clip can take over from the drawing and hand back to it with nothing visible.
final class CapClipFileTests: XCTestCase {
    private let catalog = CapClipCatalog.shared

    func testEveryPoseHasAClipAndAReactionToBeingTapped() {
        let own = catalog.clips.filter { $0.role != .poke }
        let pokes = catalog.clips.filter { $0.role == .poke }
        XCTAssertEqual(Set(own.map(\.pose)), Set(CapPose.allCases), "a pose has no clip, or two poses share one")
        XCTAssertEqual(own.count, CapPose.allCases.count)
        XCTAssertEqual(Set(pokes.map(\.pose)), Set(CapPose.allCases), "a pose has no reaction to a tap")
        XCTAssertEqual(pokes.count, CapPose.allCases.count)
        XCTAssertEqual(Set(catalog.clips.map(\.id)).count, catalog.clips.count, "two clips share an id")
        for pose in CapPose.allCases {
            XCTAssertEqual(catalog.clip(for: pose)?.pose, pose)
            XCTAssertNotEqual(catalog.clip(for: pose)?.role, .poke, "\(pose): clip(for:) must be the pose's own")
            XCTAssertEqual(catalog.poke(for: pose)?.pose, pose)
            XCTAssertEqual(catalog.poke(for: pose)?.role, .poke)
        }
    }

    func testAClipTheBuildCantReadDoesNotTakeTheOthersDown() throws {
        let manifest = """
        {"version": 1, "clips": [
          {"id": "wave", "pose": "wave", "role": "performance", "file": "cap-wave.mov", "fps": 24, "frames": 97, "duration": 4, "bytes": 1},
          {"id": "waveGhost", "pose": "wave", "role": "something-newer", "file": "cap-x.mov", "fps": 24, "frames": 97, "duration": 4, "bytes": 1},
          {"id": "wavePoke", "pose": "wave", "role": "poke", "file": "cap-wavePoke.mov", "fps": 24, "frames": 73, "duration": 3, "bytes": 1},
          {"id": "nonsense"}
        ]}
        """
        let loaded = CapClipCatalog.decode(try XCTUnwrap(manifest.data(using: .utf8)))
        XCTAssertEqual(loaded.clips.map(\.id), ["wave", "wavePoke"])
        XCTAssertEqual(loaded.clip(for: .wave)?.id, "wave")
        XCTAssertEqual(loaded.poke(for: .wave)?.id, "wavePoke")
        XCTAssertTrue(CapClipCatalog.decode(Data("not json".utf8)).clips.isEmpty)
    }

    func testEveryClipFileIsInTheAppTransparentAndTheRightSize() async throws {
        for clip in catalog.clips {
            let url = try XCTUnwrap(clip.url, "\(clip.id): the file isn't in the app")
            let asset = AVURLAsset(url: url)
            let isPlayable = try await asset.load(.isPlayable)
            XCTAssertTrue(isPlayable, "\(clip.id)")
            let tracks = try await asset.loadTracks(withMediaType: .video)
            let track = try XCTUnwrap(tracks.first, "\(clip.id)")
            let descriptions = try await track.load(.formatDescriptions)
            let extensions = CMFormatDescriptionGetExtensions(try XCTUnwrap(descriptions.first)) as? [String: Any] ?? [:]
            XCTAssertEqual(extensions["ContainsAlphaChannel"] as? Bool, true, "\(clip.id) lost its transparency")
            let size = try await track.load(.naturalSize)
            XCTAssertEqual(size, CGSize(width: 720, height: 720), "\(clip.id)")
            let duration = try await asset.load(.duration).seconds
            XCTAssertEqual(duration, clip.duration, accuracy: 0.1, "\(clip.id): the manifest and the file disagree")
            XCTAssertLessThan(clip.duration, 7, "\(clip.id) is longer than a clip should be")
            XCTAssertLessThan(clip.bytes, 3_000_000, "\(clip.id) is heavy")
        }
    }

    func testEveryClipStartsAndEndsOnItsStill() async throws {
        for clip in catalog.clips {
            let still = try Self.stillOnClipCanvas(clip.pose)
            let frames = try await Self.firstAndLastFrame(of: clip)
            let first = Self.difference(frames.first, still), last = Self.difference(frames.last, still)
            print("cap-clip \(clip.id): first frame differs from its still by \(String(format: "%.4f", first)), last by \(String(format: "%.4f", last))")
            // What is left once a clip is eased onto its drawing is video compression: the colour of a fine edge smears a
            // little (4:2:0 chroma), which is 1% to 3% of the frame by this measure and invisible. A clip that is really off
            // its drawing (zoomed, shifted, in another pose) measured 5% to 27%.
            XCTAssertLessThan(first, 0.035, "\(clip.id) doesn't start on \(clip.pose) (difference \(first))")
            XCTAssertLessThan(last, 0.035, "\(clip.id) doesn't end on \(clip.pose) (difference \(last))")
            if first >= 0.035 || last >= 0.035 { Self.dump(clip.id, [("first", frames.first), ("last", frames.last), ("still", still)]) }
        }
    }

    /// A clip's colour planes are premultiplied and a player draws them as they are, so under every transparent pixel they
    /// must be video-range black (Y 16). The first encode left a few levels of grey there (up to Y 26) and near-white colour
    /// beside the outline: BGRA decoding multiplies that away, which hid it from every other test, but on Today's dark sky it
    /// was a lighter rectangle the size of the clip and a halo round Cap. This reads the planes, not the BGRA.
    func testEveryClipIsBlackUnderItsTransparentPixels() async throws {
        for clip in catalog.clips {
            let stats = try await Self.transparentPlanes(of: clip)
            print("cap-clip \(clip.id): border Y \(stats.borderY), \(String(format: "%.3f", stats.liftedShare * 100))% of transparent pixels lifted, brightest Y \(stats.brightestY)")
            XCTAssertLessThanOrEqual(stats.borderY, 17, "\(clip.id): colour under its transparent border (black is 16): a lighter rectangle on a dark screen")
            XCTAssertLessThan(stats.liftedShare, 0.01, "\(clip.id): colour under its transparent pixels: a halo round Cap on a dark screen")
            XCTAssertLessThanOrEqual(stats.brightestY, 70, "\(clip.id): bright colour under a transparent pixel")
        }
    }

    // MARK: Pixels

    private struct Pixels {
        var bytes: [UInt8]   // premultiplied BGRA, 720 x 720
    }

    private struct PlaneStats {
        var borderY = 16          // the largest luma in the 20 px border band, over the pixels with no alpha
        var liftedShare = 0.0     // the share of all transparent pixels more than 2 above black
        var brightestY = 16
    }

    /// What the file stores under its transparent pixels, read in the decoder's own planes at every 30th frame and the last.
    private static func transparentPlanes(of clip: CapClip) async throws -> PlaneStats {
        let asset = AVURLAsset(url: try XCTUnwrap(clip.url, clip.id))
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first, clip.id)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8VideoRange_8A_TriPlanar])
        reader.add(output)
        XCTAssertTrue(reader.startReading(), "\(clip.id): \(String(describing: reader.error))")
        var stats = PlaneStats()
        var clear = 0, lifted = 0
        var index = 0
        while let sample = output.copyNextSampleBuffer() {
            defer { index += 1 }
            guard index % 30 == 0 || index == clip.frames - 1,
                  let buffer = CMSampleBufferGetImageBuffer(sample), CVPixelBufferGetPlaneCount(buffer) >= 3 else { continue }
            CVPixelBufferLockBaseAddress(buffer, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
            let w = CVPixelBufferGetWidthOfPlane(buffer, 0), h = CVPixelBufferGetHeightOfPlane(buffer, 0)
            let luma = CVPixelBufferGetBaseAddressOfPlane(buffer, 0)!.assumingMemoryBound(to: UInt8.self)
            let alpha = CVPixelBufferGetBaseAddressOfPlane(buffer, 2)!.assumingMemoryBound(to: UInt8.self)
            let lumaStride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0), alphaStride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 2)
            for y in 0..<h {
                for x in 0..<w where alpha[y * alphaStride + x] == 0 {
                    let value = Int(luma[y * lumaStride + x])
                    clear += 1
                    if value > 18 { lifted += 1 }
                    stats.brightestY = max(stats.brightestY, value)
                    if y < 20 || y >= h - 20 || x < 20 || x >= w - 20 { stats.borderY = max(stats.borderY, value) }
                }
            }
        }
        stats.liftedShare = clear > 0 ? Double(lifted) / Double(clear) : 0
        return stats
    }

    /// The pose's drawing in the 720 px frame a clip is drawn on (600 px of pose, 60 px of room all round).
    private static func stillOnClipCanvas(_ pose: CapPose) throws -> Pixels {
        let image = try XCTUnwrap(UIImage(named: pose.assetName)?.cgImage, "\(pose)")
        let canvas = 720, offset = 60
        let context = try XCTUnwrap(CGContext(data: nil, width: canvas, height: canvas, bitsPerComponent: 8, bytesPerRow: canvas * 4,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue))
        context.draw(image, in: CGRect(x: offset, y: offset, width: 600, height: 600))
        return Pixels(bytes: Self.read(context))
    }

    private static func read(_ context: CGContext) -> [UInt8] {
        let count = context.height * context.bytesPerRow
        return Array(UnsafeBufferPointer(start: context.data!.assumingMemoryBound(to: UInt8.self), count: count))
    }

    private static func firstAndLastFrame(of clip: CapClip) async throws -> (first: Pixels, last: Pixels) {
        let asset = AVURLAsset(url: try XCTUnwrap(clip.url))
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        reader.add(output)
        XCTAssertTrue(reader.startReading(), "\(clip.id): \(String(describing: reader.error))")
        var first: Pixels?
        var lastSample: CMSampleBuffer?
        while let sample = output.copyNextSampleBuffer() {
            if first == nil, let buffer = CMSampleBufferGetImageBuffer(sample) { first = Self.pixels(of: buffer) }
            lastSample = sample
        }
        let lastBuffer = try XCTUnwrap(lastSample.flatMap { CMSampleBufferGetImageBuffer($0) }, clip.id)
        return (try XCTUnwrap(first, clip.id), Self.pixels(of: lastBuffer))
    }

    private static func pixels(of buffer: CVPixelBuffer) -> Pixels {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let stride = CVPixelBufferGetBytesPerRow(buffer), width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        let base = CVPixelBufferGetBaseAddress(buffer)!
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { out in
            for y in 0..<height { memcpy(out.baseAddress! + y * width * 4, base + y * stride, width * 4) }
        }
        return Pixels(bytes: bytes)
    }

    /// Writes frames as PNGs to /tmp/cap-clip-dump/ (the simulator shares the Mac's disk) so a failure can be looked at.
    private static func dump(_ name: String, _ frames: [(String, Pixels)]) {
        let dir = URL(fileURLWithPath: "/tmp/cap-clip-dump", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (label, pixels) in frames {
            var bytes = pixels.bytes
            let image: CGImage? = bytes.withUnsafeMutableBytes { raw in
                CGContext(data: raw.baseAddress, width: 720, height: 720, bitsPerComponent: 8, bytesPerRow: 720 * 4,
                          space: CGColorSpaceCreateDeviceRGB(),
                          bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)?.makeImage()
            }
            if let image, let data = UIImage(cgImage: image).pngData() { try? data.write(to: dir.appendingPathComponent("\(name)-\(label).png")) }
        }
    }

    /// Mean absolute difference of two premultiplied images, 0 to 1.
    private static func difference(_ a: Pixels, _ b: Pixels) -> Double {
        var total = 0
        for i in 0..<min(a.bytes.count, b.bytes.count) { total += abs(Int(a.bytes[i]) - Int(b.bytes[i])) }
        return Double(total) / Double(a.bytes.count) / 255
    }
}

/// What a moment asks of Cap, once his clips are counted in.
@MainActor
final class CapScriptTests: XCTestCase {
    private func clip(_ pose: CapPose, _ role: CapClip.Role) -> CapClip {
        let suffix = role == .poke ? "Poke" : ""
        return CapClip(id: "\(pose.rawValue)\(suffix)", pose: pose, role: role, file: "cap-\(pose.rawValue)\(suffix).mov", fps: 24, frames: 96, duration: 4, bytes: 1)
    }

    private func catalog(_ clips: CapClip...) -> CapClipCatalog { CapClipCatalog(clips: clips) }

    func testWithClipsOffTheMomentPlaysAsItAlwaysDid() {
        let cat = catalog(clip(.nice, .performance), clip(.stargaze, .idle))
        let hop = CapScript.make(pose: .nice, motion: .hop, sparkles: true, idle: nil, policy: .off, catalog: cat)
        XCTAssertEqual(hop.motion, .hop)
        XCTAssertTrue(hop.sparkles)
        XCTAssertFalse(hop.hasClip)
        let sky = CapScript.make(pose: .stargaze, motion: nil, sparkles: false, idle: .breathe, policy: .off, catalog: cat)
        XCTAssertTrue(sky.breathes)
        XCTAssertFalse(sky.hasClip)
    }

    func testAPoseWithNoClipPlaysAsItAlwaysDid() {
        let script = CapScript.make(pose: .wave, motion: .hop, sparkles: false, idle: .breathe, policy: .on, catalog: .empty)
        XCTAssertEqual(script.motion, .hop)
        XCTAssertTrue(script.breathes)
        XCTAssertFalse(script.hasClip)
    }

    func testAReactionClipDoesTheMovingSoTheCodeStandsDown() {
        let cat = catalog(clip(.nice, .performance), clip(.almost, .performance), clip(.notYet, .performance))
        for (pose, motion) in [(CapPose.nice, CapMotion.hop), (.almost, .wiggle), (.notYet, .nod)] {
            let script = CapScript.make(pose: pose, motion: motion, sparkles: false, idle: nil, policy: .on, catalog: cat)
            XCTAssertEqual(script.arrival?.pose, pose)
            XCTAssertNil(script.motion, "\(motion) would play on top of the clip")
            XCTAssertNil(script.idle)
        }
    }

    func testTheEntranceAndTheSparklesStayInCode() {
        let cat = catalog(clip(.celebrate, .performance))
        let script = CapScript.make(pose: .celebrate, motion: .arrive, sparkles: true, idle: nil, policy: .on, catalog: cat)
        XCTAssertNotNil(script.arrival)
        XCTAssertEqual(script.motion, .arrive, "Cap rising from the screen's edge is about the screen, not about Cap")
        XCTAssertTrue(script.sparkles)
    }

    func testAnIdleClipLoopsWhileCapWaitsAndPlaysNowAndThenOtherwise() {
        let cat = catalog(clip(.stargaze, .idle))
        let waiting = CapScript.make(pose: .stargaze, motion: nil, sparkles: false, idle: .breathe, policy: .on, catalog: cat)
        XCTAssertNotNil(waiting.idle)
        XCTAssertNil(waiting.idleGap, "he waits on a loop")
        XCTAssertFalse(waiting.breathes, "the clip breathes for him")
        let resting = CapScript.make(pose: .stargaze, motion: nil, sparkles: false, idle: nil, policy: .on, catalog: cat)
        XCTAssertEqual(resting.idleGap, CapScript.idleGapRange, "a Cap that isn't asked to wait still comes alive now and then")
        XCTAssertGreaterThan(resting.firstDelay, 0)
    }

    func testAPerformanceInAPoseHeWaitsInRepeatsNowAndThen() {
        let cat = catalog(clip(.wave, .performance))
        let script = CapScript.make(pose: .wave, motion: nil, sparkles: false, idle: .breathe, policy: .on, catalog: cat)
        XCTAssertNotNil(script.arrival)
        XCTAssertNotNil(script.idle)
        XCTAssertEqual(script.idleGap, CapScript.repeatGapRange)
        XCTAssertGreaterThanOrEqual(script.firstDelay, CapScript.repeatGapRange.lowerBound, "he finishes before he starts again")
        let once = CapScript.make(pose: .wave, motion: nil, sparkles: false, idle: nil, policy: .on, catalog: cat)
        XCTAssertNotNil(once.arrival)
        XCTAssertNil(once.idle, "a reaction in a view that only shows him doesn't repeat")
    }

    func testLowPowerKeepsReactionsAndDropsTheWaiting() {
        let lowPower = CapPlaybackPolicy(clips: true, idles: false)
        let cat = catalog(clip(.nice, .performance), clip(.stargaze, .idle), clip(.wave, .performance))
        XCTAssertNotNil(CapScript.make(pose: .nice, motion: .hop, sparkles: false, idle: nil, policy: lowPower, catalog: cat).arrival)
        let sky = CapScript.make(pose: .stargaze, motion: nil, sparkles: false, idle: .breathe, policy: lowPower, catalog: cat)
        XCTAssertNil(sky.idle)
        XCTAssertTrue(sky.breathes, "with no clip he breathes in code, as he did")
        let wave = CapScript.make(pose: .wave, motion: nil, sparkles: false, idle: .breathe, policy: lowPower, catalog: cat)
        XCTAssertNotNil(wave.arrival)
        XCTAssertNil(wave.idle)
    }

    func testReduceMotionAndTheSettingTurnClipsOff() {
        let playback = CapPlayback.shared
        let before = playback.isEnabled
        defer { playback.isEnabled = before }
        playback.isEnabled = true
        XCTAssertTrue(playback.policy(reduceMotion: false).clips)
        XCTAssertFalse(playback.policy(reduceMotion: true).clips, "Reduce Motion: Cap stays a drawing")
        XCTAssertFalse(playback.policy(reduceMotion: true).idles)
        playback.isEnabled = false
        XCTAssertEqual(playback.policy(reduceMotion: false), .off, "Settings ▸ Cap moves")
    }

    func testEveryMomentGetsItsClip() {
        let moments: [(String, CapMoment)] = [
            ("nice", .nice), ("runMilestone", .runMilestone), ("saved", .saved), ("almost", .almost), ("notYet", .notYet),
            ("answerShown", .answerShown), ("working", .working), ("milestone", .milestone), ("streakAtRisk", .streakAtRisk),
            ("finished", .finished), ("goodnight", .goodnight), ("watchingTheSky", .watchingTheSky), ("relaxed", .relaxed),
            ("pleased", .pleased), ("asleep", .asleep),
        ]
        for (name, moment) in moments {
            let script = CapScript.make(pose: moment.pose, motion: moment.motion, sparkles: moment.sparkles, idle: moment.idle, policy: .on)
            XCTAssertTrue(script.hasClip, "\(name) has no clip")
            if let motion = moment.motion, motion != .arrive, script.arrival != nil {
                XCTAssertNil(script.motion, "\(name): \(motion) would play on top of the clip")
            }
        }
    }

    func testTheTapReactionPlaysInAnyPoseAndNeverReplacesHisOwnClip() {
        let cat = catalog(clip(.nice, .performance), clip(.stargaze, .idle), clip(.nice, .poke), clip(.stargaze, .poke))
        let moment = CapScript.make(pose: .nice, motion: .hop, sparkles: false, idle: nil, policy: .on, catalog: cat)
        XCTAssertEqual(moment.poke?.role, .poke)
        XCTAssertEqual(moment.arrival?.role, .performance, "his own clip is still his arrival")
        XCTAssertTrue(moment.plays)
        let waiting = CapScript.make(pose: .stargaze, motion: nil, sparkles: false, idle: .breathe, policy: .on, catalog: cat)
        XCTAssertEqual(waiting.poke?.pose, .stargaze)
        XCTAssertEqual(waiting.idle?.role, .idle)
    }

    func testWithClipsOffThereIsNoReactionToATapEither() {
        let cat = catalog(clip(.nice, .performance), clip(.nice, .poke))
        let off = CapScript.make(pose: .nice, motion: .hop, sparkles: false, idle: nil, policy: .off, catalog: cat)
        XCTAssertNil(off.poke)
        XCTAssertFalse(off.plays)
    }

    func testLowPowerModeKeepsTheReactionToATap() {
        let cat = catalog(clip(.stargaze, .idle), clip(.stargaze, .poke))
        let lowPower = CapPlaybackPolicy(clips: true, idles: false)
        let script = CapScript.make(pose: .stargaze, motion: nil, sparkles: false, idle: .breathe, policy: lowPower, catalog: cat)
        XCTAssertNil(script.idle, "no waiting loop in Low Power Mode")
        XCTAssertNotNil(script.poke, "a reaction to a tap is not a way of waiting")
        XCTAssertTrue(script.plays)
        XCTAssertFalse(script.hasClip)
    }

    func testAPoseWithNoReactionJustHasNoneAndStillWorks() {
        let cat = catalog(clip(.wave, .performance))
        let script = CapScript.make(pose: .wave, motion: nil, sparkles: false, idle: nil, policy: .on, catalog: cat)
        XCTAssertNil(script.poke)
        XCTAssertNotNil(script.arrival)
    }

    func testCapTalksDefaultsOnAndSurvivesAnOlderSettingsFile() throws {
        XCTAssertTrue(AppSettings().capTalks)
        let old = try XCTUnwrap(#"{"haptics":false,"capMoves":false}"#.data(using: .utf8))
        let decoded = try JSONDecoder.cramless.decode(AppSettings.self, from: old)
        XCTAssertTrue(decoded.capTalks)
        XCTAssertFalse(decoded.capMoves)
        var quiet = AppSettings()
        quiet.capTalks = false
        let round = try JSONDecoder.cramless.decode(AppSettings.self, from: JSONEncoder.cramless.encode(quiet))
        XCTAssertFalse(round.capTalks)
        XCTAssertTrue(round.capMoves, "the two switches are separate")
    }

    func testCapMovesDefaultsOnAndSurvivesAnOlderSettingsFile() throws {
        XCTAssertTrue(AppSettings().capMoves)
        let old = try XCTUnwrap(#"{"haptics":false}"#.data(using: .utf8))
        XCTAssertTrue(try JSONDecoder.cramless.decode(AppSettings.self, from: old).capMoves)
        var off = AppSettings()
        off.capMoves = false
        let round = try JSONDecoder.cramless.decode(AppSettings.self, from: JSONEncoder.cramless.encode(off))
        XCTAssertFalse(round.capMoves)
    }
}
