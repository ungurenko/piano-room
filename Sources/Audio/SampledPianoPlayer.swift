import AVFoundation
import os

private let pianoLogger = Logger(subsystem: "com.alexpianoroom.PianoRoom", category: "sampled-piano")

/// The audio queue changes this state only while AVAudioEngine is stopped.
/// The source node retains it until its final render callback has completed.
private final class PianoRenderState: @unchecked Sendable {
    let maximumFrames: UInt32 = 4096
    let left = UnsafeMutablePointer<Float>.allocate(capacity: 4096)
    let right = UnsafeMutablePointer<Float>.allocate(capacity: 4096)
    var processor: OpaquePointer?

    init() {
        left.initialize(repeating: 0, count: 4096)
        right.initialize(repeating: 0, count: 4096)
    }
    deinit {
        if let processor { pr_piano_destroy(processor) }
        left.deinitialize(count: 4096)
        right.deinitialize(count: 4096)
        left.deallocate()
        right.deallocate()
    }
}

final class SampledPianoPlayer {
    let node: AVAudioSourceNode
    private let state: PianoRenderState
    private var loadedURL: URL?

    init() {
        let state = PianoRenderState()
        self.state = state
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        node = AVAudioSourceNode(format: format) { @Sendable silence, _, frames, output in
            guard frames <= state.maximumFrames else { return kAudioUnitErr_TooManyFramesToProcess }
            let buffers = UnsafeMutableAudioBufferListPointer(output)
            guard buffers.count == 2 else { return kAudioUnitErr_FormatNotSupported }
            if buffers[0].mData == nil { buffers[0].mData = UnsafeMutableRawPointer(state.left) }
            if buffers[1].mData == nil { buffers[1].mData = UnsafeMutableRawPointer(state.right) }
            for channel in 0..<2 { buffers[channel].mDataByteSize = frames * 4 }
            let left = buffers[0].mData!.assumingMemoryBound(to: Float.self)
            let right = buffers[1].mData!.assumingMemoryBound(to: Float.self)
            if let processor = state.processor {
                pr_piano_render(processor, left, right, frames)
                silence.pointee = false
            } else {
                left.update(repeating: 0, count: Int(frames))
                right.update(repeating: 0, count: Int(frames))
                silence.pointee = true
            }
            return noErr
        }
    }

    /// Call only after stopping the engine. A failed load preserves the previous bank.
    func load(at url: URL, name: String) throws {
        if loadedURL == url, state.processor != nil {
            reset()
            return
        }
        guard let candidate = pr_piano_create(48_000, state.maximumFrames) else {
            throw AudioEngine.EngineError.instrumentLoadFailed(name)
        }
        let success = url.path.withCString { pr_piano_load(candidate, $0) }
        guard success != 0 else {
            if let reason = pr_piano_error(candidate) {
                pianoLogger.error("Instrument load failed: \(String(cString: reason), privacy: .public)")
            }
            pr_piano_destroy(candidate)
            throw AudioEngine.EngineError.instrumentLoadFailed(name)
        }
        if let previous = state.processor { pr_piano_destroy(previous) }
        state.processor = candidate
        loadedURL = url
    }

    /// Call only while the engine is stopped.
    func reset() {
        if let processor = state.processor { pr_piano_reset(processor) }
    }

    /// Call only while the engine is stopped.
    func unload() {
        if let processor = state.processor { pr_piano_destroy(processor) }
        state.processor = nil
        loadedURL = nil
    }

    func send(_ status: UInt8, _ first: UInt8, _ second: UInt8 = 0) {
        guard let processor = state.processor else { return }
        _ = pr_piano_midi(processor, status, first, second)
    }
}
