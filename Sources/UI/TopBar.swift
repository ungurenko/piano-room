import SwiftUI

struct TopBar: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        HStack(spacing: 18) {
            brand
            Spacer(minLength: 8)
            connectionStatus
            Spacer(minLength: 8)
            controls
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Theme.panel.opacity(0.55))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Theme.line, lineWidth: 1)
        )
        .shadow(color: Theme.shadowSoft, radius: 14, x: 0, y: 7)
    }

    // MARK: - Бренд

    private var brand: some View {
        HStack(spacing: 11) {
            AppLogo(size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text("Piano Room")
                    .font(.system(size: 15, weight: .semibold))
                    .tracking(-0.2)
                    .foregroundStyle(Theme.text)
                Text("Твоё пианино, твои звуки")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
            }
        }
        .fixedSize()
        .layoutPriority(1)
    }

    // MARK: - Статус

    private var connectionStatus: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(state.pianoConnected ? Color(hex: 0x6FAE72) : Theme.mutedSoft)
                .frame(width: 7, height: 7)
                .overlay(
                    Circle()
                        .stroke(state.pianoConnected ? Color(hex: 0x6FAE72).opacity(0.18) : .clear, lineWidth: 4)
                )

            if state.pianoConnected {
                HStack(spacing: 4) {
                    Text("Grace CP-250")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text("подключено")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                }
            } else {
                Text("Пианино не подключено")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
            }
        }
        .lineLimit(1)
    }

    // MARK: - Управление

    private var controls: some View {
        HStack(spacing: 10) {
            outputMenu
            localSoundControl
            panicButton
            settingsButton
        }
        .fixedSize()
        .layoutPriority(1)
    }

    private var panicButton: some View {
        Button {
            state.panic()
        } label: {
            Image(systemName: "stop.circle")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.muted)
                .frame(width: 34, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.55))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Theme.line, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help("Выключить все ноты")
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
            ToolbarPill(
                icon: "speaker.wave.2",
                title: state.outputDeviceName,
                trailingChevron: true
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var localSoundControl: some View {
        HStack(spacing: 9) {
            Image(systemName: "pianokeys")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.muted)
            Text("Встроенный звук")
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
            ToggleSwitch(
                isOn: Binding(
                    get: { !state.localSoundMuted },
                    set: { _ in state.toggleLocalSound() }
                )
            )
            .disabled(!state.pianoConnected)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.45))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.line, lineWidth: 1)
        )
        .opacity(state.pianoConnected ? 1 : 0.55)
    }

    private var settingsButton: some View {
        Button {
            openSettings()
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.muted)
                .frame(width: 34, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.55))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Theme.line, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help("Настройки")
    }
}
