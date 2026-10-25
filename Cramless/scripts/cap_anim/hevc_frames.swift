import AVFoundation
import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Reads a video through AVFoundation (the same decoder the app uses) and writes chosen frames as PNGs with their alpha, and
// prints what the file says about itself. ffmpeg cannot read Apple's alpha layer, so this is how an HEVC-with-alpha clip is
// checked.
//
//   swift hevc_frames.swift <clip.mov> <out-dir> [frame numbers, 0-based; "all" for every frame]
//
// Prints: codec, ContainsAlphaChannel, size, frame count, duration, and the average alpha of each written frame.

let args = CommandLine.arguments
guard args.count >= 3 else { print("usage: hevc_frames.swift clip.mov out-dir [frames…|all]"); exit(2) }
let url = URL(fileURLWithPath: args[1])
let outDir = URL(fileURLWithPath: args[2], isDirectory: true)
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
let wanted: Set<Int>? = args.count > 3 && args[3] != "all" ? Set(args[3...].compactMap { Int($0) }) : nil

let asset = AVURLAsset(url: url)
let track = try await asset.loadTracks(withMediaType: .video).first!
let descs = try await track.load(.formatDescriptions)
let ext = CMFormatDescriptionGetExtensions(descs[0]) as? [String: Any] ?? [:]
let size = try await track.load(.naturalSize)
let fps = try await track.load(.nominalFrameRate)
let duration = try await asset.load(.duration).seconds
let codec = CMFormatDescriptionGetMediaSubType(descs[0])
let fourcc = String(format: "%c%c%c%c", (codec >> 24) & 255, (codec >> 16) & 255, (codec >> 8) & 255, codec & 255)
print("\(url.lastPathComponent): codec \(fourcc), alpha=\(ext["ContainsAlphaChannel"] as? Bool ?? false), \(Int(size.width))x\(Int(size.height)), \(fps) fps, \(String(format: "%.3f", duration)) s")

let reader = try AVAssetReader(asset: asset)
let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
reader.add(output)
reader.startReading()
var index = 0
while let sample = output.copyNextSampleBuffer() {
    defer { index += 1 }
    if let wanted, !wanted.contains(index) { continue }
    guard let pixels = CMSampleBufferGetImageBuffer(sample) else { continue }
    CVPixelBufferLockBaseAddress(pixels, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }
    let w = CVPixelBufferGetWidth(pixels), h = CVPixelBufferGetHeight(pixels), stride = CVPixelBufferGetBytesPerRow(pixels)
    let base = CVPixelBufferGetBaseAddress(pixels)!.assumingMemoryBound(to: UInt8.self)
    var alphaSum = 0.0
    for y in 0..<h { for x in 0..<w { alphaSum += Double(base[y * stride + x * 4 + 3]) } }
    let ctx = CGContext(data: base, width: w, height: h, bitsPerComponent: 8, bytesPerRow: stride, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    let image = ctx.makeImage()!
    let dest = CGImageDestinationCreateWithURL(outDir.appendingPathComponent(String(format: "%04d.png", index + 1)) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
    if wanted != nil || index % 20 == 0 { print("  frame \(index): mean alpha \(String(format: "%.3f", alphaSum / Double(w * h) / 255))") }
}
print("frames read: \(index)")
