import AVFoundation
import Foundation
import Testing
@testable import PianoRoom

@MainActor
struct GrandPianoTests {
    @Test func salamanderSurvivesEngineRestart() throws {
        let engine = AVAudioEngine()
        let sampler = AVAudioUnitSampler()
        let gmSynth = AudioEngine.makeGMInstrument()
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        engine.attach(sampler)
        engine.attach(gmSynth)
        engine.connect(sampler, to: engine.mainMixerNode, format: format)
        engine.connect(gmSynth, to: engine.mainMixerNode, fromBus: 0, toBus: 1, format: format)
        let bank = try #require(Bundle.main.url(forResource: "Salamander", withExtension: "sf2"))
        try sampler.loadSoundBankInstrument(at: bank, program: 0,
            bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB), bankLSB: 0)
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 512)
        defer { engine.stop() }

        func note() throws -> [Float] {
            sampler.startNote(60, withVelocity: 90, onChannel: 0)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512)!
            var samples: [Float] = []
            for _ in 0..<24 {
                let status = try engine.renderOffline(512, to: buffer)
                #expect(status == .success)
                samples.append(contentsOf: UnsafeBufferPointer(start: buffer.floatChannelData![0],
                                                               count: Int(buffer.frameLength)))
            }
            sampler.sendController(120, withValue: 0, onChannel: 0)
            return samples
        }

        try AudioEngine.startEngine(engine, grandSampler: sampler, bankURL: bank, gmSynth: gmSynth, gmProgram: 0)
        let original = try note()
        let energy = original.reduce(0.0) { $0 + Double($1) * Double($1) }
        #expect(energy > 0.01)

        // Both restarting a running engine and restarting one stopped by CoreAudio
        // must restore the recorded piano, rather than the sampler's default tone.
        for stoppedExternally in [false, true] {
            if stoppedExternally { engine.stop() }
            try AudioEngine.startEngine(engine, grandSampler: sampler, bankURL: bank, gmSynth: gmSynth, gmProgram: 0)
            let restored = try note()
            let difference = zip(original, restored).reduce(0.0) { $0 + abs(Double($1.0 - $1.1)) }
            #expect(difference / Double(original.count) < 0.00001,
                    "Restart must preserve the Salamander waveform, not merely produce sound")
        }
    }

    @Test func selectedGMProgramSurvivesEngineRestart() throws {
        let engine = AVAudioEngine()
        let sampler = AVAudioUnitSampler()
        let gmSynth = AudioEngine.makeGMInstrument()
        let silentGrand = AVAudioMixerNode()
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        engine.attach(sampler)
        engine.attach(gmSynth)
        engine.attach(silentGrand)
        engine.connect(sampler, to: silentGrand, format: format)
        engine.connect(silentGrand, to: engine.mainMixerNode, fromBus: 0, toBus: 0, format: format)
        engine.connect(gmSynth, to: engine.mainMixerNode, fromBus: 0, toBus: 1, format: format)
        silentGrand.outputVolume = 0
        let bank = try #require(Bundle.main.url(forResource: "Salamander", withExtension: "sf2"))
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 512)
        defer { engine.stop() }

        func note() throws -> [Float] {
            gmSynth.startNote(60, withVelocity: 90, onChannel: 0)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512)!
            var samples: [Float] = []
            for _ in 0..<24 {
                let status = try engine.renderOffline(512, to: buffer)
                #expect(status == .success)
                samples.append(contentsOf: UnsafeBufferPointer(start: buffer.floatChannelData![0],
                                                               count: Int(buffer.frameLength)))
            }
            gmSynth.sendController(120, withValue: 0, onChannel: 0)
            return samples
        }

        try AudioEngine.startEngine(engine, grandSampler: sampler, bankURL: bank,
                                    gmSynth: gmSynth, gmProgram: 16)
        // Select an organ explicitly for the independent reference.
        gmSynth.sendProgramChange(16, bankMSB: 0, bankLSB: 0, onChannel: 0)
        let organ = try note()
        engine.stop()
        try AudioEngine.startEngine(engine, grandSampler: sampler, bankURL: bank,
                                    gmSynth: gmSynth, gmProgram: 16)
        let restored = try note()
        let difference = zip(organ, restored).reduce(0.0) { $0 + abs(Double($1.0 - $1.1)) }
        #expect(difference / Double(organ.count) < 0.00001,
                "Restart must preserve the selected organ rather than reset to GM piano")
    }

}
