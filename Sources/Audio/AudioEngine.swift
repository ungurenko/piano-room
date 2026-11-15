import AVFoundation
import AudioToolbox
import Foundation
import os
import Synchronization

private let logger = Logger(subsystem: "com.alexpianoroom.PianoRoom", category: "audio")

/// All mutable AVFoundation state belongs exclusively to `queue`. The facade is
/// Sendable because callers only enqueue commands; render parameters use atomics.
final class AudioEngine: @unchecked Sendable {
    enum EngineError: LocalizedError {
        case noSoundBank
        case soundBankLoadFailed(String)
        case engineStartFailed(String)
        case midiSynthUnavailable
        case chorusUnavailable
        case reverbUnavailable
        case instrumentLoadFailed(String)

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
            case .instrumentLoadFailed(let name):
                return "Не удалось загрузить «\(name)». Попробуйте выбрать инструмент ещё раз."
            case .reverbUnavailable:
                return "Не удалось создать эффект реверберации."
            case .chorusUnavailable:
                return "Не удалось создать эффект хоруса."
            }
        }
    }

    private let queue = DispatchQueue(label: "com.alexpianoroom.audio", qos: .userInteractive)
    private let core = AudioEngineCore()
    private let ready = Atomic<Bool>(false)
    private let sampledInstrumentActive = Atomic<Bool>(false)
    private let instrumentSelection = OSAllocatedUnfairLock(initialState: 0)
    private let lifecycle = OSAllocatedUnfairLock(initialState: 0)
    private var observer: NSObjectProtocol?
    private let errorHandler = OSAllocatedUnfairLock<(@MainActor @Sendable (String) -> Void)?>(initialState: nil)
    var onRuntimeError: (@MainActor @Sendable (String) -> Void)? {
        get { errorHandler.withLock { $0 } }
        set { errorHandler.withLock { $0 = newValue } }
    }
    var isReady: Bool { ready.load(ordering: .acquiring) }

    init() {
        observer = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange,
            object: core.notificationObject, queue: nil) { [weak self] _ in
            guard let self else { return }
            self.queue.async {
                do { try self.core.recoverConfiguration() }
                catch { self.reportFailure(error) }
            }
        }
    }
    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }
    private func reportFailure(_ error: Error) {
        ready.store(false, ordering: .releasing)
        let handler = onRuntimeError
        let message = error.localizedDescription
        Task { @MainActor in handler?(message) }
    }
    func prepare(outputDeviceID: AudioDeviceID?, outputDeviceName: String, bufferFrames: UInt32,
                 completion: @escaping @MainActor @Sendable (Result<Void, Error>) -> Void) {
        let ticket = lifecycle.withLock { $0 += 1; return $0 }
        ready.store(false, ordering: .releasing)
        let description = AudioComponentDescription(componentType: kAudioUnitType_Effect,
            componentSubType: 0x63687273, componentManufacturer: 0x50526d73,
            componentFlags: 0, componentFlagsMask: 0)
        AUAudioUnit.registerSubclass(ChorusUnit.self, as: description, name: "Piano Room Chorus", version: 1)
        // Core construction continues from the callback; no semaphore or captured mutable result.
        AVAudioUnit.instantiate(with: description, options: []) { [self] unit, _ in
            // The instance is transferred once to its owning queue and never exposed.
            let transfer = AudioUnitTransfer(unit: unit)
            let reverbDescription = AudioComponentDescription(componentType: kAudioUnitType_Effect,
                componentSubType: 0x72767262, componentManufacturer: 0x50526d73,
                componentFlags: 0, componentFlagsMask: 0)
            AUAudioUnit.registerSubclass(ReverbUnit.self, as: reverbDescription, name: "Piano Room Reverb", version: 1)
            AVAudioUnit.instantiate(with: reverbDescription, options: []) { [self] reverb, _ in
                let reverbTransfer = AudioUnitTransfer(unit: reverb)
                queue.async {
                    guard ticket == self.lifecycle.withLock({ $0 }) else { return }
                    self.core.installChorus(transfer.unit)
                    self.core.installReverb(reverbTransfer.unit)
                    self.core.prepare(outputDeviceID: outputDeviceID, outputDeviceName: outputDeviceName,
                                      bufferFrames: bufferFrames) { result in
                        self.ready.store((try? result.get()) != nil, ordering: .releasing)
                        Task { @MainActor in completion(result) }
                    }
                }
            }
        }
    }
    func switchOutput(deviceID: AudioDeviceID?, deviceName: String, bufferFrames: UInt32,
                      completion: @escaping @MainActor @Sendable (Result<Void, Error>) -> Void) {
        ready.store(false, ordering: .releasing)
        queue.async {
            do {
                guard self.core.isReady else { throw EngineError.engineStartFailed("движок ещё не готов") }
                try self.core.switchOutput(deviceID: deviceID, deviceName: deviceName, bufferFrames: bufferFrames)
                self.ready.store(true, ordering: .releasing)
                Task { @MainActor in completion(.success(())) }
            } catch {
                self.reportFailure(error)
                Task { @MainActor in completion(.failure(error)) }
            }
        }
    }
    // Compatibility entrypoint: failures are delivered through onRuntimeError.
    func switchOutput(deviceID: AudioDeviceID?, deviceName: String, bufferFrames: UInt32) throws {
        switchOutput(deviceID: deviceID, deviceName: deviceName, bufferFrames: bufferFrames) { _ in }
    }
    func stop(completion: (@MainActor @Sendable () -> Void)? = nil) {
        lifecycle.withLock { $0 += 1 }
        instrumentSelection.withLock { $0 += 1 }
        ready.store(false, ordering: .releasing)
        queue.async {
            self.core.stop()
            Task { @MainActor in completion?() }
        }
    }
    func setInstrument(_ instrument: Instrument) {
        setInstrument(instrument) { [weak self] result in
            if case .failure(let error) = result, !(error is CancellationError) {
                self?.reportFailure(error)
            }
        }
    }
    func setInstrument(_ instrument: Instrument,
                       completion: @escaping @MainActor @Sendable (Result<Void, Error>) -> Void) {
        let ticket = instrumentSelection.withLock { $0 += 1; return $0 }
        let lifetime = lifecycle.withLock { $0 }
        if instrument.source == .sampledPiano || sampledInstrumentActive.load(ordering: .acquiring) {
            ready.store(false, ordering: .releasing)
        }
        queue.async {
            guard ticket == self.instrumentSelection.withLock({ $0 }),
                  lifetime == self.lifecycle.withLock({ $0 }) else {
                Task { @MainActor in completion(.failure(CancellationError())) }
                return
            }
            do {
                try self.core.setInstrument(instrument)
                guard ticket == self.instrumentSelection.withLock({ $0 }),
                      lifetime == self.lifecycle.withLock({ $0 }) else {
                    Task { @MainActor in completion(.failure(CancellationError())) }
                    return
                }
                self.sampledInstrumentActive.store(instrument.source == .sampledPiano, ordering: .releasing)
                self.ready.store(self.core.isReady, ordering: .releasing)
                Task { @MainActor in completion(.success(())) }
            } catch {
                self.ready.store(false, ordering: .releasing)
                Task { @MainActor in completion(.failure(error)) }
            }
        }
    }
    func noteOn(_ note: UInt8, velocity: UInt8) {
        guard isReady, note < 128, velocity < 128 else { return }
        queue.async { self.core.noteOn(note, velocity: velocity) }
    }
    func noteOff(_ note: UInt8) { queue.async { self.core.noteOff(note) } }
    func controlChange(_ controller: UInt8, value: UInt8) { queue.async { self.core.controlChange(controller, value: value) } }
    func pitchBend(_ value: UInt16) { queue.async { self.core.pitchBend(value) } }
    func channelPressure(_ value: UInt8) { queue.async { self.core.channelPressure(value) } }
    func allNotesOff() { queue.async { self.core.allNotesOff() } }
    func applyAllEffectSettings(_ settings: EffectSettings) { queue.async { self.core.applyAllEffectSettings(settings) } }
    func setReverb(enabled: Bool, amount: Float) { queue.async { self.core.setReverb(enabled: enabled, amount: amount) } }
    func setReverbParameters(_ parameters: ReverbParameters) { queue.async { self.core.setReverbParameters(parameters) } }
    func setDelay(enabled: Bool, amount: Float, time: Float) { queue.async { self.core.setDelay(enabled: enabled, amount: amount, time: time) } }
    func setChorus(enabled: Bool, amount: Float) { queue.async { self.core.setChorus(enabled: enabled, amount: amount) } }
    func setDrive(enabled: Bool, amount: Float) { queue.async { self.core.setDrive(enabled: enabled, amount: amount) } }
    func setEqualizer(enabled: Bool, low: Float, high: Float) { queue.async { self.core.setEqualizer(enabled: enabled, low: low, high: high) } }
    func setMasterVolume(_ volume: Float) { queue.async { self.core.setMasterVolume(volume) } }

    // Stopping AVAudioEngine resets both instruments to their factory sounds.
    // Restore their patches after preparing resources, before accepting new notes.
    static func startEngine(_ engine: AVAudioEngine, grandSampler: AVAudioUnitSampler,
                            bankURL: URL, gmSynth: AVAudioUnitMIDIInstrument,
                            gmProgram: UInt8) throws {
        if engine.isRunning { engine.stop() }
        engine.prepare()
        logger.info("Загружаем рояль: \(bankURL.lastPathComponent, privacy: .public)")
        do {
            try grandSampler.loadSoundBankInstrument(at: bankURL, program: 0,
                bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
                bankLSB: UInt8(kAUSampler_DefaultBankLSB))
        } catch {
            do {
                try grandSampler.loadSoundBankInstrument(at: bankURL, program: 0, bankMSB: 0, bankLSB: 0)
            } catch {
                throw EngineError.soundBankLoadFailed(error.localizedDescription)
            }
        }
        gmSynth.sendProgramChange(gmProgram, bankMSB: 0, bankLSB: 0, onChannel: 0)
        do { try engine.start() }
        catch { throw EngineError.engineStartFailed(error.localizedDescription) }
    }

    // DLSMusicDevice applies live General MIDI program changes on the system bank.
    static func makeGMInstrument() -> AVAudioUnitMIDIInstrument {
        let description = AudioComponentDescription(
            componentType: kAudioUnitType_MusicDevice,
            componentSubType: kAudioUnitSubType_DLSSynth,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        return AVAudioUnitMIDIInstrument(audioComponentDescription: description)
    }
}

/// A one-way ownership transfer from Apple's instantiation callback to the audio queue.
private struct AudioUnitTransfer: @unchecked Sendable { let unit: AVAudioUnit? }

/// Звуковой движок приложения.
///
/// Два источника звука:
/// 1. `AVAudioUnitSampler` с банком Salamander — качественный рояль.
/// 2. `AVAudioUnitMIDIInstrument` (DLSMusicDevice) — 128 инструментов General MIDI.
///
/// Оба идут в общую цепочку эффектов: эквалайзер → перегруз → хорус → дилей →
/// реверберация → общий микшер. Переключение источника мгновенное (микшером),
/// поэтому не нужно перезагружать банки во время игры.
fileprivate final class AudioEngineCore {

    typealias EngineError = AudioEngine.EngineError

    // MARK: - Узлы

    private let engine = AVAudioEngine()
    var notificationObject: AVAudioEngine { engine }
    func recoverConfiguration() throws {
        guard isReady, isRunning, !engine.isRunning else { return }
        try startEngineNow()
    }
    private let grandSampler = AVAudioUnitSampler()
    private let gmSynth: AVAudioUnitMIDIInstrument
    private let grandMixer = AVAudioMixerNode()
    private let gmMixer = AVAudioMixerNode()
    private let sampledMixer = AVAudioMixerNode()
    private let sampledPiano = SampledPianoPlayer()
    private let preMixer = AVAudioMixerNode()
    private let masterMixer = AVAudioMixerNode()
    private let equalizer = AVAudioUnitEQ(numberOfBands: 2)
    private let distortion = AVAudioUnitDistortion()
    private let delay = AVAudioUnitDelay()
    private var reverbUnit: AVAudioUnit?
    private var reverb: ReverbUnit?
    private var reverbParameters = ReverbParameters.default
    private var reverbAmount: Float = 0.35
    private var reverbEnabled = true
    private var chorusUnit: AVAudioUnit?
    private var chorus: ChorusUnit?

    private let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
    private var graphBuilt = false
    private var levelTapInstalled = false
    private var bufferFrameSize: UInt32 = 128

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
        do {
            self.outputDeviceName = outputDeviceName
            self.bufferFrameSize = bufferFrames
            try configureOutputDevice(deviceID: outputDeviceID, bufferFrames: bufferFrames)
            try buildGraphIfNeeded()
            try startEngineNow()
            isReady = true
            applyAllEffectSettings(.default)
            completion(.success(()))
        } catch {
            isReady = false
            isRunning = false
            completion(.failure(error))
        }
    }

    func installChorus(_ unit: AVAudioUnit?) {
        guard !graphBuilt else { return }
        chorusUnit = unit
        chorus = unit?.auAudioUnit as? ChorusUnit
    }

    func installReverb(_ unit: AVAudioUnit?) {
        guard !graphBuilt else { return }
        reverbUnit = unit
        reverb = unit?.auAudioUnit as? ReverbUnit
    }

    private func buildGraphIfNeeded() throws {
        guard !graphBuilt else { return }

        engine.attach(grandSampler)
        engine.attach(gmSynth)
        engine.attach(grandMixer)
        engine.attach(gmMixer)
        engine.attach(sampledMixer)
        engine.attach(sampledPiano.node)
        engine.attach(preMixer)
        engine.attach(masterMixer)
        engine.attach(equalizer)
        engine.attach(distortion)
        engine.attach(delay)
        guard let reverbUnit, reverb != nil else { throw EngineError.reverbUnavailable }
        engine.attach(reverbUnit)

        engine.connect(grandSampler, to: grandMixer, format: format)
        engine.connect(gmSynth, to: gmMixer, format: format)
        engine.connect(sampledPiano.node, to: sampledMixer, format: format)
        engine.connect(grandMixer, to: preMixer, fromBus: 0, toBus: 0, format: format)
        engine.connect(gmMixer, to: preMixer, fromBus: 0, toBus: 1, format: format)
        engine.connect(sampledMixer, to: preMixer, fromBus: 0, toBus: 2, format: format)
        engine.connect(preMixer, to: equalizer, format: format)
        engine.connect(equalizer, to: distortion, format: format)

        // Хорус собирается отдельно: если системный AU не поднялся, идём напрямую.
        let chorusResult = chorusUnit.flatMap { unit in chorus.map { (unit, $0) } }
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
        engine.connect(delay, to: reverbUnit, format: format)
        engine.connect(reverbUnit, to: masterMixer, format: format)
        // Явно соединяем мастер-микшер с выходом: автоматическое подключение
        // mainMixerNode на этой macOS не срабатывает, и звук не рендерится.
        engine.connect(masterMixer, to: engine.outputNode, format: format)

        configureEffects()
        graphBuilt = true
    }

    private func pianoAssetURL(for instrument: Instrument) throws -> URL {
        guard let path = instrument.assetPath,
              let resources = Bundle.main.resourceURL else {
            throw EngineError.instrumentLoadFailed(instrument.name)
        }
        let url = resources.appendingPathComponent("Instruments").appendingPathComponent(path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw EngineError.instrumentLoadFailed(instrument.name)
        }
        return url
    }

    private var usesSFZ: Bool { currentInstrument.assetPath?.hasSuffix(".sfz") == true }

    private func grandPianoBankURL() throws -> URL {
        if currentInstrument.assetPath?.hasSuffix(".sf2") == true {
            return try pianoAssetURL(for: currentInstrument)
        }
        // Resolve this bank by name: additional libraries also contain SF2 files.
        guard let url = Bundle.main.url(forResource: "Salamander", withExtension: "sf2")
            ?? Bundle.main.url(forResource: "Salamander", withExtension: "sf2", subdirectory: "SoundBanks") else {
            throw EngineError.noSoundBank
        }
        return url
    }

    private func configureOutputDevice(deviceID: AudioDeviceID?, bufferFrames: UInt32) throws {
        guard let chosenID = deviceID ?? AudioDevices.defaultOutputID(), chosenID != 0 else {
            throw EngineError.engineStartFailed("аудиовыход недоступен")
        }
        guard AudioDevices.setBufferFrameSize(bufferFrames, for: chosenID),
              let actualFrames = AudioDevices.bufferFrameSize(of: chosenID), actualFrames > 0 else {
            throw EngineError.engineStartFailed("устройство не приняло размер буфера")
        }
        do {
            try engine.outputNode.auAudioUnit.setDeviceID(chosenID)
            outputDeviceID = chosenID
            bufferFrameSize = actualFrames
            logger.info("Выбрано аудиоустройство: \(self.outputDeviceName, privacy: .public)")
        } catch {
            throw EngineError.engineStartFailed("не удалось выбрать аудиовыход: \(error.localizedDescription)")
        }
    }

    private func startEngineNow() throws {
        if engine.isRunning { engine.stop() }
        sampledPiano.reset()
        try AudioEngine.startEngine(engine, grandSampler: grandSampler, bankURL: grandPianoBankURL(),
                                    gmSynth: gmSynth, gmProgram: UInt8(max(0, min(127, currentInstrument.gmProgram ?? 0))))
        isRunning = true
        updateMixLevels()

        // Измеритель уровня нужен только для диагностического запуска.
        if ProcessInfo.processInfo.arguments.contains("--test-note") {
            startLevelMonitor()
        }
        logger.info("Движок запущен, выход: \(self.outputDeviceName, privacy: .public), буфер: \(self.bufferFrameSize) кадров")
    }

    /// Диагностика: пишет в журнал пиковый уровень сигнала, чтобы видеть, доходит ли звук.
    private func startLevelMonitor() {
        guard levelTapInstalled == false else { return }
        levelTapInstalled = true
        masterMixer.installTap(onBus: 0, bufferSize: 2048, format: nil) { buffer, _ in
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
        bufferFrameSize = bufferFrames
        allNotesOff()
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

    func setInstrument(_ instrument: Instrument) throws {
        guard graphBuilt else { throw AudioEngine.EngineError.engineStartFailed("звук ещё готовится") }
        guard instrument.id != currentInstrument.id || !engine.isRunning else { return }
        allNotesOff()
        let previous = currentInstrument
        if instrument.source == .sampledPiano || previous.source == .sampledPiano || !engine.isRunning {
            if engine.isRunning { engine.stop() }
            isRunning = false
            do {
                if instrument.assetPath?.hasSuffix(".sfz") == true {
                    try sampledPiano.load(at: pianoAssetURL(for: instrument), name: instrument.name)
                } else {
                    sampledPiano.unload()
                }
                currentInstrument = instrument
                try startEngineNow()
                isReady = true
            } catch {
                currentInstrument = previous
                isReady = false
                throw error
            }
        } else {
            currentInstrument = instrument
            if instrument.source == .gm, let program = instrument.gmProgram {
                gmSynth.sendProgramChange(UInt8(max(0, min(127, program))), bankMSB: 0, bankLSB: 0, onChannel: 0)
            }
            updateMixLevels()
        }
    }

    private func updateMixLevels() {
        grandMixer.outputVolume = currentInstrument.source != .gm && !usesSFZ ? 1 : 0
        gmMixer.outputVolume = currentInstrument.source == .gm ? 1 : 0
        sampledMixer.outputVolume = usesSFZ ? (currentInstrument.id == "piano-osiris" ? 0.35 : 1) : 0
    }

    // MARK: - Ноты и контроллеры

    func noteOn(_ note: UInt8, velocity: UInt8) {
        switch currentInstrument.source {
        case .grandPiano:
            grandSampler.startNote(note, withVelocity: velocity, onChannel: 0)
        case .sampledPiano:
            if usesSFZ { sampledPiano.send(0x90, note, velocity) }
            else { grandSampler.startNote(note, withVelocity: velocity, onChannel: 0) }
        case .gm:
            gmSynth.startNote(note, withVelocity: velocity, onChannel: 0)
        }
    }

    func noteOff(_ note: UInt8) {
        switch currentInstrument.source {
        case .grandPiano:
            grandSampler.stopNote(note, onChannel: 0)
        case .sampledPiano:
            if usesSFZ { sampledPiano.send(0x80, note) }
            else { grandSampler.stopNote(note, onChannel: 0) }
        case .gm:
            gmSynth.stopNote(note, onChannel: 0)
        }
    }

    func controlChange(_ controller: UInt8, value: UInt8) {
        switch currentInstrument.source {
        case .grandPiano:
            grandSampler.sendController(controller, withValue: value, onChannel: 0)
        case .sampledPiano:
            if usesSFZ { sampledPiano.send(0xB0, controller, value) }
            else { grandSampler.sendController(controller, withValue: value, onChannel: 0) }
        case .gm:
            gmSynth.sendController(controller, withValue: value, onChannel: 0)
        }
    }

    func pitchBend(_ value: UInt16) {
        switch currentInstrument.source {
        case .grandPiano:
            grandSampler.sendPitchBend(value, onChannel: 0)
        case .sampledPiano:
            if usesSFZ { sampledPiano.send(0xE0, UInt8(value & 127), UInt8((value >> 7) & 127)) }
            else { grandSampler.sendPitchBend(value, onChannel: 0) }
        case .gm:
            gmSynth.sendPitchBend(value, onChannel: 0)
        }
    }

    func channelPressure(_ value: UInt8) {
        switch currentInstrument.source {
        case .grandPiano:
            grandSampler.sendPressure(value, onChannel: 0)
        case .sampledPiano:
            if usesSFZ { sampledPiano.send(0xD0, value) }
            else { grandSampler.sendPressure(value, onChannel: 0) }
        case .gm:
            gmSynth.sendPressure(value, onChannel: 0)
        }
    }

    func allNotesOff() {
        sampledPiano.send(0xB0, 64, 0)
        sampledPiano.send(0xB0, 123, 0)
        sampledPiano.send(0xB0, 120, 0)
        for channel in UInt8(0)..<UInt8(16) {
            grandSampler.sendController(64, withValue: 0, onChannel: channel)
            gmSynth.sendController(64, withValue: 0, onChannel: channel)
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

        updateReverb()
    }

    func applyAllEffectSettings(_ settings: EffectSettings) {
        guard graphBuilt else { return }
        reverbParameters = settings.reverbParameters
        setReverb(enabled: settings.reverbEnabled, amount: settings.reverb)
        setDelay(enabled: settings.delayEnabled, amount: settings.delay, time: settings.delayTime)
        setChorus(enabled: settings.chorusEnabled, amount: settings.chorus)
        setDrive(enabled: settings.driveEnabled, amount: settings.drive)
        setEqualizer(enabled: settings.eqEnabled, low: settings.eqLow, high: settings.eqHigh)
        setMasterVolume(settings.masterVolume)
    }

    func setReverb(enabled: Bool, amount: Float) {
        reverbEnabled = enabled
        reverbAmount = amount.isFinite ? max(0, min(1, amount)) : 0.35
        updateReverb()
    }

    func setReverbParameters(_ parameters: ReverbParameters) {
        reverbParameters = parameters
        updateReverb()
    }

    private func updateReverb() {
        reverb?.apply(parameters: reverbParameters, mix: reverbAmount, enabled: reverbEnabled)
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
        gmSynth = AudioEngine.makeGMInstrument()
    }
}

/// Значения эффектов, которые интерфейс передаёт движку.
struct EffectSettings: Sendable {
    var reverb: Float = 0.35
    var reverbEnabled = true
    var reverbParameters = ReverbParameters.default

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
