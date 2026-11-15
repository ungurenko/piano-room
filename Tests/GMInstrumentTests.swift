import AVFoundation
import Testing
@testable import PianoRoom

@MainActor
struct GMInstrumentTests {
    private func render(program: UInt8) throws -> [Float] {
        let engine = AVAudioEngine()
        let synth = AudioEngine.makeGMInstrument()
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        engine.attach(synth)
        engine.connect(synth, to: engine.mainMixerNode, format: format)
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 512)
        try engine.start()
        defer { engine.stop() }
        synth.sendProgramChange(program, bankMSB: 0, bankLSB: 0, onChannel: 0)
        synth.startNote(60, withVelocity: 90, onChannel: 0)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512)!
        var samples: [Float] = []
        for _ in 0..<24 {
            let status = try engine.renderOffline(512, to: buffer)
            #expect(status == .success)
            samples.append(contentsOf: UnsafeBufferPointer(start: buffer.floatChannelData![0],
                                                           count: Int(buffer.frameLength)))
        }
        return samples
    }

    @Test func everyGMProgramProducesFiniteAudio() throws {
        for program: UInt8 in 0..<128 {
            let samples = try render(program: program)
            let finite = samples.allSatisfy { $0.isFinite }
            let energy = samples.reduce(0.0) { $0 + Double($1) * Double($1) }
            #expect(finite, "GM program must produce finite audio")
            #expect(energy > 1e-8, "GM program must produce audible samples")
        }
    }

    @Test func favoriteGMTimbresProduceDifferentAudio() throws {
        let programs: [UInt8] = [0, 4, 16, 48, 89]
        let audio = try programs.map { try render(program: $0) }
        for samples in audio {
            let finite = samples.allSatisfy { $0.isFinite }
            #expect(finite)
            let energy = samples.reduce(0.0) { $0 + Double($1) * Double($1) }
            #expect(energy > 0.01)
        }
        for a in audio.indices {
            for b in audio.indices where b > a {
                let difference = zip(audio[a], audio[b]).reduce(0.0) { $0 + abs(Double($1.0 - $1.1)) }
                #expect(difference / Double(audio[a].count) > 0.001,
                        "Different GM instruments must produce different audio")
            }
        }
    }
}
