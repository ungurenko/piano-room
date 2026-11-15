import AVFoundation
import CoreAudio
import os
import SwiftUI
import Observation

private let appLogger = Logger(subsystem: "com.alexpianoroom.PianoRoom", category: "app")

/// Состояние интерфейса эффектов.
struct EffectUIState {
    var reverb: Double = 0.35
    var reverbOn = true
    var reverbParameters = ReverbParameters.default

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
            reverb: Float(reverb), reverbEnabled: reverbOn, reverbParameters: reverbParameters,
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
@Observable
final class AppState {

    // MARK: - Инструменты и ноты

    var currentInstrument: Instrument = InstrumentCatalog.grandPiano
    var loadingInstrumentName: String?
    private var instrumentSelectionGeneration = 0
    private var diagnosticArgumentsHandled = false
    var runningNotes: Set<UInt8> = []
    var sustainDown = false
    var showAllInstruments = false

    // MARK: - MIDI

    var midiSources: [MIDISource] = []
    var selectedSourceID: Int32?
    var pianoConnected = false

    // MARK: - Звук

    var audioOutputs: [AudioOutputDevice] = []
    var selectedOutputID: AudioDeviceID?
    var outputDeviceName = "Системный вывод"
    var effects = EffectUIState()
    var masterVolume: Double = 0.72
    var localSoundMuted = false

    // MARK: - Запуск

    var isStarting = true
    var isReady = false
    var startupError: String?

    // MARK: - Настройки

    var bufferFrames: UInt32 = 128

    // MARK: - Сервисы

    // Движок сериализует команды в собственной очереди; MIDI управляется на MainActor.
    nonisolated let engine = AudioEngine()
    let midi = MIDIService()

    private var didAutoMuteLocalSound = false
    private var deviceListener: AudioObjectPropertyListenerBlock?
    private var outputChosenByUser: Bool

    // MARK: - Инициализация

    private let preferences: UserDefaults

    init(defaults: UserDefaults = .standard) {
        preferences = defaults
        outputChosenByUser = preferences.bool(forKey: "audioOutputByUser")
        loadPreferences()
        sanitizePreferences()
    }

    private var isShuttingDown = false
    private var started = false
    private var screenTasks: [UInt8: Task<Void, Never>] = [:]
    private var midiTask: Task<Void, Never>?
    private let midiEpoch = OSAllocatedUnfairLock(initialState: UInt64(0))

    func start() {
        guard !started else { return }
        started = true
        engine.onRuntimeError = { [weak self] message in
            guard let self, !self.isShuttingDown else { return }
            self.isReady = false
            self.startupError = message
            self.restorePianoSound()
        }
        setupAudio()
    }

    func shutdown() async {
        guard !isShuttingDown else { return }
        isShuttingDown = true
        isReady = false
        midi.onEvent = nil
        midi.onSourcesChanged = nil
        midiTask?.cancel()
        midiTask = nil
        for task in screenTasks.values { task.cancel() }
        screenTasks.removeAll()
        restorePianoSound()
        try? await Task.sleep(for: .milliseconds(120))
        midi.shutdown()
        await withCheckedContinuation { continuation in
            engine.stop { continuation.resume() }
        }
        if let deviceListener { AudioDevices.removeDeviceChangeListener(deviceListener) }
        deviceListener = nil
    }

    func retryAudio() {
        guard !isStarting else { return }
        startEngine()
    }

    func disconnectMIDISource() {
        preferences.set(true, forKey: "midiDisabled")
        midi.disconnect()
        selectedSourceID = nil
        panic()
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
        guard !outputs.isEmpty else {
            selectedOutputID = nil
            outputDeviceName = "Нет аудиовыхода"
            isReady = false
            engine.stop()
            restorePianoSound()
            return
        }

        let saved = preferences.object(forKey: "audioOutputID") as? Int
        let savedID = saved.flatMap { AudioDeviceID(exactly: $0) }
        let savedUID = preferences.string(forKey: "audioOutputUID")

        let candidate: AudioOutputDevice?
        if !outputChosenByUser, let piano = outputs.first(where: { $0.isPiano }) {
            // Пианино подключено, а вручную вывод не выбирали — играем через него.
            candidate = piano
        } else {
            candidate =
                outputs.first { $0.uid == savedUID } ??
                outputs.first { savedUID == nil && $0.id == savedID } ??
                outputs.first { $0.isPiano } ??
                outputs.first { $0.id == AudioDevices.defaultOutputID() } ??
                outputs.first
        }

        guard let chosen = candidate else { return }
        selectedOutputID = chosen.id
        outputDeviceName = chosen.name
        if !outputChosenByUser || preferences.string(forKey: "audioOutputUID") == nil {
            preferences.set(chosen.uid, forKey: "audioOutputUID")
            preferences.set(Int(chosen.id), forKey: "audioOutputID")
        }
    }

    private func handleAudioDevicesChanged() {
        let previous = selectedOutputID
        refreshOutputs(preferred: previous)
        guard selectedOutputID != previous,
              let device = audioOutputs.first(where: { $0.id == selectedOutputID }) else { return }
        switchAudio(to: device)
    }

    private func switchAudio(to device: AudioOutputDevice) {
        isReady = false
        engine.switchOutput(deviceID: device.id, deviceName: device.name, bufferFrames: bufferFrames) { [weak self] result in
            guard let self, !self.isShuttingDown else { return }
            switch result {
            case .success:
                self.isReady = true
                self.startupError = nil
                self.bufferFrames = AudioDevices.bufferFrameSize(of: device.id) ?? self.bufferFrames
                self.preferences.set(Int(self.bufferFrames), forKey: "bufferFrames")
                self.muteLocalSoundIfNeeded()
            case .failure(let error):
                self.isReady = false
                self.startupError = error.localizedDescription
                self.restorePianoSound()
            }
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
            guard let self, !self.isShuttingDown else { return }
            switch result {
            case .success:
                self.startupError = nil
                if let id = self.selectedOutputID {
                    self.bufferFrames = AudioDevices.bufferFrameSize(of: id) ?? self.bufferFrames
                }
                self.applyEffects()
                self.selectInstrument(self.currentInstrument)
            case .failure(let error):
                self.isStarting = false
                self.isReady = false
                self.restorePianoSound()
                self.startupError = error.localizedDescription
            }
        }
    }

    func selectOutput(_ device: AudioOutputDevice) {
        outputChosenByUser = true
        preferences.set(true, forKey: "audioOutputByUser")
        selectedOutputID = device.id
        outputDeviceName = device.name
        preferences.set(Int(device.id), forKey: "audioOutputID")
        preferences.set(device.uid, forKey: "audioOutputUID")
        switchAudio(to: device)
    }

    func refreshAudioDevices() {
        handleAudioDevicesChanged()
        handleSourcesChanged(midi.sources())
    }

    // MARK: - MIDI

    private func setupMIDI() {
        midi.onSourcesChanged = { [weak self] sources in
            Task { @MainActor in
                self?.handleSourcesChanged(sources)
            }
        }

        let (stream, continuation) = AsyncStream<(UInt64, MIDIEvent)>.makeStream()
        let epoch = midiEpoch
        midi.onEvent = { event in continuation.yield((epoch.withLock { $0 }, event)) }
        midiTask = Task { [weak self] in
            for await (epoch, event) in stream {
                guard let self, !Task.isCancelled else { return }
                guard self.isReady, self.selectedSourceID != nil, epoch == self.midiEpoch.withLock({ $0 }) else { continue }
                self.handleMIDIEvent(event)
            }
        }

        guard midi.start() else {
            startupError = "Не удалось запустить MIDI. Повтори запуск звука."
            midiTask?.cancel()
            midiTask = nil
            return
        }
        handleSourcesChanged(midi.sources())
    }

    private func handleSourcesChanged(_ sources: [MIDISource]) {
        guard !isShuttingDown else { return }
        let oldEndpoint = midiSources.first { $0.id == selectedSourceID }?.endpoint
        let sources = sources.filter(\.online)
        midiSources = sources
        pianoConnected = sources.contains { isPianoSource($0) }

        if !pianoConnected { didAutoMuteLocalSound = false }
        guard !preferences.bool(forKey: "midiDisabled") else { return }
        let savedID = preferences.object(forKey: "midiSourceID") as? Int32
        let candidate = sources.first { $0.id == selectedSourceID }
            ?? sources.first { $0.id == savedID }
            ?? sources.first(where: isPianoSource)
            ?? sources.first
        if candidate?.id != selectedSourceID || candidate?.endpoint != oldEndpoint {
            midi.disconnect()
            panic()
            selectedSourceID = nil
            if let candidate {
                if midi.connect(to: candidate) { selectedSourceID = candidate.id }
                else { startupError = "Не удалось подключить MIDI-вход" }
            }
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
        midi.disconnect()
        panic()
        selectedSourceID = nil
        guard midi.connect(to: source) else {
            startupError = "Не удалось подключить MIDI-вход"
            return
        }
        preferences.set(false, forKey: "midiDisabled")
        preferences.set(source.id, forKey: "midiSourceID")
        selectedSourceID = source.id
    }

    // MARK: - Обработка MIDI

    private func handleMIDIEvent(_ event: MIDIEvent) {
        switch event {
        case .noteOn(let note, let velocity, _):
            engine.noteOn(note, velocity: velocity)
            runningNotes.insert(note)
        case .noteOff(let note, _):
            engine.noteOff(note)
            runningNotes.remove(note)
        case .controlChange(let controller, let value, _):
            if controller == 64 {
                engine.controlChange(controller, value: value)
                let down = value >= 64
                sustainDown = down
            } else if controller == 91 {
                // Кнопка Reverb на панели пианино.
                let amount = Double(value) / 127
                effects.reverbOn = amount > 0.02
                self.setReverb(amount)
            } else if controller == 93 {
                // Кнопка Chorus/Delay на панели пианино.
                let amount = Double(value) / 127
                effects.delayOn = amount > 0.02
                self.setDelay(amount)
            } else if controller == 120 || controller == 123 {
                engine.controlChange(controller, value: value)
                runningNotes.removeAll()
                self.sustainDown = false
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
            guard
                  let instrument = InstrumentCatalog.gm.first(where: { $0.gmProgram == Int(program) }) else { return }
            if self.isReady, self.currentInstrument.source == .gm, self.currentInstrument.gmProgram == Int(program) {
                return
            }
            self.selectInstrument(instrument)
        case .polyPressure:
            break
        }
    }

    func noteFromScreen(_ note: UInt8, velocity: UInt8 = 96) {
        guard isReady else { return }
        screenTasks[note]?.cancel()
        engine.noteOn(note, velocity: velocity)
        runningNotes.insert(note)
        screenTasks[note] = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(220)) } catch { return }
            guard let self, !self.isShuttingDown else { return }
            self.engine.noteOff(note)
            runningNotes.remove(note)
            self.screenTasks[note] = nil
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
            guard !self.isShuttingDown else { return }
            for note in notes {
                self.engine.noteOff(note)
                self.runningNotes.remove(note)
            }
        }
    }

    // MARK: - Инструменты

    func selectInstrument(_ instrument: Instrument) {
        if !started || (isStarting && !engine.isReady && loadingInstrumentName == nil) {
            currentInstrument = instrument
            preferences.set(instrument.id, forKey: "instrumentID")
            return
        }
        panic(invalidateInput: false)
        instrumentSelectionGeneration += 1
        let generation = instrumentSelectionGeneration
        let loading = instrument.source == .sampledPiano || currentInstrument.source == .sampledPiano || !isReady
        if loading {
            loadingInstrumentName = instrument.name
            isReady = false
        }
        startupError = nil
        engine.setInstrument(instrument) { [weak self] result in
            guard let self, !self.isShuttingDown,
                  generation == self.instrumentSelectionGeneration else { return }
            self.loadingInstrumentName = nil
            self.isStarting = false
            switch result {
            case .success:
                self.currentInstrument = instrument
                self.preferences.set(instrument.id, forKey: "instrumentID")
                self.isReady = true
                if self.midiTask == nil { self.setupMIDI() }
                self.muteLocalSoundIfNeeded()
                if !self.diagnosticArgumentsHandled {
                    self.diagnosticArgumentsHandled = true
                    self.handleDiagnosticArguments()
                }
            case .failure(let error):
                if error is CancellationError { return }
                self.isReady = false
                self.startupError = error.localizedDescription
                self.restorePianoSound()
            }
        }
    }

    /// Выключить все ноты: помогает, если клавиша «залипла» или пропал MIDI-вход.
    func panic(invalidateInput: Bool = true) {
        if invalidateInput { midiEpoch.withLock { $0 &+= 1 } }
        for task in screenTasks.values { task.cancel() }
        screenTasks.removeAll()
        engine.controlChange(64, value: 0)
        engine.allNotesOff()
        runningNotes.removeAll()
        sustainDown = false
    }

    // MARK: - Встроенный звук пианино

    /// По умолчанию при первом подключении глушим встроенный звук пианино,
    /// чтобы во время игры не было двойного звучания.
    private func muteLocalSoundIfNeeded() {
        guard !isShuttingDown, isReady, pianoConnected, !didAutoMuteLocalSound else { return }
        setLocalSoundMuted(true)
        didAutoMuteLocalSound = localSoundMuted
    }

    func toggleLocalSound() {
        setLocalSoundMuted(!localSoundMuted)
    }

    private func setLocalSoundMuted(_ muted: Bool) {
        guard let destination = midi.pianoDestination() else {
            appLogger.error("Пианино не найдено: встроенный звук не переключён")
            return
        }
        let value: UInt8 = muted ? 0 : 127
        var success = true
        for channel in UInt8(0)..<UInt8(16) {
            if !midi.sendController(122, value: value, channel: channel, to: destination) { success = false }
        }
        guard success else {
            if muted { localSoundMuted = true; restorePianoSound() }
            startupError = "Не удалось переключить встроенный звук пианино"
            return
        }
        localSoundMuted = muted
        appLogger.info("Встроенный звук пианино \(muted ? "выключен" : "включён", privacy: .public)")
    }

    func restorePianoSound() {
        guard localSoundMuted else { return }
        guard let destination = midi.pianoDestination() else {
            appLogger.error("Пианино не найдено: звук не восстановлен")
            return
        }
        var success = true
        for channel in UInt8(0)..<UInt8(16) {
            if !midi.sendController(122, value: 127, channel: channel, to: destination) { success = false }
        }
        guard success else {
            appLogger.error("Не удалось восстановить встроенный звук пианино")
            return
        }
        localSoundMuted = false
        didAutoMuteLocalSound = false
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

    func selectReverbPreset(_ id: String) {
        effects.reverbParameters = ReverbParameters.parameters(for: id)
        engine.setReverbParameters(effects.reverbParameters)
        saveEffects()
    }

    func updateReverbParameter(_ keyPath: WritableKeyPath<ReverbParameters, Float>, value: Float) {
        effects.reverbParameters[keyPath: keyPath] = value
        effects.reverbParameters = effects.reverbParameters.sanitized()
        engine.setReverbParameters(effects.reverbParameters)
        saveEffects()
    }

    func resetReverbPreset() {
        selectReverbPreset(effects.reverbParameters.presetID)
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
        preferences.set(value, forKey: "masterVolume")
    }

    // MARK: - Настройки

    func setBufferFrames(_ frames: UInt32) {
        bufferFrames = frames
        preferences.set(Int(frames), forKey: "bufferFrames")
        // Меняем только буфер: вывод не считаем «выбранным вручную», чтобы
        // при подключении пианино приложение по-прежнему переключилось на него.
        guard let device = audioOutputs.first(where: { $0.id == selectedOutputID }) else { return }
        switchAudio(to: device)
    }

    /// Вернуть эффекты, инструмент и настройки к состоянию «как после установки».
    func resetSettings() {
        let defaults = preferences
        let keys = [
            "instrumentID", "masterVolume", "bufferFrames",
            "fx.reverb", "fx.reverbOn", "fx.delay", "fx.delayOn", "fx.delayTime",
            "fx.chorus", "fx.chorusOn", "fx.drive", "fx.driveOn",
            "fx.eqLow", "fx.eqHigh", "fx.eqOn"
        ]
        for key in keys { defaults.removeObject(forKey: key) }
        for key in Self.reverbPreferenceKeys { defaults.removeObject(forKey: "fx.reverb.\(key)") }

        effects = EffectUIState()
        masterVolume = 0.72
        setBufferFrames(128)
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
        let defaults = preferences

        if let id = defaults.string(forKey: "instrumentID"),
           let instrument = InstrumentCatalog.instrument(id: id) {
            currentInstrument = instrument
        }

        masterVolume = defaults.object(forKey: "masterVolume") as? Double ?? 0.72

        if let frames = defaults.object(forKey: "bufferFrames") as? Int, [64, 128, 256, 512].contains(frames) {
            bufferFrames = UInt32(frames)
        }

        let presetID = defaults.string(forKey: "fx.reverb.presetID") ?? "chamber"
        var reverb = ReverbParameters.parameters(for: presetID)
        for (name, keyPath) in Self.reverbParameterKeys {
            if let number = defaults.object(forKey: "fx.reverb.\(name)") as? NSNumber {
                reverb[keyPath: keyPath] = number.floatValue
            }
        }
        effects.reverbParameters = reverb.sanitized()

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

    private func sanitizePreferences() {
        func bounded(_ value: Double, fallback: Double) -> Double {
            value.isFinite ? min(1, max(0, value)) : fallback
        }
        masterVolume = bounded(masterVolume, fallback: 0.72)
        effects.reverb = bounded(effects.reverb, fallback: 0.35)
        effects.reverbParameters = effects.reverbParameters.sanitized()
        effects.delay = bounded(effects.delay, fallback: 0.25)
        effects.delayTime = bounded(effects.delayTime, fallback: 0.45)
        effects.chorus = bounded(effects.chorus, fallback: 0.3)
        effects.drive = bounded(effects.drive, fallback: 0.15)
        effects.eqLow = bounded(effects.eqLow, fallback: 0.5)
        effects.eqHigh = bounded(effects.eqHigh, fallback: 0.56)
    }

    private static let reverbParameterKeys: [(String, WritableKeyPath<ReverbParameters, Float>)] = [
        ("decaySeconds", \.decaySeconds), ("size", \.size), ("preDelayMs", \.preDelayMs),
        ("tone", \.tone), ("width", \.width), ("modulation", \.modulation)
    ]
    private static var reverbPreferenceKeys: [String] {
        ["presetID"] + reverbParameterKeys.map { $0.0 }
    }

    private func saveEffects() {
        let defaults = preferences
        defaults.set(effects.reverbParameters.presetID, forKey: "fx.reverb.presetID")
        for (name, keyPath) in Self.reverbParameterKeys {
            defaults.set(Double(effects.reverbParameters[keyPath: keyPath]), forKey: "fx.reverb.\(name)")
        }
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
