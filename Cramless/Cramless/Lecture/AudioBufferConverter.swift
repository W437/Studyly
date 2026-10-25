import AVFoundation
import Foundation

/// Converts what the microphone delivers into another format: the speech analyzer's
/// (`SpeechAnalyzer.bestAvailableAudioFormat`, 16 kHz Int16 mono when measured) or the recording file's
/// (mono Float32 at the microphone's rate).
///
/// Taken from the owner's Dozen app (`DictationAudioConverter`), where a device proved the two rules that matter:
/// the tap's format is not the analyzer's (feeding the tap's buffers straight in fails or is silent), and the output
/// buffer must be roomy. The converter takes at most 4096 input frames a call and carries the rest to the next
/// call, so a call may owe more than its own buffer brings; a tight output buffer caps what a call returns and leaves
/// that debt standing. One converter lives for a whole recording so the resampler's state carries across buffers.
/// Used from the tap's thread only. Every buffer returned is new (the tap's buffer is the engine's to reuse).
final class AudioBufferConverter: @unchecked Sendable {
    let source: AVAudioFormat
    let target: AVAudioFormat
    private let converter: AVAudioConverter?

    /// Nil when the formats can't be converted into one another.
    init?(from source: AVAudioFormat, to target: AVAudioFormat) {
        self.source = source
        self.target = target
        if Self.matches(source, target) {
            converter = nil
        } else {
            guard let converter = AVAudioConverter(from: source, to: target) else { return nil }
            // No priming frames per call: this is a stream of short buffers, not one file.
            converter.primeMethod = .none
            // Two channels in, one out: mix them rather than drop one.
            converter.downmix = true
            self.converter = converter
        }
    }

    /// Nil for an empty buffer, or one that won't convert.
    func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard buffer.frameLength > 0 else { return nil }
        guard let converter else { return Self.copy(buffer) }
        let ratio = target.sampleRate / source.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio * 2).rounded(.up)) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }
        var delivered = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if delivered {
                inputStatus.pointee = .noDataNow
                return nil
            }
            delivered = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, error == nil, output.frameLength > 0 else { return nil }
        return output
    }

    static func matches(_ a: AVAudioFormat, _ b: AVAudioFormat) -> Bool {
        a.sampleRate == b.sampleRate && a.channelCount == b.channelCount
            && a.commonFormat == b.commonFormat && a.isInterleaved == b.isInterleaved
    }

    static func copy(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else { return nil }
        copy.frameLength = buffer.frameLength
        let from = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        let to = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        for index in 0..<min(from.count, to.count) {
            guard let source = from[index].mData, let destination = to[index].mData else { continue }
            memcpy(destination, source, Int(min(from[index].mDataByteSize, to[index].mDataByteSize)))
        }
        return copy
    }
}

/// A converter that follows the input: when a route change hands the tap a different format, it builds a new
/// converter for it. Thread-safe; fed from the tap's thread.
final class FollowingConverter: @unchecked Sendable {
    let target: AVAudioFormat
    private let lock = NSLock()
    private var converter: AudioBufferConverter?

    init(target: AVAudioFormat) { self.target = target }

    func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        lock.lock()
        defer { lock.unlock() }
        if converter == nil || !AudioBufferConverter.matches(converter!.source, buffer.format) {
            converter = AudioBufferConverter(from: buffer.format, to: target)
        }
        return converter?.convert(buffer)
    }
}

/// Lets recording start the moment the person taps Record, before the speech engine is ready (picking the
/// language takes a second or so): the tap feeds the relay, which keeps copies of the buffers until the transcriber
/// attaches, then replays them in order and forwards the rest. Nothing said in the first seconds goes
/// untranscribed. The backlog is capped (a minute); what overflows is counted so times stay right. Thread-safe.
final class AudioListenerRelay: @unchecked Sendable {
    private let lock = NSLock()
    private var target: AudioListener?
    private var backlog: [AVAudioPCMBuffer] = []
    private var backlogFrames: AVAudioFramePosition = 0
    private var dropped: Double = 0
    private var closed = false
    private let maxSeconds: Double

    init(maxSeconds: Double = 60) { self.maxSeconds = maxSeconds }

    /// What the recorder's tap calls.
    var listener: AudioListener { { [self] buffer in receive(buffer) } }

    /// Seconds of early audio that overflowed the backlog: the transcriber's times start after them.
    var droppedSeconds: Double {
        lock.lock()
        defer { lock.unlock() }
        return dropped
    }

    func receive(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        if let target { return target(buffer) }
        guard !closed, let copy = AudioBufferConverter.copy(buffer) else { return }
        backlog.append(copy)
        backlogFrames += AVAudioFramePosition(copy.frameLength)
        while let first = backlog.first, Double(backlogFrames) / first.format.sampleRate > maxSeconds {
            backlog.removeFirst()
            backlogFrames -= AVAudioFramePosition(first.frameLength)
            dropped += Double(first.frameLength) / first.format.sampleRate
        }
    }

    /// The transcriber is ready: what was kept goes first, in order, then everything live.
    func attach(_ listener: @escaping AudioListener) {
        lock.lock()
        defer { lock.unlock() }
        for buffer in backlog { listener(buffer) }
        backlog = []
        backlogFrames = 0
        target = listener
    }

    /// No transcriber is coming: stop keeping audio.
    func close() {
        lock.lock()
        defer { lock.unlock() }
        closed = true
        target = nil
        backlog = []
        backlogFrames = 0
    }
}

/// The input level for a meter, 0…1, from a buffer's RMS: −60 dBFS (a quiet room) is 0, 0 dBFS is 1.
enum AudioLevel {
    static func level(of buffer: AVAudioPCMBuffer) -> Float {
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return 0 }
        var sum: Float = 0
        if let data = buffer.floatChannelData {
            let samples = data[0]
            for i in 0..<frames { sum += samples[i] * samples[i] }
        } else if let data = buffer.int16ChannelData {
            let samples = data[0]
            for i in 0..<frames { let s = Float(samples[i]) / 32768; sum += s * s }
        } else {
            return 0
        }
        let rms = (sum / Float(frames)).squareRoot()
        guard rms > 0 else { return 0 }
        let decibels = 20 * log10(rms)
        return min(1, max(0, (decibels + 60) / 60))
    }
}
