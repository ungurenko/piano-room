import AVFoundation
import AudioToolbox
import Foundation
import os

private let logger = Logger(subsystem: "com.alexpianoroom.PianoRoom", category: "audio")

/// Звуковой движок приложения.
///
/// Два источника звука:
/// 1. `AVAudioUnitSampler` с банком Salamander — качественный рояль.
/// 2. `AVAudioUnitMIDIInstrument` (AUMIDISynth) — 128 инструментов General MIDI.
///
/// Оба идут в общую цепочку эффектов: эквалайзер → перегруз → хорус → дилей →
/// реверберация → общий микшер. Переключение источника мгновенное (микшером),
/// поэтому не нужно перезагружать банки во время игры.
final class AudioEngine {

    enum EngineError: LocalizedError {
        case noSoundBank
        case soundBankLoadFailed(String)
        case engineStartFailed(String)
        case midiSynthUnavailable
        case chorusUnavailable

        var errorDescription: String? {
            switch self {
            case .noSoundBank:
                return "Не найден банк рояля (Salamander.sf2) в приложении."
            case .soundBankLoadFailed(let message):
                return "Не удалось загрузить рояль: \(message)"
            case .engineStartFailed(let message):
                return "Не удалось запустить звук: \(message)"
            case .midiSynthUnavailable:
                return "Системный GM-синтезатор недоступен."
            case .chorusUnavailable:
                return "Не удалось создать эффект хоруса."
            }
        }
    }

    // MARK: - Узлы

    private let engine = AVAudioEngine()
    private let grandSampler = AVAudioUnitSampler()
    private let gmSynth: AVAudioUnitMIDIInstrument
    private let grandMixer = AVAudioMixerNode()
    private let gmMixer = AVAudioMixerNode()
    private let preMixer = AVAudioMixerNode()
    private let masterMixer = AVAudioMixerNode()
    private let equalizer = AVAudioUnitEQ(numberOfBands: 2)
    private let distortion = AVAudioUnitDistortion()
    private let delay = AVAudioUnitDelay()
    private let reverb = AVAudioUnitReverb()
    private var chorusUnit: AVAudioUnit?
    private var chorus: ChorusUnit?

    private let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
    private var graphBuilt = false
    private var levelTapInstalled = false
    private var tapCalls = 0
    private var bufferFrameSize: UInt32 = 128
    private var configurationObserver: NSObjectProtocol?

    // MARK: - Состояние

    private(set) var isRunning = false
    private(set) var isReady = false
    private(set) var currentInstrument: Instrument = InstrumentCatalog.grandPiano
    private(set) var outputDeviceID: AudioDeviceID?
    private(set) var outputDeviceName: String = "Системный вывод"

    // MARK: - Подготовка

    /// Собрать граф, загрузить банк и запустить двигатель.
    func prepare(
        outputDeviceID: AudioDeviceID?,
        outputDeviceName: String,
        bufferFrames: UInt32,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                self.outputDeviceName = outputDeviceName
                self.bufferFrameSize = bufferFrames
                // Устройство выбираем ДО сборки графа: иначе outputNode остаётся
                // привязанным к старому устройству и рендер на новом не идёт.
                try self.configureOutputDevice(deviceID: outputDeviceID, bufferFrames: bufferFrames)
                try self.buildGraphIfNeeded()
                try self.loadGrandPiano()
                try self.startEngineNow()
                self.isReady = true
                self.applyAllEffectSettings(EffectSettings.default)
                DispatchQueue.main.async { completion(.success(())) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    private func buildGraphIfNeeded() throws {
        guard !graphBuilt else { return }

        engine.attach(grandSampler)
        engine.attach(gmSynth)
        engine.attach(grandMixer)
        engine.attach(gmMixer)
        engine.attach(preMixer)
        engine.attach(masterMixer)
        engine.attach(equalizer)
        engine.attach(distortion)
        engine.attach(delay)
        engine.attach(reverb)

        engine.connect(grandSampler, to: grandMixer, format: format)
        engine.connect(gmSynth, to: gmMixer, format: format)
        engine.connect(grandMixer, to: preMixer, fromBus: 0, toBus: 0, format: format)
        engine.connect(gmMixer, to: preMixer, fromBus: 0, toBus: 1, format: format)
        engine.connect(preMixer, to: equalizer, format: format)
        engine.connect(equalizer, to: distortion, format: format)

        // Хорус собирается отдельно: если системный AU не поднялся, идём напрямую.
        let chorusResult = makeChorus()
        let afterDistortion: AVAudioNode
        if let (unit, chorusAU) = chorusResult {
            engine.attach(unit)
            engine.connect(distortion, to: unit, format: format)
            chorusUnit = unit
            chorus = chorusAU
            afterDistortion = unit
        } else {
            afterDistortion = distortion
        }

        engine.connect(afterDistortion, to: delay, format: format)
        engine.connect(delay, to: reverb, format: format)
        engine.connect(reverb, to: masterMixer, format: format)
        // Явно соединяем мастер-микшер с выходом: автоматическое подключение
        // mainMixerNode на этой macOS не срабатывает, и звук не рендерится.
        engine.connect(masterMixer, to: engine.outputNode, format: format)

        configureEffects()
        graphBuilt = true
    }

    private func makeChorus() -> (AVAudioUnit, ChorusUnit)? {
        let description = AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: Self.fourCharCode("chrs"),
            componentManufacturer: Self.fourCharCode("PRms"),
            componentFlags: 0,
            componentFlagsMask: 0
        )

        AUAudioUnit.registerSubclass(
            ChorusUnit.self,
            as: description,
            name: "Piano Room Chorus",
            version: 1
        )

        let semaphore = DispatchSemaphore(value: 0)
        var result: AVAudioUnit?
        AVAudioUnit.instantiate(with: description, options: []) { unit, _ in
            result = unit
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 3)

        guard let unit = result, let au = unit.auAudioUnit as? ChorusUnit else {
            logger.error("Хорус не создан, работаем без него")
            return nil
        }
        logger.info("Хорус создан")
        return (unit, au)
    }

    private func loadGrandPiano() throws {
        let candidates = Bundle.main.urls(forResourcesWithExtension: "sf2", subdirectory: nil)
            ?? Bundle.main.urls(forResourcesWithExtension: "sf2", subdirectory: "SoundBanks")
        guard let url = candidates?.first else {
            logger.error("Банк рояля не найден в приложении")
            throw EngineError.noSoundBank
        }

        logger.info("Загружаем рояль: \(url.lastPathComponent, privacy: .public)")
        do {
            try grandSampler.loadSoundBankInstrument(
                at: url,
                program: 0,
                bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
                bankLSB: UInt8(kAUSampler_DefaultBankLSB)
            )
        } catch {
            // Некоторые SF2 собраны с банком 0 — пробуем и такой вариант.
            do {
                try grandSampler.loadSoundBankInstrument(at: url, program: 0, bankMSB: 0, bankLSB: 0)
            } catch {
                throw EngineError.soundBankLoadFailed(error.localizedDescription)
            }
        }
    }

    private func configureOutputDevice(deviceID: AudioDeviceID?, bufferFrames: UInt32) throws {
        if let deviceID {
            outputDeviceID = deviceID
            AudioDevices.setBufferFrameSize(bufferFrames, for: deviceID)
            do {
                // Официальный способ: AUAudioUnit сам пересогласует формат и запустит
                // устройство. Старый AudioUnitSetProperty на этой macOS оставлял
                // движок запущенным, но рендер не шёл.
                try engine.outputNode.auAudioUnit.setDeviceID(deviceID)
                logger.info("Выбрано аудиоустройство: \(self.outputDeviceName, privacy: .public)")
            } catch {
                throw EngineError.engineStartFailed("не удалось выбрать аудиовыход: \(error.localizedDescription)")
            }
        } else {
            outputDeviceID = AudioDevices.defaultOutputID()
            if let defaultID = outputDeviceID {
                AudioDevices.setBufferFrameSize(bufferFrames, for: defaultID)
            }
        }
    }

    private func startEngineNow() throws {
        if engine.isRunning { engine.stop() }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            throw EngineError.engineStartFailed(error.localizedDescription)
        }
        isRunning = true
        updateMixLevels()
        observeConfigurationChanges()
        // Измеритель уровня нужен только для диагностического запуска.
        if ProcessInfo.processInfo.arguments.contains("--test-note") {
            startLevelMonitor()
        }
        logger.info("Движок запущен, выход: \(self.outputDeviceName, privacy: .public), буфер: \(self.bufferFrameSize) кадров")
    }

    /// Смена аудиоконфигурации (подключили наушники, выдернули устройство) может
    /// остановить движок. Пытаемся поднять его заново, чтобы звук не пропал молча.
    private func observeConfigurationChanges() {
        guard configurationObserver == nil else { return }
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            self?.handleConfigurationChange()
        }
    }

    private func handleConfigurationChange() {
        guard isRunning else { return }
        logger.info("Изменилась конфигурация аудио: перезапускаем движок")
        engine.stop()
        do {
            try engine.start()
            isRunning = true
            logger.info("Движок перезапущен после смены конфигурации")
        } catch {
            isRunning = false
            logger.error("Не удалось перезапустить движок: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Диагностика: пишет в журнал пиковый уровень сигнала, чтобы видеть, доходит ли звук.
    private func startLevelMonitor() {
        guard levelTapInstalled == false else { return }
        levelTapInstalled = true
        masterMixer.installTap(onBus: 0, bufferSize: 2048, format: nil) { buffer, _ in
            self.tapCalls += 1
            guard let channels = buffer.floatChannelData else { return }
            let frames = Int(buffer.frameLength)
            guard frames > 0 else { return }
            var peak: Float = 0
            let channelCount = Int(buffer.format.channelCount)
            for channel in 0..<channelCount {
                let data = channels[channel]
                for frame in stride(from: 0, to: frames, by: 8) {
                    peak = max(peak, abs(data[frame]))
                }
            }
            if peak > 0.0008 {
                logger.info("Уровень сигнала: \(Double(peak), privacy: .public)")
            }
        }
    }

    /// Переключить аудиовыход без пересборки графа.
    func switchOutput(deviceID: AudioDeviceID?, deviceName: String, bufferFrames: UInt32) throws {
        outputDeviceName = deviceName
        if engine.isRunning {
            engine.stop()
            isRunning = false
        }
        try configureOutputDevice(deviceID: deviceID, bufferFrames: bufferFrames)
        try startEngineNow()
    }

    func stop() {
        guard engine.isRunning else { return }
        allNotesOff()
        engine.stop()
        isRunning = false
    }

    // MARK: - Инструменты

    func setInstrument(_ instrument: Instrument) {
        guard instrument.id != currentInstrument.id else { return }
        allNotesOff()
        currentInstrument = instrument

        if instrument.source == .gm, let program = instrument.gmProgram {
            gmSynth.sendProgramChange(UInt8(max(0, min(127, program))), bankMSB: 0, bankLSB: 0, onChannel: 0)
        }
        updateMixLevels()
    }

    private func updateMixLevels() {
        grandMixer.outputVolume = currentInstrument.source == .grandPiano ? 1 : 0
        gmMixer.outputVolume = currentInstrument.source == .gm ? 1 : 0
    }

    // MARK: - Ноты и контроллеры

    func noteOn(_ note: UInt8, velocity: UInt8) {
        switch currentInstrument.source {
        case .grandPiano:
            grandSampler.startNote(note, withVelocity: velocity, onChannel: 0)
        case .gm:
            gmSynth.startNote(note, withVelocity: velocity, onChannel: 0)
        }
    }

    func noteOff(_ note: UInt8) {
        switch currentInstrument.source {
        case .grandPiano:
            grandSampler.stopNote(note, onChannel: 0)
        case .gm:
            gmSynth.stopNote(note, onChannel: 0)
        }
    }

    func controlChange(_ controller: UInt8, value: UInt8) {
        switch currentInstrument.source {
        case .grandPiano:
            grandSampler.sendController(controller, withValue: value, onChannel: 0)
        case .gm:
            gmSynth.sendController(controller, withValue: value, onChannel: 0)
        }
    }

    func pitchBend(_ value: UInt16) {
        switch currentInstrument.source {
        case .grandPiano:
            grandSampler.sendPitchBend(value, onChannel: 0)
        case .gm:
            gmSynth.sendPitchBend(value, onChannel: 0)
        }
    }

    func channelPressure(_ value: UInt8) {
        switch currentInstrument.source {
        case .grandPiano:
            grandSampler.sendPressure(value, onChannel: 0)
        case .gm:
            gmSynth.sendPressure(value, onChannel: 0)
        }
    }

    func allNotesOff() {
        for channel in UInt8(0)..<UInt8(16) {
            grandSampler.sendController(123, withValue: 0, onChannel: channel)
            gmSynth.sendController(123, withValue: 0, onChannel: channel)
            grandSampler.sendController(120, withValue: 0, onChannel: channel)
            gmSynth.sendController(120, withValue: 0, onChannel: channel)
        }
    }

    // MARK: - Эффекты

    private func configureEffects() {
        equalizer.bands[0].filterType = .lowShelf
        equalizer.bands[0].frequency = 140
        equalizer.bands[0].bandwidth = 1.0
        equalizer.bands[0].gain = 0

        equalizer.bands[1].filterType = .highShelf
        equalizer.bands[1].frequency = 3_600
        equalizer.bands[1].bandwidth = 1.0
        equalizer.bands[1].gain = 0

        distortion.loadFactoryPreset(.multiDistortedCubed)
        distortion.wetDryMix = 0

        delay.delayTime = 0.28
        delay.feedback = 22
        delay.lowPassCutoff = 8_000
        delay.wetDryMix = 0

        reverb.loadFactoryPreset(.largeHall2)
        reverb.wetDryMix = 0
    }

    func applyAllEffectSettings(_ settings: EffectSettings) {
        guard graphBuilt else { return }
        setReverb(enabled: settings.reverbEnabled, amount: settings.reverb)
        setDelay(enabled: settings.delayEnabled, amount: settings.delay, time: settings.delayTime)
        setChorus(enabled: settings.chorusEnabled, amount: settings.chorus)
        setDrive(enabled: settings.driveEnabled, amount: settings.drive)
        setEqualizer(enabled: settings.eqEnabled, low: settings.eqLow, high: settings.eqHigh)
        setMasterVolume(settings.masterVolume)
    }

    func setReverb(enabled: Bool, amount: Float) {
        reverb.wetDryMix = enabled ? max(0, min(1, amount)) * 100 : 0
    }

    func setDelay(enabled: Bool, amount: Float, time: Float) {
        delay.wetDryMix = enabled ? max(0, min(1, amount)) * 100 : 0
        delay.delayTime = 0.08 + Double(max(0, min(1, time))) * 0.72
    }

    func setChorus(enabled: Bool, amount: Float) {
        guard let chorus else { return }
        chorus.isEnabled = enabled
        chorus.mix = max(0, min(1, amount))
    }

    func setDrive(enabled: Bool, amount: Float) {
        distortion.wetDryMix = enabled ? max(0, min(1, amount)) * 100 : 0
    }

    func setEqualizer(enabled: Bool, low: Float, high: Float) {
        equalizer.bands[0].bypass = !enabled
        equalizer.bands[1].bypass = !enabled
        equalizer.bands[0].gain = (max(0, min(1, low)) - 0.5) * 24
        equalizer.bands[1].gain = (max(0, min(1, high)) - 0.5) * 24
    }

    func setMasterVolume(_ volume: Float) {
        masterMixer.outputVolume = max(0, min(1, volume))
    }

    // MARK: - Утилиты

    private static func fourCharCode(_ string: String) -> FourCharCode {
        var result: FourCharCode = 0
        for scalar in string.unicodeScalars.prefix(4) {
            result = (result << 8) + FourCharCode(scalar.value)
        }
        return result
    }

    init() {
        let description = AudioComponentDescription(
            componentType: kAudioUnitType_MusicDevice,
            componentSubType: kAudioUnitSubType_MIDISynth,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        gmSynth = AVAudioUnitMIDIInstrument(audioComponentDescription: description)
    }
}

/// Значения эффектов, которые интерфейс передаёт движку.
struct EffectSettings {
    var reverb: Float = 0.35
    var reverbEnabled = true

    var delay: Float = 0.25
    var delayTime: Float = 0.45
    var delayEnabled = true

    var chorus: Float = 0.30
    var chorusEnabled = false

    var drive: Float = 0.15
    var driveEnabled = false

    var eqLow: Float = 0.5
    var eqHigh: Float = 0.56
    var eqEnabled = true

    var masterVolume: Float = 0.72

    static let `default` = EffectSettings()
}
