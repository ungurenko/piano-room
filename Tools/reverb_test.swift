// Offline tests exercise the public Audio Unit render interface, without audio hardware.
import AVFoundation
import Foundation

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        FileHandle.standardError.write(Data("Проверка реверба не пройдена: \(message)\n".utf8))
        exit(1)
    }
}

private final class ReverbHarness {
    let unit: ReverbUnit
    var cursor = 0
    var renderTimes: [UInt64] = []

    init(rate: Double = 48_000, blockSize: UInt32 = 128,
         parameters: ReverbParameters = .default, mix: Float = 1, enabled: Bool = true) throws {
        let description = AudioComponentDescription(componentType: kAudioUnitType_Effect,
            componentSubType: 0x72767262, componentManufacturer: 0x50526d73,
            componentFlags: 0, componentFlagsMask: 0)
        unit = try ReverbUnit(componentDescription: description)
        unit.apply(parameters: parameters, mix: mix, enabled: enabled)
        try configure(rate: rate, blockSize: blockSize)
    }

    deinit { unit.deallocateRenderResources() }

    var rate: Double { unit.outputBusses[0].format.sampleRate }

    func configure(rate: Double, blockSize: UInt32) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)!
        unit.maximumFramesToRender = blockSize
        try unit.inputBusses[0].setFormat(format)
        try unit.outputBusses[0].setFormat(format)
        try unit.allocateRenderResources()
        cursor = 0
    }

    func render(frames: Int? = nil, nilOutput: Bool = false,
                input: @escaping (Int, Int) -> Float = { _, _ in 0 }) -> [[Float]] {
        let count = frames ?? Int(unit.maximumFramesToRender)
        let buffer = AVAudioPCMBuffer(pcmFormat: unit.outputBusses[0].format,
                                     frameCapacity: UInt32(count))!
        buffer.frameLength = UInt32(count)
        let list = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        let ownedPointers = list.map(\.mData)
        if nilOutput {
            for channel in 0..<list.count { list[channel].mData = nil }
        }
        defer {
            for channel in 0..<list.count { list[channel].mData = ownedPointers[channel] }
        }
        var flags = AudioUnitRenderActionFlags()
        var timestamp = AudioTimeStamp()
        timestamp.mSampleTime = Double(cursor)
        timestamp.mFlags = .sampleTimeValid
        let start = DispatchTime.now().uptimeNanoseconds
        let status = unit.internalRenderBlock(&flags, &timestamp, UInt32(count), 0,
                                              buffer.mutableAudioBufferList, nil) { _, _, frames, _, data in
            for (channel, item) in UnsafeMutableAudioBufferListPointer(data).enumerated() {
                guard let samples = item.mData?.assumingMemoryBound(to: Float.self) else {
                    return kAudioUnitErr_Uninitialized
                }
                for frame in 0..<Int(frames) { samples[frame] = input(frame, channel) }
            }
            return noErr
        }
        renderTimes.append(DispatchTime.now().uptimeNanoseconds - start)
        require(status == noErr, "Рендер завершился ошибкой \(status)")
        cursor += count
        return list.map { item in
            require(item.mData != nil, "AU не предоставил выходную память")
            return Array(UnsafeBufferPointer(start: item.mData!.assumingMemoryBound(to: Float.self), count: count))
        }
    }

    func silence(seconds: Double) {
        let blocks = Int(ceil(seconds * rate / Double(unit.maximumFramesToRender)))
        for _ in 0..<blocks { _ = render() }
    }
}

@main
private struct ReverbTests {
    static func main() throws {
        var measurements: [(Double, UInt32, Double, Double)] = []
        for rate in [44_100.0, 48_000, 96_000] {
            for blockSize: UInt32 in [64, 128, 256, 512] {
                let harness = try ReverbHarness(rate: rate, blockSize: blockSize)
                harness.silence(seconds: 0.4)
                var energy = [Double](repeating: 0, count: 2)
                var earlyEnergy = 0.0
                var lateEnergy = 0.0
                var difference = 0.0
                let length = Int(rate * 3.0)
                var offset = 0
                while offset < length {
                    let count = min(Int(blockSize), length - offset)
                    let initial = offset == 0
                    let output = harness.render(frames: count, nilOutput: initial) { frame, channel in
                        initial && frame == 0 && channel == 0 ? 1 : 0
                    }
                    for frame in 0..<count {
                        let seconds = Double(offset + frame) / rate
                        for channel in 0..<2 {
                            let sample = output[channel][frame]
                            require(sample.isFinite, "Неконечное значение: \(rate)/\(blockSize)")
                            let square = Double(sample) * Double(sample)
                            energy[channel] += square
                            if seconds >= 0.08 && seconds < 0.6 { earlyEnergy += square }
                            if seconds >= 2.4 { lateEnergy += square }
                        }
                        difference += abs(Double(output[0][frame] - output[1][frame]))
                    }
                    offset += count
                }
                require(energy.allSatisfy { $0 > 1e-8 }, "Импульс не создал хвост на обоих каналах")
                require(difference > 1e-5, "Стереохвост совпал на обоих каналах")
                require(earlyEnergy > 1e-8 && lateEnergy < earlyEnergy * 0.2,
                        "Хвост не затухает: ранняя энергия \(earlyEnergy), поздняя \(lateEnergy)")
                let sorted = harness.renderTimes.sorted()
                let p99 = Double(sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.99))]) / 1_000
                let maximum = Double(sorted.last!) / 1_000
                measurements.append((rate, blockSize, p99, maximum))
            }
        }
        print("Импульс, стерео, затухание и выход без предоставленной памяти: 12 сочетаний — OK")

        let dry = try ReverbHarness(mix: 0)
        dry.silence(seconds: 0.8)
        let expected: (Int, Int) -> Float = { frame, channel in
            Float(sin(Double(frame) * 0.13 + Double(channel))) * 0.2
        }
        let dryOutput = dry.render(input: expected)
        for channel in 0..<2 {
            for frame in 0..<128 {
                require(abs(dryOutput[channel][frame] - expected(frame, channel)) < 1e-6,
                        "Нулевая сила изменила прямой звук")
            }
        }
        let bypass = try ReverbHarness(mix: 1, enabled: false)
        bypass.silence(seconds: 0.8)
        let bypassOutput = bypass.render(input: expected)
        for channel in 0..<2 {
            for frame in 0..<128 {
                require(abs(bypassOutput[channel][frame] - expected(frame, channel)) < 1e-6,
                        "Выключенный реверб изменил прямой звук")
            }
        }
        bypass.unit.apply(parameters: .default, mix: 1, enabled: true)
        bypass.silence(seconds: 0.8)
        let noRecordedBypass = bypass.render()
        require(noRecordedBypass.joined().allSatisfy { abs($0) < 1e-7 },
                "При включении вернулись ноты, сыгранные с выключенным ревербом")
        print("Нулевая сила, прямой звук и повторное включение — OK")

        let reset = try ReverbHarness()
        reset.silence(seconds: 0.4)
        _ = reset.render { frame, _ in frame == 0 ? 1 : 0 }
        reset.silence(seconds: 0.15)
        reset.unit.reset()
        for _ in 0..<100 {
            require(reset.render().joined().allSatisfy { abs($0) < 1e-7 },
                    "Сброс AU сохранил остаток прежнего хвоста")
        }
        reset.unit.deallocateRenderResources()
        try reset.configure(rate: 96_000, blockSize: 512)
        reset.silence(seconds: 0.4)
        require(reset.render(nilOutput: true).joined().allSatisfy { $0 == 0 },
                "Повторное выделение ресурсов вернуло старый хвост")
        print("Сброс хвоста и повторное выделение ресурсов с другим форматом — OK")

        var pulled = false
        var flags = AudioUnitRenderActionFlags()
        var timestamp = AudioTimeStamp()
        let oversized = AVAudioPCMBuffer(pcmFormat: dry.unit.outputBusses[0].format, frameCapacity: 256)!
        let status = dry.unit.internalRenderBlock(&flags, &timestamp, 256, 0,
                                                  oversized.mutableAudioBufferList, nil) { _, _, _, _, _ in
            pulled = true
            return noErr
        }
        require(status == kAudioUnitErr_TooManyFramesToProcess && !pulled,
                "Слишком большой блок не был отклонён до чтения входа")
        print("Блок больше разрешённого отклонён до чтения входа — OK")
        for (rate, block, p99, maximum) in measurements {
            let deadline = Double(block) / rate * 1_000_000
            print(String(format: "%.1f кГц / %d кадров: p99 %.1f мкс, максимум %.1f мкс, срок %.1f мкс",
                         rate / 1_000, block, p99, maximum, deadline))
        }
        print("Офлайн-проверки реверба пройдены. Проверка на слух не выполнялась.")
    }
}
