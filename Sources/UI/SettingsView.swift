import AppKit
import CoreAudio
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.section) {
            soundSection
            midiSection
            pianoSection

            Spacer(minLength: 0)

            Button {
                state.resetSettings()
            } label: {
                Label("Сбросить настройки", systemImage: "arrow.counterclockwise")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.muted)
            }
            .buttonStyle(.plain)

            HStack {
                Text("Piano Room 1.0")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.mutedSoft)
                Spacer()
                if state.isReady {
                    Text("Движок готов")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(hex: 0x6FAE72))
                }
            }
        }
        .padding(24)
        .frame(width: 520, height: 600)
        .background(Theme.gradient)
        .onAppear {
            // Системный заголовок окна настроек на русском.
            DispatchQueue.main.async {
                for window in NSApp.windows where window.title.contains("Settings") {
                    window.title = "Настройки Piano Room"
                }
            }
        }
    }

    // MARK: - Звук

    private var soundSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.control) {
            sectionTitle("Звук")

            HStack {
                Text("Аудиовыход")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.text)
                Spacer()
                Picker("", selection: outputBinding) {
                    ForEach(state.audioOutputs) { device in
                        Text(device.name).tag(Optional(device.id))
                    }
                }
                .labelsHidden()
                .frame(width: 240, alignment: .trailing)
            }

            HStack {
                Text("Буфер")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.text)
                Spacer()
                Picker("", selection: bufferBinding) {
                    Text("64 — минимум задержки").tag(UInt32(64))
                    Text("128 — баланс").tag(UInt32(128))
                    Text("256 — стабильнее").tag(UInt32(256))
                    Text("512 — максимум стабильности").tag(UInt32(512))
                }
                .labelsHidden()
                .frame(width: 240, alignment: .trailing)
            }

            Button {
                state.noteFromScreen(60)
            } label: {
                Label("Проверить звук", systemImage: "play.circle")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.accentDeep)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Space.group)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.45))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.line, lineWidth: 1)
        )
    }

    // MARK: - MIDI

    private var midiSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.control) {
            sectionTitle("MIDI")

            HStack {
                Text("Вход")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.text)
                Spacer()
                Picker("", selection: sourceBinding) {
                    Text("Не выбран").tag(Optional<Int32>.none)
                    ForEach(state.midiSources) { source in
                        Text(source.name).tag(Optional(source.id))
                    }
                }
                .labelsHidden()
                .frame(width: 240, alignment: .trailing)
            }

            HStack(spacing: 7) {
                Circle()
                    .fill(state.pianoConnected ? Color(hex: 0x6FAE72) : Theme.mutedSoft)
                    .frame(width: 6, height: 6)
                Text(state.pianoConnected ? "Grace CP-250 подключено" : "Пианино не найдено")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.muted)
            }

            Button {
                state.refreshAudioDevices()
                if let piano = state.midiSources.first(where: { $0.name.lowercased().contains("5704") || $0.name.lowercased().contains("piano") }) {
                    state.selectMIDISource(piano)
                }
            } label: {
                Label("Обновить список", systemImage: "arrow.clockwise")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.accentDeep)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Space.group)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.45))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.line, lineWidth: 1)
        )
    }

    // MARK: - Пианино

    private var pianoSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.control) {
            sectionTitle("Встроенный звук пианино")

            Toggle(isOn: Binding(
                get: { !state.localSoundMuted },
                set: { _ in state.toggleLocalSound() }
            )) {
                Text("Звук пианино включён")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.text)
            }
            .toggleStyle(.switch)
            .tint(Theme.accent)
            .disabled(!state.pianoConnected)

            Text("Когда выключен, пианино работает только как клавиатура, а звук даёт Piano Room.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Space.group)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.45))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.line, lineWidth: 1)
        )
    }

    // MARK: - Внутреннее

    private func sectionTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(1.0)
            .foregroundStyle(Theme.muted)
    }

    private var outputBinding: Binding<AudioDeviceID?> {
        Binding(
            get: { state.selectedOutputID },
            set: { newValue in
                guard let id = newValue, let device = state.audioOutputs.first(where: { $0.id == id }) else { return }
                state.selectOutput(device)
            }
        )
    }

    private var sourceBinding: Binding<Int32?> {
        Binding(
            get: { state.selectedSourceID },
            set: { newValue in
                guard let id = newValue, let source = state.midiSources.first(where: { $0.id == id }) else { return }
                state.selectMIDISource(source)
            }
        )
    }

    private var bufferBinding: Binding<UInt32> {
        Binding(
            get: { state.bufferFrames },
            set: { state.setBufferFrames($0) }
        )
    }
}
