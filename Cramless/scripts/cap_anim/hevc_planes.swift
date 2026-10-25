import AVFoundation
import CoreVideo
import Foundation

// Reads a clip's frames in the decoder's own format (YCbCr planes plus a separate alpha plane) and reports what is stored
// where the picture is transparent. `hevc_frames.swift` asks for BGRA, which Apple premultiplies on the way out, so colour
// hidden under zero alpha reads as black there; a player that draws the planes itself (a layer on screen) can show it.
//
//   swift hevc_planes.swift <clip.mov> [frame numbers, 0-based; default 0 30 60 -1]   (-1 is the last frame)
//
// Prints, for the 20 px band round the canvas (where Cap never is): the alpha plane's range, and Y, Cb and Cr over the pixels
// whose alpha is zero. A clean file has Y = 16, Cb = Cr = 128 there (video-range black) and alpha = 0. A second line covers
// every transparent pixel in the frame, Cap's outline included: how many are lifted above black by more than 2 levels (ringing
// round the outline shows as a halo on a dark screen) and the brightest.

let args = CommandLine.arguments
guard args.count >= 2 else { print("usage: hevc_planes.swift clip.mov [frames…]"); exit(2) }
let url = URL(fileURLWithPath: args[1])
var wanted = args.count > 2 ? args[2...].compactMap { Int($0) } : [0, 30, 60, -1]

let asset = AVURLAsset(url: url)
let track = try await asset.loadTracks(withMediaType: .video).first!
let reader = try AVAssetReader(asset: asset)
let format = kCVPixelFormatType_420YpCbCr8VideoRange_8A_TriPlanar
let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: format])
reader.add(output)
reader.startReading()

var index = 0
var last: (Int, CVPixelBuffer)?
func report(_ n: Int, _ pixels: CVPixelBuffer) {
    CVPixelBufferLockBaseAddress(pixels, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }
    let planes = CVPixelBufferGetPlaneCount(pixels)
    guard planes >= 3 else { print("frame \(n): \(planes) planes (format \(CVPixelBufferGetPixelFormatType(pixels)))"); return }
    let w = CVPixelBufferGetWidthOfPlane(pixels, 0), h = CVPixelBufferGetHeightOfPlane(pixels, 0)
    func plane(_ p: Int) -> (UnsafeMutablePointer<UInt8>, Int) {
        (CVPixelBufferGetBaseAddressOfPlane(pixels, p)!.assumingMemoryBound(to: UInt8.self), CVPixelBufferGetBytesPerRowOfPlane(pixels, p))
    }
    let (yp, ys) = plane(0), (cp, cs) = plane(1), (ap, as_) = plane(2)
    var aMin = 255, aMax = 0, count = 0
    var yMin = 255, yMax = 0, ySum = 0, cbSum = 0, crSum = 0
    for y in 0..<h {
        for x in 0..<w {
            let inBand = y < 20 || y >= h - 20 || x < 20 || x >= w - 20
            guard inBand else { continue }
            let a = Int(ap[y * as_ + x])
            aMin = min(aMin, a); aMax = max(aMax, a)
            guard a == 0 else { continue }
            let yy = Int(yp[y * ys + x])
            yMin = min(yMin, yy); yMax = max(yMax, yy); ySum += yy
            cbSum += Int(cp[(y / 2) * cs + (x / 2) * 2])
            crSum += Int(cp[(y / 2) * cs + (x / 2) * 2 + 1])
            count += 1
        }
    }
    let n1 = max(count, 1)
    print(String(format: "frame %3d: alpha band %d...%d; where alpha is 0 (%d px): Y %d...%d (mean %.1f), Cb %.1f, Cr %.1f",
                 n, aMin, aMax, count, yMin, yMax, Double(ySum) / Double(n1), Double(cbSum) / Double(n1), Double(crSum) / Double(n1)))
    var clear = 0, lifted = 0, brightest = 16
    for y in 0..<h {
        for x in 0..<w where ap[y * as_ + x] == 0 {
            clear += 1
            let yy = Int(yp[y * ys + x])
            if yy > 18 { lifted += 1 }
            brightest = max(brightest, yy)
        }
    }
    print(String(format: "          all %d transparent px: %d lifted by more than 2 (%.3f%%), brightest Y %d", clear, lifted,
                 100 * Double(lifted) / Double(max(clear, 1)), brightest))
}

while let sample = output.copyNextSampleBuffer() {
    defer { index += 1 }
    guard let pixels = CMSampleBufferGetImageBuffer(sample) else { continue }
    if index == 0 {
        print("\(url.lastPathComponent): decoder format \(String(format: "%c%c%c%c", (format >> 24) & 255, (format >> 16) & 255, (format >> 8) & 255, format & 255)), "
              + "\(CVPixelBufferGetWidth(pixels))x\(CVPixelBufferGetHeight(pixels)), \(CVPixelBufferGetPlaneCount(pixels)) planes")
        if let attachments = CVBufferCopyAttachments(pixels, .shouldPropagate) as? [String: Any] {
            for key in ["CVImageBufferYCbCrMatrix", "CVImageBufferColorPrimaries", "CVImageBufferTransferFunction", "ChromaLocationTopField"] {
                if let v = attachments[key] { print("  \(key): \(v)") }
            }
        }
    }
    if wanted.contains(index) { report(index, pixels) }
    if wanted.contains(-1) { last = (index, pixels) }
}
if let (n, pixels) = last, wanted.contains(-1) { report(n, pixels) }
print("frames read: \(index)")
