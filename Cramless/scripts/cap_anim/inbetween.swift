import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import ImageIO
import UniformTypeIdentifiers
import VideoToolbox

// inbetween <plan.json>
//
// Draws the pictures a clip is missing. Some of Cap's clips were animated "on twos" or "on threes": the video model changed the
// drawing only every 2nd or 3rd frame and held it in between, so a 24 fps file moved 8 or 12 times a second and looked choppy
// on a 120 Hz screen (`produce.py check` measures it, `produce.py smooth` calls this). The plan lists the frames that really
// are new drawings (the keys) and where each one sits in time; every other frame is made here, from the two keys around it,
// by Apple's frame-rate conversion (optical flow). Keys are copied exactly as they are.
//
//     { "out": "<dir>", "frames": 121, "keys": [ { "file": "<png>", "n": 0 }, { "file": "<png>", "n": 3 }, ... ] }
//
// The keys are the video model's own frames: Cap on the flat magenta it draws him against, before any cut-out. The in-betweens
// are made on those, one picture at a time, and the usual keyer then cuts Cap out of every frame alike. (A first version cut Cap
// out first and moved his colour and his alpha in two passes: where the paw moved fast the two passes disagreed, and the paw came
// out pink-speckled and see-through.) `out` gets 0001.png ... <frames>.png.

struct Plan: Decodable {
    struct Key: Decodable {
        var file: String
        var n: Int
    }

    var out: String
    var frames: Int
    var keys: [Key]
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

guard CommandLine.arguments.count == 2 else { fail("usage: inbetween <plan.json>") }
guard let data = FileManager.default.contents(atPath: CommandLine.arguments[1]), let plan = try? JSONDecoder().decode(Plan.self, from: data) else {
    fail("cannot read the plan \(CommandLine.arguments[1])")
}
guard plan.keys.count >= 2, plan.keys.first?.n == 0, zip(plan.keys, plan.keys.dropFirst()).allSatisfy({ $0.n < $1.n }),
      let lastKey = plan.keys.last, lastKey.n < plan.frames else {
    fail("the keys must start at frame 0, rise, and end inside the clip")
}
let outDir = URL(fileURLWithPath: plan.out)
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func image(_ path: String) -> CGImage {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fail("cannot read \(path)") }
    return image
}

let first = image(plan.keys[0].file)
let width = first.width, height = first.height
let rect = CGRect(x: 0, y: 0, width: width, height: height)
/// The frames' own colour space, so no colour is converted on the way in or out (a key and the pictures between must match).
let space = first.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
let halfInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.floatComponents.rawValue | CGBitmapInfo.byteOrder16Little.rawValue

func makeBuffer() -> CVPixelBuffer {
    var buffer: CVPixelBuffer?
    let attributes: [String: Any] = [kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()]
    let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_64RGBAHalf, attributes as CFDictionary, &buffer)
    guard status == kCVReturnSuccess, let buffer else { fail("CVPixelBufferCreate failed (\(status))") }
    return buffer
}

/// An opaque frame as half-float RGBA.
func load(_ path: String) -> CVPixelBuffer {
    let buffer = makeBuffer()
    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    guard let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 16,
                                  bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: space, bitmapInfo: halfInfo) else {
        fail("no half-float context")
    }
    context.clear(rect)
    context.draw(image(path), in: rect)
    return buffer
}

/// A converted buffer as an opaque 8-bit PNG.
func write(_ buffer: CVPixelBuffer, to url: URL) {
    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    guard let source = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 16,
                                 bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: space, bitmapInfo: halfInfo),
          let half = source.makeImage(),
          let eight = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { fail("cannot read the buffer") }
    eight.draw(half, in: rect)
    guard let out = eight.makeImage(), let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fail("cannot write \(url.path)")
    }
    CGImageDestinationAddImage(destination, out, nil)
    guard CGImageDestinationFinalize(destination) else { fail("cannot finish \(url.path)") }
}

func name(_ n: Int) -> URL { outDir.appendingPathComponent(String(format: "%04d.png", n + 1)) }

func copy(_ path: String, to url: URL) {
    try? FileManager.default.removeItem(at: url)
    do { try FileManager.default.copyItem(atPath: path, toPath: url.path) } catch { fail("cannot copy \(path): \(error)") }
}

let timescale: Int32 = 6000

func frame(_ buffer: CVPixelBuffer, at value: Int64) -> VTFrameProcessorFrame {
    guard let frame = VTFrameProcessorFrame(buffer: buffer, presentationTimeStamp: CMTime(value: value, timescale: timescale)) else {
        fail("cannot wrap a picture for the frame processor")
    }
    return frame
}

@available(macOS 15.4, *)
struct Interpolator {
    let processor = VTFrameProcessor()

    init() throws {
        guard VTFrameRateConversionConfiguration.isSupported else { fail("frame-rate conversion is not supported on this Mac") }
        guard let configuration = VTFrameRateConversionConfiguration(frameWidth: width, frameHeight: height, usePrecomputedFlow: false,
                                                                     qualityPrioritization: .quality, revision: .revision1) else {
            fail("no configuration for \(width) x \(height)")
        }
        try processor.startSession(configuration: configuration)
    }

    /// The pictures between `a` and `b` at these phases (0 is `a`, 1 is `b`).
    func between(_ a: CVPixelBuffer, _ b: CVPixelBuffer, phases: [Float]) async throws -> [CVPixelBuffer] {
        let outputs = phases.map { _ in makeBuffer() }
        let destinations = outputs.enumerated().map { frame($1, at: Int64(Float(timescale) * phases[$0])) }
        guard let parameters = VTFrameRateConversionParameters(sourceFrame: frame(a, at: 0), nextFrame: frame(b, at: Int64(timescale)),
                                                               opticalFlow: nil, interpolationPhase: phases, submissionMode: .random,
                                                               destinationFrames: destinations) else {
            fail("cannot make the frame-rate conversion parameters")
        }
        try await processor.process(parameters: parameters)
        return outputs
    }

    func end() { processor.endSession() }
}

if #available(macOS 15.4, *) {
    let interpolator = try Interpolator()
    var made = 0
    copy(plan.keys[0].file, to: name(0))
    var from = load(plan.keys[0].file)
    for pair in zip(plan.keys, plan.keys.dropFirst()) {
        let (a, b) = pair
        let gap = b.n - a.n
        let to = load(b.file)
        if gap > 1 {
            let phases = (1..<gap).map { Float($0) / Float(gap) }
            for (i, picture) in try await interpolator.between(from, to, phases: phases).enumerated() {
                write(picture, to: name(a.n + 1 + i))
                made += 1
            }
        }
        copy(b.file, to: name(b.n))
        from = to
    }
    for n in (lastKey.n + 1)..<plan.frames { copy(lastKey.file, to: name(n)) }       // after the last key he holds still
    interpolator.end()
    print("\(plan.frames) frames: \(plan.keys.count) keys kept, \(made) drawn between them -> \(outDir.path)")
} else {
    fail("needs macOS 15.4 or later")
}
