import AVFoundation
import Foundation
import Synchronization

/// Собственный эффект хоруса.
///
/// Apple не поставляет хорус среди системных эффектов, поэтому модулированная
/// задержка реализована здесь как обычный Audio Unit в процессе приложения.
/// Алгоритм простой: сигнал задерживается на 12 мс, задержка плавно колеблется
/// около этого значения, сухой и обработанный сигнал смешиваются.
final class ChorusUnit: AUAudioUnit {

    // MARK: - Шины

    private var inputBus: AUAudioUnitBus!
    private var outputBus: AUAudioUnitBus!
    private var _inputBusses: AUAudioUnitBusArray!
    private var _outputBusses: AUAudioUnitBusArray!

    // MARK: - Буферы задержки

    private var ringBuffers: [UnsafeMutablePointer<Float>?] = []
    private var ringLength: Int = 0
    private var writeIndex: Int = 0

    // MARK: - Состояние

    private var sampleRate: Double = 48_000
    private var channelCount: Int = 2
    private var lfoPhase: Float = 0

    private let maxDelayMilliseconds: Float = 60
    private let baseDelayMilliseconds: Float = 12

    // MARK: - Параметры (меняются из интерфейса)

    private let rate = Atomic<Float>(0.5)
    private let depth = Atomic<Float>(3)
    private let wetMix = Atomic<Float>(0.5)
    private let enabled = Atomic<Bool>(true)
    var rateHz: Float {
        get { rate.load(ordering: .relaxed) }
        set { rate.store(newValue.isFinite ? max(0, min(20, newValue)) : 0.5, ordering: .relaxed) }
    }
    var depthMilliseconds: Float {
        get { depth.load(ordering: .relaxed) }
        set { depth.store(newValue.isFinite ? max(0, min(40, newValue)) : 3, ordering: .relaxed) }
    }
    var mix: Float {
        get { wetMix.load(ordering: .relaxed) }
        set { wetMix.store(newValue.isFinite ? max(0, min(1, newValue)) : 0, ordering: .relaxed) }
    }
    var isEnabled: Bool {
        get { enabled.load(ordering: .relaxed) }
        set { enabled.store(newValue, ordering: .relaxed) }
    }

    // MARK: - Инициализация

    override init(
        componentDescription: AudioComponentDescription,
        options: AudioComponentInstantiationOptions = []
    ) throws {
        try super.init(componentDescription: componentDescription, options: options)

        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        inputBus = try AUAudioUnitBus(format: format)
        outputBus = try AUAudioUnitBus(format: format)

        inputBus.maximumChannelCount = 2
        outputBus.maximumChannelCount = 2

        _inputBusses = AUAudioUnitBusArray(audioUnit: self, busType: .input, busses: [inputBus])
        _outputBusses = AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: [outputBus])
    }

    override var inputBusses: AUAudioUnitBusArray { _inputBusses }
    override var outputBusses: AUAudioUnitBusArray { _outputBusses }

    // MARK: - Ресурсы

    override func allocateRenderResources() throws {
        try super.allocateRenderResources()

        releaseBuffers()
        sampleRate = outputBus.format.sampleRate
        channelCount = Int(outputBus.format.channelCount)

        let maximumDelaySamples = Int(maxDelayMilliseconds / 1000 * Float(sampleRate))
        ringLength = maximumDelaySamples + Int(maximumFramesToRender) + 8

        for _ in 0..<max(channelCount, 1) {
            guard let pointer = UnsafeMutablePointer<Float>.allocate(capacity: ringLength > 0 ? ringLength : 1) as UnsafeMutablePointer<Float>? else {
                continue
            }
            pointer.initialize(repeating: 0, count: max(ringLength, 1))
            ringBuffers.append(pointer)
        }

        writeIndex = 0
        lfoPhase = 0
    }

    override func deallocateRenderResources() {
        releaseBuffers()
        super.deallocateRenderResources()
    }

    private func releaseBuffers() {
        for pointer in ringBuffers {
            pointer?.deinitialize(count: max(ringLength, 1))
            pointer?.deallocate()
        }
        ringBuffers.removeAll()
    }

    // MARK: - Рендер

    override var internalRenderBlock: AUInternalRenderBlock {
        return { [unowned self] actionFlags, timestamp, frameCount, outputBusNumber, outputData, realtimeEventListHead, pullInputBlock in
            guard let pullInputBlock else { return kAudioUnitErr_NoConnection }

            var pullFlags = AudioUnitRenderActionFlags()
            let status = pullInputBlock(&pullFlags, timestamp, frameCount, 0, outputData)
            guard status == noErr else { return status }
            guard !self.ringBuffers.isEmpty else { return noErr }

            let frames = Int(frameCount)
            guard frames > 0, self.ringLength > 0 else { return noErr }

            let rate = Float(self.sampleRate)
            let increment = self.rateHz / max(rate, 1)
            let wet = self.isEnabled ? self.mix : 0
            let dry = 1 - wet
            let baseSamples = self.baseDelayMilliseconds / 1000 * rate
            let depthSamples = self.depthMilliseconds / 1000 * rate * 0.5
            let ringLength = self.ringLength
            let ringLengthFloat = Float(ringLength)

            let initialWrite = self.writeIndex
            let initialPhase = self.lfoPhase
            let bufferList = UnsafeMutableAudioBufferListPointer(outputData)

            for (bufferIndex, buffer) in bufferList.enumerated() {
                guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                guard bufferIndex < self.ringBuffers.count, let ring = self.ringBuffers[bufferIndex] else { continue }

                var write = initialWrite
                var phase = initialPhase
                let channelOffset: Float = bufferIndex == 0 ? 0 : 0.25

                for frame in 0..<min(frames, Int(buffer.mDataByteSize) / MemoryLayout<Float>.size) {
                    let angle = 2 * Float.pi * (phase + channelOffset)
                    let lfo = sinf(angle)
                    let delaySamples = baseSamples + depthSamples * (1 + lfo)

                    var readPosition = Float(write) - delaySamples
                    while readPosition < 0 { readPosition += ringLengthFloat }
                    while readPosition >= ringLengthFloat { readPosition -= ringLengthFloat }

                    let integerPart = Int(readPosition)
                    let fraction = readPosition - Float(integerPart)
                    let index0 = integerPart % ringLength
                    let index1 = (integerPart + 1) % ringLength
                    let delayed = ring[index0] * (1 - fraction) + ring[index1] * fraction

                    let input = data[frame]
                    ring[write] = input
                    data[frame] = input * dry + delayed * wet

                    write += 1
                    if write >= ringLength { write = 0 }
                    phase += increment
                    if phase >= 1 { phase -= 1 }
                }
            }

            self.writeIndex = (initialWrite + frames) % ringLength
            let finalPhase = initialPhase + Float(frames) * increment
            self.lfoPhase = finalPhase - floorf(finalPhase)
            return noErr
        }
    }
}
