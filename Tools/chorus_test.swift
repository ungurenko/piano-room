// Offline DSP regression tests. No engine, audio device or MIDI client is started.
import AVFoundation

func makeUnit(blockSize: UInt32) throws -> ChorusUnit {
    let description = AudioComponentDescription(componentType: kAudioUnitType_Effect,
        componentSubType: 0x63687273, componentManufacturer: 0x50526d73,
        componentFlags: 0, componentFlagsMask: 0)
    let unit = try ChorusUnit(componentDescription: description)
    unit.maximumFramesToRender = blockSize
    unit.rateHz = 0
    unit.depthMilliseconds = 0
    unit.mix = 1
    try unit.allocateRenderResources()
    return unit
}

func render(_ unit: ChorusUnit, blockSize: Int, block: Int, impulse: Bool) -> [[Float]] {
    let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: UInt32(blockSize))!
    buffer.frameLength = UInt32(blockSize)
    var flags = AudioUnitRenderActionFlags()
    var time = AudioTimeStamp()
    time.mSampleTime = Double(block * blockSize)
    time.mFlags = .sampleTimeValid
    let status = unit.internalRenderBlock(&flags, &time, UInt32(blockSize), 0,
                                         buffer.mutableAudioBufferList, nil) { _, _, count, _, data in
        for item in UnsafeMutableAudioBufferListPointer(data) {
            let samples = item.mData!.assumingMemoryBound(to: Float.self)
            samples.update(repeating: 0, count: Int(count))
            if impulse { samples[0] = 1 }
        }
        return noErr
    }
    precondition(status == noErr, "Rendering failed: \(status)")
    return (0..<2).map { Array(UnsafeBufferPointer(start: buffer.floatChannelData![$0], count: blockSize)) }
}

for blockSize in [64, 128, 512] {
    let unit = try makeUnit(blockSize: UInt32(blockSize))
    var peaks = [[Int]](repeating: [], count: 2)
    for block in 0..<32 {
        let output = render(unit, blockSize: blockSize, block: block, impulse: block == 0)
        for channel in 0..<2 {
            for frame in 0..<blockSize where abs(output[channel][frame]) > 0.1 {
                peaks[channel].append(block * blockSize + frame)
            }
        }
    }
    precondition(peaks == [[576], [576]], "12 ms stereo delay, block \(blockSize): \(peaks)")
    unit.deallocateRenderResources()
    // Resource lifecycle must tolerate allocation with a different buffer capacity.
    unit.maximumFramesToRender = 1024
    try unit.allocateRenderResources()
    unit.deallocateRenderResources()
}

let unit = try makeUnit(blockSize: 128)
_ = render(unit, blockSize: 128, block: 0, impulse: true)
unit.isEnabled = false
for block in 1..<40 { _ = render(unit, blockSize: 128, block: block, impulse: false) }
unit.isEnabled = true
for block in 40..<72 {
    let output = render(unit, blockSize: 128, block: block, impulse: false)
    precondition(output.joined().allSatisfy { abs($0) < 0.00001 }, "Bypass restored stale audio")
}
unit.deallocateRenderResources()
print("Хорус: задержка 12 мс на обоих каналах, 3 размера блока, ресурсы и bypass — OK")
