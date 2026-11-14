import AVFoundation
import CoreAudio
import os
import SwiftUI

private let appLogger = Logger(subsystem: "com.alexpianoroom.PianoRoom", category: "app")

/// Состояние интерфейса эффектов.
struct EffectUIState {
    var reverb: Double = 0.35
    var reverbOn = true

    var delay: Double = 0.25
    var delayTime: Double = 0.45
    var delayOn = true

    var chorus: Double = 0.30
    var chorusOn = false

    var drive: Double = 0.15
    var driveOn = false

    var eqLow: Double = 0.50
    var eqHigh: Double = 0.56
    var eqOn = true

    var toSettings: EffectSettings {
        EffectSettings(
            reverb: Float(reverb), reverbEnabled: reverbOn,
            delay: Float(delay), delayTime: Float(delayTime), delayEnabled: delayOn,
            chorus: Float(chorus), chorusEnabled: chorusOn,
            drive: Float(drive), driveEnabled: driveOn,
            eqLow: Float(eqLow), eqHigh: Float(eqHigh), eqEnabled: eqOn,
            masterVolume: 0.72
        )
    }
}

/// Главное состояние приложения: связывает MIDI, звук и интерфейс.
@MainActor
final class AppState: ObservableObject {

    // MARK: - Инструменты и ноты

    @Published var currentInstrument: Instrument = InstrumentCatalog.grandPiano
    @Published var runningNotes: Set<UInt8> = []
    @Published var sustainDown = false
    @Published var showAllInstruments = false

    // MARK: - MIDI

    @Published var midiSources: [MIDISource] = []
    @Published var selectedSourceID: Int32?
    @Published var pianoConnected = false

    // MARK: - Звук

    @Published var audioOutputs: [AudioOutputDevice] = []
    @Published var selectedOutputID: AudioDeviceID?
    @Published var outputDeviceName = "Системный вывод"
    @Published var effects = EffectUIState()
    @Published var masterVolume: Double = 0.72
    @Published var localSoundMuted = false

    // MARK: - Запуск

    @Published var isStarting = true
    @Published var isReady = false
    @Published var startupError: String?

    // MARK: - Настройки

    @Published var bufferFrames: UInt32 = 128

    // MARK: - Сервисы

    // Движок и MIDI вызываются и с главного потока, и из потока CoreMIDI,
    // поэтому намеренно не привязаны к главному актору.
    nonisolated(unsafe) let engine = AudioEngine()
    nonisolated(unsafe) let midi = MIDIService()

    private var restoreOnTerminate: (() -> Void)?
    private var didAutoMuteLocalSound = false
    private var deviceListener: AudioObjectPropertyListenerBlock?
    private var outputChosenByUser: Bool

    // MARK: - Инициализация

    init() {
        outputChosenByUser = UserDefaults.standard.bool(forKey: "audioOutputByUser")
        loadPreferences()
        setupAudio()
        setupMIDI()

        // При завершении приложения важно выполнить это синхронно: асинхронная
        // задача не успеет стартовать до выхода процесса, и пианино останется немым.
        restoreOnTerminate = { [weak self] in
            MainActor.assumeIsolated {
                self?.restorePianoSound()
            }
        }
    }

    var onTerminate: (() -> Void)? {
        get { restoreOnTerminate }
        set { restoreOnTerminate = newValue }
    }

    // MARK: - Звук

    private func setupAudio() {
        refreshOutputs(preferred: nil)
        startEngine()

        // Пианино могли подключить после запуска: следим за списком устройств.
        deviceListener = AudioDevices.addDeviceChangeListener { [weak self] in
            Task { @MainActor in
                self?.handleAudioDevicesChanged()
            }
        }
    }

    func refreshOutputs(preferred: AudioDeviceID?) {
        let outputs = AudioDevices.outputs()
        audioOutputs = outputs
        guard !outputs.isEmpty else { return }

        let saved = UserDefaults.standard.object(forKey: "audioOutputID") as? Int
        let savedID = saved.map { AudioDeviceID($0) }

        let candidate: AudioOutputDevice?
        if !outputChosenByUser, let piano = outputs.first(where: { $0.isPiano }) {
            // Пианино подключено, а вручную вывод не выбирали — играем через него.
            candidate = piano
        } else {
            candidate =
                outputs.first { $0.id == savedID } ??
                outputs.first { $0.isPiano } ??
                outputs.first { $0.id == AudioDevices.defaultOutputID() } ??
                outputs.first
        }

        guard let chosen = candidate else { return }
        let changed = selectedOutputID != chosen.id
        selectedOutputID = chosen.id
        outputDeviceName = chosen.name
        if preferred == nil || changed {
            UserDefaults.standard.set(Int(chosen.id), forKey: "audioOutputID")
        }
    }

    private func handleAudioDevicesChanged() {
        let previous = selectedOutputID
        refreshOutputs(preferred: previous)
        guard selectedOutputID != previous,
              let device = audioOutputs.first(where: { $0.id == selectedOutputID }) else { return }
        do {
            try engine.switchOutput(deviceID: device.id, deviceName: device.name, bufferFrames: bufferFrames)
        } catch {
            startupError = error.localizedDescription
        }
    }

    private func startEngine() {
        isStarting = true
        startupError = nil

        // Диагностика: принудительно играть через системный вывод.
        let forceBuiltin = ProcessInfo.processInfo.arguments.contains("--builtin-output")
        let deviceID = forceBuiltin ? nil : selectedOutputID
        let name = forceBuiltin
            ? (audioOutputs.first { $0.id == AudioDevices.defaultOutputID() }?.name ?? "Системный вывод")
            : (audioOutputs.first { $0.id == deviceID }?.name ?? outputDeviceName)

        engine.prepare(
            outputDeviceID: deviceID,
            outputDeviceName: name,
            bufferFrames: bufferFrames
        ) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                self.isReady = true
                self.isStarting = false
                self.applyEffects()
                self.engine.setInstrument(self.currentInstrument)
                self.handleDiagnosticArguments()
            case .failure(let error):
                self.isStarting = false
                self.startupError = error.localizedDescription
            }
        }
    }

    func selectOutput(_ device: AudioOutputDevice) {
        outputChosenByUser = true
        UserDefaults.standard.set(true, forKey: "audioOutputByUser")
        selectedOutputID = device.id
        outputDeviceName = device.name
        UserDefaults.standard.set(Int(device.id), forKey: "audioOutputID")
        do {
            try engine.switchOutput(deviceID: device.id, deviceName: device.name, bufferFrames: bufferFrames)
        } catch {
            startupError = error.localizedDescription
        }
    }

    func refreshAudioDevices() {
        refreshOutputs(preferred: selectedOutputID)
    }

    // MARK: - MIDI

    private func setupMIDI() {
        midi.onSourcesChanged = { [weak self] sources in
            Task { @MainActor in
                self?.handleSourcesChanged(sources)
            }
        }

        midi.onEvent = { [weak self] event in
            self?.handleMIDIEvent(event)
        }

        midi.start()
        handleSourcesChanged(midi.sources())
    }

    private func handleSourcesChanged(_ sources: [MIDISource]) {
        midiSources = sources
        pianoConnected = sources.contains { isPianoSource($0) }

        let previousSource = selectedSourceID

        if let current = selectedSourceID, sources.contains(where: { $0.id == current }) {
            // Источник на месте — ничего не меняем.
        } else if let piano = sources.first(where: isPianoSource) {
            selectedSourceID = piano.id
            midi.connect(to: piano)
        } else if let first = sources.first {
            selectedSourceID = first.id
            midi.connect(to: first)
        } else {
            selectedSourceID = nil
        }

        // Источник сменился или исчез: старые ноты могли «залипнуть».
        if previousSource != selectedSourceID {
            engine.allNotesOff()
            runningNotes.removeAll()
            sustainDown = false
        }

        if pianoConnected {
            muteLocalSoundIfNeeded()
        }
    }

    private func isPianoSource(_ source: MIDISource) -> Bool {
        let lowered = source.name.lowercased()
        return lowered.contains("5704") || lowered.contains("piano") || lowered.contains("pia")
    }

    func selectMIDISource(_ source: MIDISource) {
        selectedSourceID = source.id
        midi.connect(to: source)
        // При смене входа старые ноты могли остаться зажатыми.
        engine.allNotesOff()
        runningNotes.removeAll()
        sustainDown = false
    }

    // MARK: - Обработка MIDI

    nonisolated private func handleMIDIEvent(_ event: MIDIEvent) {
        switch event {
        case .noteOn(let note, let velocity, _):
            engine.noteOn(note, velocity: velocity)
            Task { @MainActor [weak self] in
                self?.runningNotes.insert(note)
            }
        case .noteOff(let note, _):
            engine.noteOff(note)
            Task { @MainActor [weak self] in
                self?.runningNotes.remove(note)
            }
        case .controlChange(let controller, let value, _):
            if controller == 64 {
                engine.controlChange(controller, value: value)
                let down = value >= 64
                Task { @MainActor [weak self] in
                    self?.sustainDown = down
                }
            } else if controller == 91 {
                // Кнопка Reverb на панели пианино.
                let amount = Double(value) / 127
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.effects.reverbOn = amount > 0.02
                    self.setReverb(amount)
                }
            } else if controller == 93 {
                // Кнопка Chorus/Delay на панели пианино.
                let amount = Double(value) / 127
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.effects.delayOn = amount > 0.02
                    self.setDelay(amount)
                }
            } else if controller == 120 || controller == 123 {
                engine.controlChange(controller, value: value)
                Task { @MainActor [weak self] in
                    self?.runningNotes.removeAll()
                    self?.sustainDown = false
                }
            } else {
                engine.controlChange(controller, value: value)
            }
        case .pitchBend(let value, _):
            engine.pitchBend(value)
        case .channelPressure(let value, _):
            engine.channelPressure(value)
        case .programChange(let program, let channel):
            // Кнопки тембров на панели пианино присылают Program Change:
            // переключаем приложение на соответствующий инструмент General MIDI.
            guard channel != 9 else { break }
            Task { @MainActor [weak self] in
                guard let self,
                      let instrument = InstrumentCatalog.gm.first(where: { $0.gmProgram == Int(program) }) else { return }
                if self.currentInstrument.source == .gm, self.currentInstrument.gmProgram == Int(program) {
                    return
                }
                self.selectInstrument(instrument)
            }
        case .polyPressure:
            break
        }
    }

    func noteFromScreen(_ note: UInt8, velocity: UInt8 = 96) {        engine.noteOn(note, velocity: velocity)
        runningNotes.insert(note)
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 220_000_000)
            self?.engine.noteOff(note)
            self?.runningNotes.remove(note)
        }
    }

    /// Диагностические флаги запуска: нужны для проверки интерфейса без клавиатуры.
    private func handleDiagnosticArguments() {
        let arguments = ProcessInfo.processInfo.arguments

        if arguments.contains("--test-note") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                self.playTestChord()
            }
        }

        if arguments.contains("--show-all") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                self.showAllInstruments = true
            }
        }

        if let selectArgument = arguments.first(where: { $0.hasPrefix("--select=") }) {
            let identifier = String(selectArgument.dropFirst("--select=".count))
            if let instrument = InstrumentCatalog.instrument(id: identifier) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    self.selectInstrument(instrument)
                }
            }
        }
    }

    /// Диагностический аккорд: запускается с флагом `--test-note`.
    private func playTestChord() {
        appLogger.info("Тестовый аккорд: играем")
        let notes: [UInt8] = [60, 64, 67]
        for note in notes {
            engine.noteOn(note, velocity: 100)
            runningNotes.insert(note)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            for note in notes {
                self.engine.noteOff(note)
                self.runningNotes.remove(note)
            }
        }
    }

    // MARK: - Инструменты

    func selectInstrument(_ instrument: Instrument) {
        currentInstrument = instrument
        engine.setInstrument(instrument)
        UserDefaults.standard.set(instrument.id, forKey: "instrumentID")
    }

    /// Выключить все ноты: помогает, если клавиша «залипла» или пропал MIDI-вход.
    func panic() {
        engine.allNotesOff()
        runningNotes.removeAll()
        sustainDown = false
    }

    // MARK: - Встроенный звук пианино

    /// По умолчанию при первом подключении глушим встроенный звук пианино,
    /// чтобы во время игры не было двойного звучания.
    private func muteLocalSoundIfNeeded() {
        guard !didAutoMuteLocalSound else { return }
        didAutoMuteLocalSound = true
        setLocalSoundMuted(true)
    }

    func toggleLocalSound() {
        setLocalSoundMuted(!localSoundMuted)
    }

    private func setLocalSoundMuted(_ muted: Bool) {
        guard let destination = midi.pianoDestination() else {
            appLogger.error("Пианино не найдено: встроенный звук не переключён")
            localSoundMuted = muted
            return
        }
        let value: UInt8 = muted ? 0 : 127
        for channel in UInt8(0)..<UInt8(16) {
            midi.sendController(122, value: value, channel: channel, to: destination)
        }
        localSoundMuted = muted
        appLogger.info("Встроенный звук пианино \(muted ? "выключен" : "включён", privacy: .public)")
    }

    func restorePianoSound() {
        guard let destination = midi.pianoDestination() else {
            appLogger.error("Пианино не найдено: звук не восстановлен")
            return
        }
        for channel in UInt8(0)..<UInt8(16) {
            midi.sendController(122, value: 127, channel: channel, to: destination)
        }
        // Даём CoreMIDI время донести пакет до USB-устройства перед завершением.
        usleep(120_000)
        appLogger.info("Встроенный звук пианино восстановлен при выходе")
    }

    // MARK: - Эффекты

    func applyEffects() {
        var settings = effects.toSettings
        settings.masterVolume = Float(masterVolume)
        engine.applyAllEffectSettings(settings)
        saveEffects()
    }

    func setReverb(_ value: Double) {
        effects.reverb = value
        engine.setReverb(enabled: effects.reverbOn, amount: Float(value))
        saveEffects()
    }

    func toggleReverb() {
        effects.reverbOn.toggle()
        engine.setReverb(enabled: effects.reverbOn, amount: Float(effects.reverb))
        saveEffects()
    }

    func setDelay(_ value: Double) {
        effects.delay = value
        engine.setDelay(enabled: effects.delayOn, amount: Float(value), time: Float(effects.delayTime))
        saveEffects()
    }

    func setDelayTime(_ value: Double) {
        effects.delayTime = value
        engine.setDelay(enabled: effects.delayOn, amount: Float(effects.delay), time: Float(value))
        saveEffects()
    }

    func toggleDelay() {
        effects.delayOn.toggle()
        engine.setDelay(enabled: effects.delayOn, amount: Float(effects.delay), time: Float(effects.delayTime))
        saveEffects()
    }

    func setChorus(_ value: Double) {
        effects.chorus = value
        engine.setChorus(enabled: effects.chorusOn, amount: Float(value))
        saveEffects()
    }

    func toggleChorus() {
        effects.chorusOn.toggle()
        engine.setChorus(enabled: effects.chorusOn, amount: Float(effects.chorus))
        saveEffects()
    }

    func setDrive(_ value: Double) {
        effects.drive = value
        engine.setDrive(enabled: effects.driveOn, amount: Float(value))
        saveEffects()
    }

    func toggleDrive() {
        effects.driveOn.toggle()
        engine.setDrive(enabled: effects.driveOn, amount: Float(effects.drive))
        saveEffects()
    }

    func setEQ(low: Double? = nil, high: Double? = nil) {
        if let low { effects.eqLow = low }
        if let high { effects.eqHigh = high }
        engine.setEqualizer(enabled: effects.eqOn, low: Float(effects.eqLow), high: Float(effects.eqHigh))
        saveEffects()
    }

    func toggleEQ() {
        effects.eqOn.toggle()
        engine.setEqualizer(enabled: effects.eqOn, low: Float(effects.eqLow), high: Float(effects.eqHigh))
        saveEffects()
    }

    func setMasterVolume(_ value: Double) {
        masterVolume = value
        engine.setMasterVolume(Float(value))
        UserDefaults.standard.set(value, forKey: "masterVolume")
    }

    // MARK: - Настройки

    func setBufferFrames(_ frames: UInt32) {
        bufferFrames = frames
        UserDefaults.standard.set(Int(frames), forKey: "bufferFrames")
        // Меняем только буфер: вывод не считаем «выбранным вручную», чтобы
        // при подключении пианино приложение по-прежнему переключилось на него.
        guard let device = audioOutputs.first(where: { $0.id == selectedOutputID }) else { return }
        do {
            try engine.switchOutput(deviceID: device.id, deviceName: device.name, bufferFrames: frames)
        } catch {
            startupError = error.localizedDescription
        }
    }

    /// Вернуть эффекты, инструмент и настройки к состоянию «как после установки».
    func resetSettings() {
        let defaults = UserDefaults.standard
        let keys = [
            "instrumentID", "masterVolume", "bufferFrames",
            "fx.reverb", "fx.reverbOn", "fx.delay", "fx.delayOn", "fx.delayTime",
            "fx.chorus", "fx.chorusOn", "fx.drive", "fx.driveOn",
            "fx.eqLow", "fx.eqHigh", "fx.eqOn"
        ]
        for key in keys { defaults.removeObject(forKey: key) }

        effects = EffectUIState()
        masterVolume = 0.72
        bufferFrames = 128
        selectInstrument(InstrumentCatalog.grandPiano)
        applyEffects()
        engine.setMasterVolume(0.72)
        appLogger.info("Настройки сброшены")
    }

    var latencyMilliseconds: Double {
        let rate = audioOutputs.first { $0.id == selectedOutputID }?.sampleRate ?? 48_000
        return Double(bufferFrames) / rate * 1000
    }

    var sampleRateLabel: String {
        let rate = audioOutputs.first { $0.id == selectedOutputID }?.sampleRate ?? 48_000
        return "\(Int(rate / 1000)) кГц"
    }

    // MARK: - Сохранение

    private func loadPreferences() {
        let defaults = UserDefaults.standard

        if let id = defaults.string(forKey: "instrumentID"),
           let instrument = InstrumentCatalog.instrument(id: id) {
            currentInstrument = instrument
        }

        masterVolume = defaults.object(forKey: "masterVolume") as? Double ?? 0.72

        if let frames = defaults.object(forKey: "bufferFrames") as? Int, frames > 0 {
            bufferFrames = UInt32(frames)
        }

        effects.reverb = defaults.object(forKey: "fx.reverb") as? Double ?? effects.reverb
        effects.delay = defaults.object(forKey: "fx.delay") as? Double ?? effects.delay
        effects.delayTime = defaults.object(forKey: "fx.delayTime") as? Double ?? effects.delayTime
        effects.chorus = defaults.object(forKey: "fx.chorus") as? Double ?? effects.chorus
        effects.drive = defaults.object(forKey: "fx.drive") as? Double ?? effects.drive
        effects.eqLow = defaults.object(forKey: "fx.eqLow") as? Double ?? effects.eqLow
        effects.eqHigh = defaults.object(forKey: "fx.eqHigh") as? Double ?? effects.eqHigh

        effects.reverbOn = defaults.object(forKey: "fx.reverbOn") as? Bool ?? effects.reverbOn
        effects.delayOn = defaults.object(forKey: "fx.delayOn") as? Bool ?? effects.delayOn
        effects.chorusOn = defaults.object(forKey: "fx.chorusOn") as? Bool ?? effects.chorusOn
        effects.driveOn = defaults.object(forKey: "fx.driveOn") as? Bool ?? effects.driveOn
        effects.eqOn = defaults.object(forKey: "fx.eqOn") as? Bool ?? effects.eqOn
    }

    private func saveEffects() {
        let defaults = UserDefaults.standard
        defaults.set(effects.reverb, forKey: "fx.reverb")
        defaults.set(effects.delay, forKey: "fx.delay")
        defaults.set(effects.delayTime, forKey: "fx.delayTime")
        defaults.set(effects.chorus, forKey: "fx.chorus")
        defaults.set(effects.drive, forKey: "fx.drive")
        defaults.set(effects.eqLow, forKey: "fx.eqLow")
        defaults.set(effects.eqHigh, forKey: "fx.eqHigh")
        defaults.set(effects.reverbOn, forKey: "fx.reverbOn")
        defaults.set(effects.delayOn, forKey: "fx.delayOn")
        defaults.set(effects.chorusOn, forKey: "fx.chorusOn")
        defaults.set(effects.driveOn, forKey: "fx.driveOn")
        defaults.set(effects.eqOn, forKey: "fx.eqOn")
    }
}
