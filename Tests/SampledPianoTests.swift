import AVFoundation
import Testing
@testable import PianoRoom

@MainActor
struct SampledPianoTests {
    @Test func recordedLibrariesSurviveSourceNodeRestart() throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        var signatures: [[Float]] = []
        for name in ["Osiris", "Headroom"] {
            let engine = AVAudioEngine()
            let piano = SampledPianoPlayer()
            engine.attach(piano.node)
            engine.connect(piano.node, to: engine.mainMixerNode, format: format)
            try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 512)
            let url = Bundle.main.resourceURL!.appendingPathComponent("Instruments/\(name)/Instrument.sfz")
            try piano.load(at: url, name: name)
            defer { engine.stop() }
            func note(_ velocity: UInt8) throws -> [Float] {
                piano.send(0x90, 60, velocity)
                let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512)!
                var result: [Float] = []
                for _ in 0..<32 {
                    #expect(try engine.renderOffline(512, to: buffer) == .success)
                    result.append(contentsOf: UnsafeBufferPointer(start: buffer.floatChannelData![0], count: 512))
                }
                #expect(result.allSatisfy { $0.isFinite })
                #expect(result.reduce(0.0) { $0 + Double($1 * $1) } > 0.01)
                return result
            }
            try engine.start()
            let reference = try note(90)
            signatures.append(reference)
            engine.stop()
            piano.reset()
            try engine.start()
            let restored = try note(90)
            #expect(zip(reference, restored).allSatisfy { abs($0 - $1) < 0.00001 })
            engine.stop()
            piano.reset()
            do {
                try piano.load(at: url.deletingLastPathComponent().appendingPathComponent("missing.sfz"), name: name)
                Issue.record("Missing library must fail")
            } catch { }
            try engine.start()
            let retained = try note(90)
            #expect(zip(reference, retained).allSatisfy { abs($0 - $1) < 0.00001 })
            engine.stop()
            piano.reset()
            try engine.start()
            let quiet = try note(30)
            #expect(zip(reference, quiet).reduce(0.0) { $0 + abs(Double($1.0 - $1.1)) } > 1)
        }
        #expect(zip(signatures[0], signatures[1]).reduce(0.0) { $0 + abs(Double($1.0 - $1.1)) } > 1)
    }

    @Test func fuchsNativeBankSurvivesRestart() throws {
        let engine = AVAudioEngine()
        let sampler = AVAudioUnitSampler()
        let gm = AudioEngine.makeGMInstrument()
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        engine.attach(sampler)
        engine.attach(gm)
        engine.connect(sampler, to: engine.mainMixerNode, format: format)
        let bank = Bundle.main.resourceURL!.appendingPathComponent("Instruments/Fuchs/Instrument.sf2")
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 512)
        defer { engine.stop() }
        func note() throws -> [Float] {
            sampler.startNote(60, withVelocity: 90, onChannel: 0)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512)!
            var result: [Float] = []
            for _ in 0..<32 {
                #expect(try engine.renderOffline(512, to: buffer) == .success)
                result.append(contentsOf: UnsafeBufferPointer(start: buffer.floatChannelData![0], count: 512))
            }
            return result
        }
        try AudioEngine.startEngine(engine, grandSampler: sampler, bankURL: bank, gmSynth: gm, gmProgram: 0)
        let reference = try note()
        #expect(reference.reduce(0.0) { $0 + Double($1 * $1) } > 0.01)
        try AudioEngine.startEngine(engine, grandSampler: sampler, bankURL: bank, gmSynth: gm, gmProgram: 0)
        let restored = try note()
        #expect(zip(reference, restored).allSatisfy { abs($0 - $1) < 0.00001 })
    }
}
