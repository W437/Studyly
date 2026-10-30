// Reads the text in a picture with Apple's Vision and prints it as JSON: [{text, conf, x, y, w, h}], the box as fractions of the
// picture with y counted from the top. Build: swiftc -O ocr.swift -o ../../../build/store-art/gpt/bin/ocr
import AppKit
import Foundation
import Vision

guard CommandLine.arguments.count > 1 else {
    FileHandle.standardError.write(Data("usage: ocr <image> [language,language...] | ocr --supported\n".utf8))
    exit(2)
}
if CommandLine.arguments[1] == "--supported" {
    let r = VNRecognizeTextRequest()
    r.recognitionLevel = .accurate
    print((try? r.supportedRecognitionLanguages().joined(separator: " ")) ?? "")
    exit(0)
}
let path = CommandLine.arguments[1]
guard let image = NSImage(contentsOfFile: path),
      let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    FileHandle.standardError.write(Data("cannot read \(path)\n".utf8))
    exit(1)
}
let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.usesLanguageCorrection = false
request.recognitionLanguages = CommandLine.arguments.count > 2 ? CommandLine.arguments[2].split(separator: ",").map(String.init) : ["en-US"]
try VNImageRequestHandler(cgImage: cg, options: [:]).perform([request])
var rows: [[String: Any]] = []
for observation in request.results ?? [] {
    guard let best = observation.topCandidates(1).first else { continue }
    let b = observation.boundingBox
    rows.append(["text": best.string, "conf": Double(best.confidence),
                 "x": Double(b.minX), "y": Double(1 - b.maxY), "w": Double(b.width), "h": Double(b.height)])
}
let data = try JSONSerialization.data(withJSONObject: rows)
print(String(data: data, encoding: .utf8) ?? "[]")
