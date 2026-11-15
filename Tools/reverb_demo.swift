// Render one piano performance once, then reuse it for every reverb comparison.
import AVFoundation
import Foundation

private struct UnitTransfer: @unchecked Sendable { let unit: AVAudioUnit }
private struct DemoError: Error, CustomStringConvertible { let description: String }
private enum PianoAction {
    case noteOn(UInt8, UInt8)
    case noteOff(UInt8)
    case pedal(UInt8)
}
private struct PianoEvent { let frame: Int; let action: PianoAction }

@main
@MainActor
private struct ReverbDemo {
    private static let rate = 48_000.0
    private static let length = 12.0
    private static let blockSize: AVAudioFrameCount = 512
    private static let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)!

    @MainActor
    static func main() async throws {
        let bank = URL(fileURLWithPath: "Resources/SoundBanks/Salamander.sf2")
        guard FileManager.default.fileExists(atPath: bank.path) else {
            throw DemoError(description: "Не найден Resources/SoundBanks/Salamander.sf2")
        }
        let directory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "output/reverb-demo")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let dry = try renderPiano(bank: bank)
        let old = try process(dry, effect: makeAppleReverb())
        let newUnit = try await makeNewReverb()
        guard let reverb = newUnit.auAudioUnit as? ReverbUnit else {
            throw DemoError(description: "Создан неправильный Audio Unit")
        }
        reverb.apply(parameters: .default, mix: 0.35, enabled: true)
        let new = try process(dry, effect: newUnit)
        var variants = [("01-dry.wav", dry), ("02-apple-large-hall.wav", old), ("03-new-chamber.wav", new)]

        // Match RMS during the played phrase. A shared final trim keeps every file below clipping.
        let gains = variants.map { _, channels -> Double in
            let start = Int(rate * 0.25), end = Int(rate * 6.5)
            var energy = 0.0
            for channel in channels {
                for sample in channel[start..<end] { energy += Double(sample) * Double(sample) }
            }
            let rms = sqrt(energy / Double((end - start) * 2))
            return rms > 0 ? 0.1 / rms : 1
        }
        var largestPeak = 0.0
        for index in variants.indices {
            for channel in variants[index].1 {
                for sample in channel { largestPeak = max(largestPeak, abs(Double(sample)) * gains[index]) }
            }
        }
        let safety = largestPeak > 0.95 ? 0.95 / largestPeak : 1
        for index in variants.indices {
            let gain = Float(gains[index] * safety)
            for channel in 0..<2 {
                for frame in variants[index].1[channel].indices { variants[index].1[channel][frame] *= gain }
            }
            let url = directory.appendingPathComponent(variants[index].0)
            try write(variants[index].1, to: url)
            print(String(format: "%@ — 12 с, 48 кГц, стерео; поправка громкости %.2f дБ",
                         url.path, 20 * log10(Double(gain))))
        }
        print("Исходное исполнение одинаково во всех файлах. Громкость выровнена по RMS. Прослушивание человеком не выполнялось.")
    }

    private static func events() -> [PianoEvent] {
        var result: [PianoEvent] = []
        func add(_ seconds: Double, _ action: PianoAction) {
            result.append(PianoEvent(frame: Int((seconds * rate).rounded()), action: action))
        }
        // Short low notes reveal muddy lows; sustained chords reveal the tail; arpeggios reveal attack clarity.
        for (time, note) in [(0.25, UInt8(36)), (0.65, UInt8(43)), (1.05, UInt8(48))] {
            add(time, .noteOn(note, 92)); add(time + 0.18, .noteOff(note))
        }
        add(1.5, .pedal(127))
        for note: UInt8 in [48, 55, 60, 64, 67] {
            add(1.5, .noteOn(note, 82)); add(2.1, .noteOff(note))
        }
        add(2.75, .pedal(0))
        for (index, note) in [60, 64, 67, 72, 76, 79, 76, 72, 67, 64, 60, 55].enumerated() {
            let time = 3.15 + Double(index) * 0.14
            add(time, .noteOn(UInt8(note), UInt8(72 + index % 4 * 6)))
            add(time + 0.11, .noteOff(UInt8(note)))
        }
        add(5.15, .pedal(127))
        for note: UInt8 in [41, 48, 53, 57, 60, 65] {
            add(5.15, .noteOn(note, 88)); add(5.8, .noteOff(note))
        }
        add(6.5, .pedal(0))
        return result.sorted { $0.frame < $1.frame }
    }

    private static func renderPiano(bank: URL) throws -> [[Float]] {
        let engine = AVAudioEngine()
        let sampler = AVAudioUnitSampler()
        engine.attach(sampler)
        engine.connect(sampler, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.6
        do {
            try sampler.loadSoundBankInstrument(at: bank, program: 0,
                bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB), bankLSB: UInt8(kAUSampler_DefaultBankLSB))
        } catch {
            try sampler.loadSoundBankInstrument(at: bank, program: 0, bankMSB: 0, bankLSB: 0)
        }
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: blockSize)
        try engine.start()
        defer { engine.stop(); engine.disableManualRenderingMode() }
        let score = events()
        var nextEvent = 0
        return try render(engine) { cursor in
            while nextEvent < score.count && score[nextEvent].frame <= cursor {
                switch score[nextEvent].action {
                case .noteOn(let note, let velocity): sampler.startNote(note, withVelocity: velocity, onChannel: 0)
                case .noteOff(let note): sampler.stopNote(note, onChannel: 0)
                case .pedal(let value): sampler.sendController(64, withValue: value, onChannel: 0)
                }
                nextEvent += 1
            }
            return nextEvent < score.count ? score[nextEvent].frame - cursor : Int(blockSize)
        }
    }

    private static func makeAppleReverb() -> AVAudioUnitReverb {
        let reverb = AVAudioUnitReverb()
        reverb.loadFactoryPreset(.largeHall2)
        reverb.wetDryMix = 35
        return reverb
    }

    @MainActor
    private static func makeNewReverb() async throws -> AVAudioUnit {
        let description = AudioComponentDescription(componentType: kAudioUnitType_Effect,
            componentSubType: 0x72767262, componentManufacturer: 0x50526d73,
            componentFlags: 0, componentFlagsMask: 0)
        AUAudioUnit.registerSubclass(ReverbUnit.self, as: description, name: "Piano Room Reverb", version: 1)
        let transfer: UnitTransfer = try await withCheckedThrowingContinuation { continuation in
            AVAudioUnit.instantiate(with: description, options: []) { unit, error in
                if let unit { continuation.resume(returning: UnitTransfer(unit: unit)) }
                else { continuation.resume(throwing: error ?? DemoError(description: "Не удалось создать реверб")) }
            }
        }
        return transfer.unit
    }

    private static func process(_ input: [[Float]], effect: AVAudioUnit) throws -> [[Float]] {
        let source = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(input[0].count))!
        source.frameLength = source.frameCapacity
        for channel in 0..<2 {
            input[channel].withUnsafeBufferPointer {
                source.floatChannelData![channel].update(from: $0.baseAddress!, count: $0.count)
            }
        }
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.attach(effect)
        engine.connect(player, to: effect, format: format)
        engine.connect(effect, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 1
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: blockSize)
        player.scheduleBuffer(source)
        try engine.start()
        player.play()
        defer { player.stop(); engine.stop(); engine.disableManualRenderingMode() }
        return try render(engine) { _ in Int(blockSize) }
    }

    private static func render(_ engine: AVAudioEngine, beforeBlock: (Int) -> Int) throws -> [[Float]] {
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: blockSize)!
        let totalFrames = Int(rate * length)
        var output = [[Float]](repeating: [], count: 2)
        output[0].reserveCapacity(totalFrames); output[1].reserveCapacity(totalFrames)
        var cursor = 0
        var retries = 0
        while cursor < totalFrames {
            let next = beforeBlock(cursor)
            let count = min(Int(blockSize), min(totalFrames - cursor, max(1, next)))
            let status = try engine.renderOffline(AVAudioFrameCount(count), to: buffer)
            switch status {
            case .success:
                guard Int(buffer.frameLength) == count, let data = buffer.floatChannelData else {
                    throw DemoError(description: "Звуковой движок вернул неполный блок")
                }
                for channel in 0..<2 {
                    output[channel].append(contentsOf: UnsafeBufferPointer(start: data[channel], count: count))
                }
                cursor += count
                retries = 0
            case .cannotDoInCurrentContext:
                retries += 1
                if retries > 100 { throw DemoError(description: "Звуковой движок не готов к офлайн-рендеру") }
            case .insufficientDataFromInputNode, .error:
                throw DemoError(description: "Не удалось обработать звуковой блок: \(status.rawValue)")
            @unknown default:
                throw DemoError(description: "Неизвестный результат офлайн-рендера")
            }
        }
        return output
    }

    private static func write(_ samples: [[Float]], to url: URL) throws {
        guard samples.count == 2, samples[0].count == samples[1].count,
              samples.joined().allSatisfy({ $0.isFinite }) else {
            throw DemoError(description: "В сравнении обнаружены некорректные звуковые данные")
        }
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples[0].count))!
        buffer.frameLength = buffer.frameCapacity
        for channel in 0..<2 {
            samples[channel].withUnsafeBufferPointer {
                buffer.floatChannelData![channel].update(from: $0.baseAddress!, count: $0.count)
            }
        }
        var fileSettings = format.settings
        fileSettings[AVLinearPCMIsNonInterleaved] = false
        let file = try AVAudioFile(forWriting: url, settings: fileSettings,
                                  commonFormat: .pcmFormatFloat32, interleaved: false)
        try file.write(from: buffer)
    }
}
