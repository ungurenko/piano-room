import AVFoundation
import Synchronization

/// In-process stereo reverb. Only the render thread accesses the C++ processor.
final class ReverbUnit: AUAudioUnit {
    private var inputBus: AUAudioUnitBus!
    private var outputBus: AUAudioUnitBus!
    private var inputs: AUAudioUnitBusArray!
    private var outputs: AUAudioUnitBusArray!
    private var inputBuffer: AVAudioPCMBuffer?
    private var outputBuffer: AVAudioPCMBuffer?
    private var processor: OpaquePointer?
    private let resetRequested = Atomic<Bool>(false)
    private let version = Atomic<Int>(0)
    private let target_mix = Atomic<Float>(0.35)
    private let target_enabled = Atomic<Float>(1)
    private let target_decaySeconds = Atomic<Float>(2.2)
    private let target_size = Atomic<Float>(0.3333333333333333)
    private let target_preDelayMs = Atomic<Float>(18)
    private let target_tone = Atomic<Float>(0.5)
    private let target_width = Atomic<Float>(1)
    private let target_modulation = Atomic<Float>(0.2)
    private let target_early = Atomic<Float>(1.2)
    private var last = PRReverbParameters(mix: 0.35, enabled: 1, decaySeconds: 2.2,
        size: 1.0 / 3.0, preDelayMs: 18, tone: 0.5, width: 1, modulation: 0.2, early: 1.2)

    func apply(parameters: ReverbParameters, mix: Float, enabled: Bool) {
        let stamp = version.load(ordering: .sequentiallyConsistent)
        version.store(stamp &+ 1, ordering: .sequentiallyConsistent)
        target_mix.store(mix, ordering: .sequentiallyConsistent)
        target_enabled.store((enabled ? 1 : 0), ordering: .sequentiallyConsistent)
        target_decaySeconds.store(parameters.decaySeconds, ordering: .sequentiallyConsistent)
        target_size.store(parameters.size, ordering: .sequentiallyConsistent)
        target_preDelayMs.store(parameters.preDelayMs, ordering: .sequentiallyConsistent)
        target_tone.store(parameters.tone, ordering: .sequentiallyConsistent)
        target_width.store(parameters.width, ordering: .sequentiallyConsistent)
        target_modulation.store(parameters.modulation, ordering: .sequentiallyConsistent)
        target_early.store(parameters.early, ordering: .sequentiallyConsistent)
        version.store(stamp &+ 2, ordering: .sequentiallyConsistent)
    }

    private func snapshot() -> PRReverbParameters {
        let before = version.load(ordering: .sequentiallyConsistent)
        guard before & 1 == 0 else { return last }
        var value = last
        value.mix = target_mix.load(ordering: .sequentiallyConsistent)
        value.enabled = Int32(target_enabled.load(ordering: .sequentiallyConsistent))
        value.decaySeconds = target_decaySeconds.load(ordering: .sequentiallyConsistent)
        value.size = target_size.load(ordering: .sequentiallyConsistent)
        value.preDelayMs = target_preDelayMs.load(ordering: .sequentiallyConsistent)
        value.tone = target_tone.load(ordering: .sequentiallyConsistent)
        value.width = target_width.load(ordering: .sequentiallyConsistent)
        value.modulation = target_modulation.load(ordering: .sequentiallyConsistent)
        value.early = target_early.load(ordering: .sequentiallyConsistent)
        if before == version.load(ordering: .sequentiallyConsistent) { last = value }
        return last
    }

    override init(componentDescription: AudioComponentDescription,
                  options: AudioComponentInstantiationOptions = []) throws {
        try super.init(componentDescription: componentDescription, options: options)
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        inputBus = try AUAudioUnitBus(format: format)
        outputBus = try AUAudioUnitBus(format: format)
        inputBus.maximumChannelCount = 2
        outputBus.maximumChannelCount = 2
        inputs = AUAudioUnitBusArray(audioUnit: self, busType: .input, busses: [inputBus])
        outputs = AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: [outputBus])
    }
    override var inputBusses: AUAudioUnitBusArray { inputs }
    override var outputBusses: AUAudioUnitBusArray { outputs }
    override func allocateRenderResources() throws {
        let format = outputBus.format
        guard format.channelCount == 2, format.commonFormat == .pcmFormatFloat32,
              !format.isInterleaved, inputBus.format == format else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(kAudioUnitErr_FormatNotSupported))
        }
        try super.allocateRenderResources()
        if let processor { pr_reverb_destroy(processor) }
        processor = pr_reverb_create(format.sampleRate, maximumFramesToRender)
        inputBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: maximumFramesToRender)
        outputBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: maximumFramesToRender)
        guard processor != nil, inputBuffer != nil, outputBuffer != nil else {
            deallocateRenderResources()
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(kAudioUnitErr_FailedInitialization))
        }
    }
    override func deallocateRenderResources() {
        if let processor { pr_reverb_destroy(processor) }
        processor = nil
        inputBuffer = nil
        outputBuffer = nil
        super.deallocateRenderResources()
    }
    override func reset() {
        super.reset()
        resetRequested.store(true, ordering: .releasing)
    }

    override var internalRenderBlock: AUInternalRenderBlock {
        { [unowned self] flags, timestamp, frames, bus, data, _, pull in
            guard frames <= self.maximumFramesToRender else { return kAudioUnitErr_TooManyFramesToProcess }
            guard bus == 0, let pull else { return kAudioUnitErr_NoConnection }
            guard let processor = self.processor, let input = self.inputBuffer,
                  let scratch = self.outputBuffer else { return kAudioUnitErr_Uninitialized }
            input.frameLength = frames
            let status = pull(flags, timestamp, frames, 0, input.mutableAudioBufferList)
            guard status == noErr else { return status }
            let buffers = UnsafeMutableAudioBufferListPointer(data)
            guard buffers.count == 2, let channels = input.floatChannelData,
                  let fallback = scratch.floatChannelData else { return kAudioUnitErr_FormatNotSupported }
            for c in 0..<2 {
                if buffers[c].mData == nil { buffers[c].mData = UnsafeMutableRawPointer(fallback[c]) }
                buffers[c].mDataByteSize = frames * 4
            }
            pr_reverb_set_parameters(processor, self.snapshot())
            if self.resetRequested.exchange(false, ordering: .acquiringAndReleasing) {
                pr_reverb_reset(processor)
            }
            pr_reverb_process(processor, channels[0], channels[1],
                buffers[0].mData!.assumingMemoryBound(to: Float.self),
                buffers[1].mData!.assumingMemoryBound(to: Float.self), frames)
            flags.pointee.remove(.unitRenderAction_OutputIsSilence)
            return noErr
        }
    }
}
