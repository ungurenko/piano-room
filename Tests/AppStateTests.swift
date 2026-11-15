import Foundation
import Testing
@testable import PianoRoom

@MainActor
struct AppStateTests {
    private func withPreferences(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "PianoRoomTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }

    @Test func invalidSavedValuesAreSafeForUIAndAudio() throws {
        try withPreferences { defaults in
            defaults.set(Double.nan, forKey: "masterVolume")
            defaults.set(Double.infinity, forKey: "fx.reverb")
            defaults.set(-2.0, forKey: "fx.delay")
            defaults.set(4.0, forKey: "fx.drive")
            let state = AppState(defaults: defaults)
            #expect(state.masterVolume == 0.72)
            #expect(state.effects.reverb == 0.35)
            #expect(state.effects.delay == 0)
            #expect(state.effects.drive == 1)
            #expect(!state.isReady)
        }
    }

    @Test(arguments: [-1, 0, 129, Int.max])
    func unsupportedBufferFallsBackTo128(_ frames: Int) throws {
        try withPreferences { defaults in
            defaults.set(frames, forKey: "bufferFrames")
            #expect(AppState(defaults: defaults).bufferFrames == 128)
        }
    }

    @Test func savedInstrumentAndEffectsRestore() throws {
        try withPreferences { defaults in
            defaults.set("gm-16", forKey: "instrumentID")
            defaults.set(0.6, forKey: "fx.chorus")
            defaults.set(true, forKey: "fx.chorusOn")
            defaults.set(256, forKey: "bufferFrames")
            let state = AppState(defaults: defaults)
            #expect(state.currentInstrument.id == "gm-16")
            #expect(state.effects.chorus == 0.6)
            #expect(state.effects.chorusOn)
            #expect(state.bufferFrames == 256)
        }
    }

    @Test func oldReverbPreferencesKeepMixAndUseChamber() throws {
        try withPreferences { defaults in
            defaults.set(0.63, forKey: "fx.reverb")
            defaults.set(false, forKey: "fx.reverbOn")
            let state = AppState(defaults: defaults)
            #expect(state.effects.reverb == 0.63)
            #expect(!state.effects.reverbOn)
            #expect(state.effects.reverbParameters == .default)
        }
    }

    @Test func reverbPresetAndEditsSurviveRestartAndReset() throws {
        try withPreferences { defaults in
            let state = AppState(defaults: defaults)
            state.setReverb(0.61)
            state.toggleReverb()
            state.selectReverbPreset("ambient")
            #expect(state.effects.reverb == 0.61)
            #expect(!state.effects.reverbOn)
            state.updateReverbParameter(\.decaySeconds, value: 9)
            #expect(state.effects.reverbParameters.isModified)
            let restored = AppState(defaults: defaults)
            #expect(restored.effects.reverbParameters == state.effects.reverbParameters)
            restored.resetReverbPreset()
            #expect(restored.effects.reverbParameters.decaySeconds == 12)
            #expect(restored.effects.reverb == 0.61)
            restored.resetSettings()
            #expect(restored.effects.reverbParameters == .default)
        }
    }

    @Test func invalidReverbParametersAreBounded() throws {
        try withPreferences { defaults in
            defaults.set("missing", forKey: "fx.reverb.presetID")
            defaults.set(Double.nan, forKey: "fx.reverb.decaySeconds")
            defaults.set(999.0, forKey: "fx.reverb.preDelayMs")
            defaults.set(-2.0, forKey: "fx.reverb.width")
            let parameters = AppState(defaults: defaults).effects.reverbParameters
            #expect(parameters.presetID == "chamber")
            #expect(parameters.decaySeconds == 2.2)
            #expect(parameters.preDelayMs == 100)
            #expect(parameters.width == 0)
        }
    }

    @Test func explicitMIDIDisconnectPersistsAndClearsNotes() throws {
        try withPreferences { defaults in
            let state = AppState(defaults: defaults)
            state.selectedSourceID = 7
            state.runningNotes = [60]
            state.sustainDown = true
            state.disconnectMIDISource()
            #expect(state.selectedSourceID == nil)
            #expect(state.runningNotes.isEmpty)
            #expect(!state.sustainDown)
            #expect(defaults.bool(forKey: "midiDisabled"))
        }
    }

    @Test func resetRestoresInstrumentEffectsVolumeAndBuffer() throws {
        try withPreferences { defaults in
            defaults.set("gm-16", forKey: "instrumentID")
            defaults.set(0.2, forKey: "masterVolume")
            defaults.set(512, forKey: "bufferFrames")
            defaults.set(0.9, forKey: "fx.reverb")
            defaults.set(true, forKey: "fx.driveOn")
            let state = AppState(defaults: defaults)
            state.resetSettings()
            #expect(state.currentInstrument == InstrumentCatalog.grandPiano)
            #expect(state.masterVolume == 0.72)
            #expect(state.bufferFrames == 128)
            #expect(state.effects.reverb == 0.35)
            #expect(!state.effects.driveOn)
        }
    }

    @Test func latestSelectionWinsDuringSavedLibraryStartup() async throws {
        let suite = "PianoRoomTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("piano-osiris", forKey: "instrumentID")
        defaults.set(0.0, forKey: "masterVolume")
        defaults.set(true, forKey: "midiDisabled")
        let state = AppState(defaults: defaults)
        state.start()
        for _ in 0..<500 {
            if state.loadingInstrumentName != nil || state.startupError != nil { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(state.loadingInstrumentName == "Osiris Piano")
        state.selectInstrument(InstrumentCatalog.sampledPianos[1])
        for _ in 0..<9_000 {
            if state.isReady || state.startupError != nil { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(state.startupError == nil)
        #expect(state.isReady)
        #expect(state.currentInstrument.id == "piano-headroom")
        #expect(defaults.string(forKey: "instrumentID") == "piano-headroom")
        await state.shutdown()
    }

}
