import AppKit
import CoreAudio
import SwiftUI

/// Окно настроек в теме «Белый лист»: белый холст, чернильные подписи,
/// волосяные линии вместо карточек и один красный акцент в текстовых действиях.
struct SettingsView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            soundSection
            sectionDivider
            midiSection
            sectionDivider
            pianoSection

            Spacer(minLength: 24)

            resetButton
                .padding(.bottom, 16)

            footer
        }
        .padding(24)
        .frame(width: 520, height: 600)
        .background(Theme.background)
        .onAppear {
            // Системный заголовок окна настроек на русском.
            Task { @MainActor in
                for window in NSApp.windows where window.title.contains("Settings") {
                    window.title = "Настройки Piano Room"
                }
            }
        }
    }

    // MARK: - Звук

    private var soundSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("Звук")

            settingRow("Аудиовыход") {
                Picker("Аудиовыход", selection: outputBinding) {
                    ForEach(state.audioOutputs) { device in
                        Text(device.name).tag(Optional(device.id))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .frame(width: 240, alignment: .trailing)
            }

            Hairline(color: Theme.line)

            settingRow("Буфер") {
                Picker("Размер буфера", selection: bufferBinding) {
                    Text("64 — минимум задержки").tag(UInt32(64))
                    Text("128 — баланс").tag(UInt32(128))
                    Text("256 — стабильнее").tag(UInt32(256))
                    Text("512 — максимум стабильности").tag(UInt32(512))
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .frame(width: 240, alignment: .trailing)
            }

            testSoundButton
                .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Текстовое действие секции «Звук»: без фона и рамки, чернильный акцент.
    private var testSoundButton: some View {
        Button {
            state.noteFromScreen(60)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "play.fill")
                    .font(.system(size: 9, weight: .medium))
                Text("Проверить звук")
                    .font(Theme.ui(11.5, weight: .medium))
            }
            .foregroundStyle(Theme.accentDeep)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - MIDI

    private var midiSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("MIDI")

            settingRow("Вход") {
                Picker("MIDI-вход", selection: sourceBinding) {
                    Text("Не выбран").tag(Optional<Int32>.none)
                    ForEach(state.midiSources) { source in
                        Text(source.name).tag(Optional(source.id))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .frame(width: 240, alignment: .trailing)
            }

            midiStatusRow
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var midiStatusRow: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(state.pianoConnected ? Theme.success : Theme.mutedSoft)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)

            Text(state.pianoConnected ? "Grace CP-250 подключено" : "Пианино не найдено")
                .font(Theme.ui(11.5))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)

            Spacer(minLength: 12)

            Button {
                state.refreshAudioDevices()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .medium))
                    Text("Обновить список")
                        .font(Theme.ui(11.5, weight: .medium))
                }
                .foregroundStyle(Theme.accentDeep)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Встроенный звук пианино

    private var pianoSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("Встроенный звук пианино")

            settingRow("Звук пианино включён") {
                Toggle("Звук пианино включён", isOn: localSoundBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(Theme.text)
                    .disabled(!state.pianoConnected)
            }

            Text("Когда выключен, пианино работает только как клавиатура, а звук даёт Piano Room.")
                .font(Theme.ui(11))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Нижняя часть

    private var resetButton: some View {
        Button {
            state.resetSettings()
        } label: {
            Label("Сбросить настройки", systemImage: "arrow.counterclockwise")
                .font(Theme.ui(11.5))
                .foregroundStyle(Theme.muted)
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 0) {
            Hairline(color: Theme.line)

            HStack(spacing: 8) {
                Text("Piano Room 1.0")
                    .font(Theme.ui(11))
                    .foregroundStyle(Theme.mutedSoft)

                Spacer(minLength: 12)

                if state.isReady {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Theme.success)
                            .frame(width: 5, height: 5)
                            .accessibilityHidden(true)
                        Text("Движок готов")
                            .font(Theme.ui(11))
                            .foregroundStyle(Theme.muted)
                    }
                }
            }
            .padding(.top, 12)
        }
    }

    // MARK: - Каркас секций

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(Theme.ui(12.5, weight: .semibold))
            .foregroundStyle(Theme.text)
            .padding(.bottom, 8)
    }

    /// Строка настройки: подпись слева, контрол справа, высота 36 + 6 pt воздуха.
    private func settingRow<Control: View>(
        _ title: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(Theme.ui(12.5))
                .foregroundStyle(Theme.text)
                .fixedSize()

            Spacer(minLength: 12)

            control()
        }
        .frame(height: 36)
        .padding(.vertical, 6)
    }

    /// Между секциями 26 pt и волосяная линия по центру воздуха.
    private var sectionDivider: some View {
        Hairline(color: Theme.line)
            .padding(.top, 13)
            .padding(.bottom, 12)
    }

    // MARK: - Биндинги

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
                guard let id = newValue else {
                    state.disconnectMIDISource()
                    return
                }
                guard let source = state.midiSources.first(where: { $0.id == id }) else { return }
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

    private var localSoundBinding: Binding<Bool> {
        Binding(
            get: { !state.localSoundMuted },
            set: { _ in state.toggleLocalSound() }
        )
    }
}
