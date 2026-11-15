import AVFoundation
import Testing
@testable import PianoRoom

@MainActor
struct AudioStartupTests {
    @Test func gmStartsAndRestartsWithoutPianoBank() throws {
        let engine = AVAudioEngine()
        let sampler = AVAudioUnitSampler()
        let gm = AudioEngine.makeGMInstrument()
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        engine.attach(sampler)
        engine.attach(gm)
        engine.connect(gm, to: engine.mainMixerNode, format: format)
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 512)
        defer { engine.stop() }
        func render() throws -> [Float] {
            gm.startNote(60, withVelocity: 90, onChannel: 0)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512)!
            var result: [Float] = []
            for _ in 0..<24 {
                #expect(try engine.renderOffline(512, to: buffer) == .success)
                result.append(contentsOf: UnsafeBufferPointer(start: buffer.floatChannelData![0], count: 512))
            }
            gm.sendController(120, withValue: 0, onChannel: 0)
            return result
        }
        try AudioEngine.startEngine(engine, grandSampler: sampler, bankURL: nil, gmSynth: gm, gmProgram: 16)
        let original = try render()
        #expect(original.reduce(0.0) { $0 + Double($1 * $1) } > 0.01)
        engine.stop()
        try AudioEngine.startEngine(engine, grandSampler: sampler, bankURL: nil, gmSynth: gm, gmProgram: 16)
        let restored = try render()
        #expect(zip(original, restored).allSatisfy { abs($0 - $1) < 0.00001 })
    }
}
