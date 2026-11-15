import SwiftUI

struct TopBar: View {
    @Environment(AppState.self) private var state
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        ZStack {
            HStack(spacing: Theme.Space.group) {
                Wordmark(size: 16)
                Spacer(minLength: Theme.Space.group)
                controls
            }

            connectionStatus
        }
        .padding(.horizontal, Theme.Layout.horizontalInset)
        .frame(height: Theme.Layout.headerHeight)
        .background(Theme.background)
        .overlay(alignment: .bottom) {
            Hairline()
        }
    }

    // MARK: - Статус

    private var connectionStatus: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(state.pianoConnected ? Theme.success : Theme.mutedSoft)
                .frame(width: 7, height: 7)
                .overlay {
                    if state.pianoConnected {
                        Circle()
                            .strokeBorder(Theme.success.opacity(0.18), lineWidth: 4)
                    }
                }

            if state.pianoConnected {
                Text("Grace CP-250")
                    .font(Theme.ui(12.5, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text("подключено")
                    .font(Theme.ui(11.5))
                    .foregroundStyle(Theme.muted)
            } else {
                Text("Пианино не подключено")
                    .font(Theme.ui(11.5))
                    .foregroundStyle(Theme.muted)
            }
        }
        .lineLimit(1)
        .fixedSize()
        .accessibilityElement(children: .combine)
    }

    // MARK: - Управление

    private var controls: some View {
        HStack(spacing: 2) {
            outputMenu
            localSoundControl
            Rectangle()
                .fill(Theme.line)
                .frame(width: 1, height: 18)
                .padding(.horizontal, 6)
            IconButton(systemName: "stop.circle", title: "Выключить все ноты") {
                state.panic()
            }
            IconButton(systemName: "gearshape", title: "Настройки") {
                openSettings()
            }
        }
        .fixedSize()
    }

    private var outputMenu: some View {
        Menu {
            ForEach(state.audioOutputs) { device in
                Button {
                    state.selectOutput(device)
                } label: {
                    if device.id == state.selectedOutputID {
                        Label(device.name, systemImage: "checkmark")
                    } else {
                        Text(device.name)
                    }
                }
            }
            Divider()
            Button("Обновить список") {
                state.refreshAudioDevices()
            }
        } label: {
            DeviceMenuLabel(name: state.outputDeviceName)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Аудиовыход")
    }

    private var localSoundControl: some View {
        LocalSoundToggle(
            isOn: !state.localSoundMuted,
            isEnabled: state.pianoConnected
        ) {
            state.toggleLocalSound()
        }
    }
}

// MARK: - Подпись аудиовыхода

private struct DeviceMenuLabel: View {
    let name: String

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "speaker.wave.2")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Theme.muted)

            VStack(alignment: .leading, spacing: 1) {
                Text("Выход")
                    .font(Theme.ui(8.5, weight: .medium))
                    .tracking(0.4)
                    .foregroundStyle(Theme.mutedSoft)
                Text(name)
                    .font(Theme.ui(10.5, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 138, alignment: .leading)
            }

            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(Theme.mutedSoft)
        }
        .padding(.horizontal, 7)
        .frame(height: 34)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovering ? Theme.hover : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }
}

// MARK: - Встроенный звук

private struct LocalSoundToggle: View {
    let isOn: Bool
    let isEnabled: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text("Встроенный звук")
                    .font(Theme.ui(10.5))
                    .foregroundStyle(Theme.textSoft)
                    .lineLimit(1)
                PillSwitch(isOn: isOn)
            }
            .padding(.horizontal, 8)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovering ? Theme.hover : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .help("Встроенный звук пианино")
        .accessibilityLabel("Встроенный звук пианино")
        .accessibilityValue(isOn ? "Включено" : "Выключено")
    }
}
