import SwiftUI

struct EffectsPanel: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(spacing: 13) {
            PanelHeader(title: "Эффекты", trailing: "5")

            reverb
            delay
            chorus
            drive
            equalizer

            Spacer(minLength: 0)

            master
        }
        .panelStyle()
    }

    // MARK: - Секции

    private var reverb: some View {
        EffectSection(
            title: "Реверберация",
            isOn: state.effects.reverbOn,
            toggle: { state.toggleReverb() },
            value: Binding(
                get: { state.effects.reverb },
                set: { state.setReverb($0) }
            )
        )
    }

    private var delay: some View {
        VStack(spacing: 7) {
            EffectSection(
                title: "Дилей",
                isOn: state.effects.delayOn,
                toggle: { state.toggleDelay() },
                value: Binding(
                    get: { state.effects.delay },
                    set: { state.setDelay($0) }
                )
            )
            SubFader(
                title: "Время",
                value: Binding(
                    get: { state.effects.delayTime },
                    set: { state.setDelayTime($0) }
                ),
                isEnabled: state.effects.delayOn
            )
        }
    }

    private var chorus: some View {
        EffectSection(
            title: "Хорус",
            isOn: state.effects.chorusOn,
            toggle: { state.toggleChorus() },
            value: Binding(
                get: { state.effects.chorus },
                set: { state.setChorus($0) }
            )
        )
    }

    private var drive: some View {
        EffectSection(
            title: "Перегруз",
            isOn: state.effects.driveOn,
            toggle: { state.toggleDrive() },
            value: Binding(
                get: { state.effects.drive },
                set: { state.setDrive($0) }
            )
        )
    }

    private var equalizer: some View {
        VStack(spacing: 7) {
            HStack {
                Text("Эквалайзер")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.text)
                Spacer()
                ToggleSwitch(
                    isOn: Binding(
                        get: { state.effects.eqOn },
                        set: { _ in state.toggleEQ() }
                    )
                )
            }
            SubFader(
                title: "Низ",
                value: Binding(
                    get: { state.effects.eqLow },
                    set: { state.setEQ(low: $0) }
                ),
                isEnabled: state.effects.eqOn
            )
            SubFader(
                title: "Верх",
                value: Binding(
                    get: { state.effects.eqHigh },
                    set: { state.setEQ(high: $0) }
                ),
                isEnabled: state.effects.eqOn
            )
        }
    }

    // MARK: - Мастер

    private var master: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Громкость")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.text)
                Spacer()
                Text("\(Int(state.masterVolume * 100))%")
                    .font(.system(size: 11, weight: .regular).monospacedDigit())
                    .foregroundStyle(Theme.muted)
            }
            Fader(
                value: Binding(
                    get: { state.masterVolume },
                    set: { state.setMasterVolume($0) }
                )
            )
        }
        .padding(.top, 12)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Theme.line)
                .frame(height: 1)
        }
    }
}

// MARK: - Секция эффекта

private struct EffectSection: View {
    let title: String
    let isOn: Bool
    let toggle: () -> Void
    @Binding var value: Double

    var body: some View {
        VStack(spacing: 7) {
            HStack {
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.text)
                Spacer()
                ToggleSwitch(
                    isOn: Binding(get: { isOn }, set: { _ in toggle() })
                )
            }
            Fader(value: $value)
                .disabled(!isOn)
                .opacity(isOn ? 1 : 0.45)
        }
    }
}

// MARK: - Дополнительный ползунок

private struct SubFader: View {
    let title: String
    @Binding var value: Double
    let isEnabled: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.muted)
                .frame(width: 38, alignment: .leading)
            Fader(value: $value)
                .disabled(!isEnabled)
                .opacity(isEnabled ? 1 : 0.45)
        }
        .padding(.leading, 2)
    }
}
