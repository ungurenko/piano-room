import SwiftUI

struct EffectsPanel: View {
    @Environment(AppState.self) private var state
    @State private var reverbExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(spacing: 0) {
                    reverb
                    Hairline(color: Theme.lineSoft)
                    delay
                    Hairline(color: Theme.lineSoft)
                    chorus
                    Hairline(color: Theme.lineSoft)
                    drive
                    Hairline(color: Theme.lineSoft)
                    equalizer
                }
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: .infinity, alignment: .top)

            volume
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Шапка

    private var header: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Эффекты")
                    .font(Theme.ui(12.5, weight: .medium))
                    .foregroundStyle(Theme.textSoft)
                Spacer()
                Text("5")
                    .font(Theme.ui(10))
                    .foregroundStyle(Theme.mutedSoft)
            }
            .padding(.bottom, 10)

            Hairline()
        }
    }

    // MARK: - Эффекты

    private var reverb: some View {
        VStack(spacing: 8) {
            effectRow(
                title: "Реверберация",
                isOn: state.effects.reverbOn,
                toggle: { state.toggleReverb() },
                value: Binding(get: { state.effects.reverb }, set: { state.setReverb($0) })
            )
            Picker("Пространство", selection: Binding(
                get: { state.effects.reverbParameters.presetID },
                set: { state.selectReverbPreset($0) }
            )) {
                ForEach(ReverbParameters.presets) { preset in
                    Text(preset.name).tag(preset.id)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .accessibilityLabel("Пространство реверберации")
            .frame(maxWidth: .infinity, alignment: .leading)

            DisclosureGroup(isExpanded: $reverbExpanded) {
                VStack(spacing: 8) {
                    reverbFader("Хвост", keyPath: \.decaySeconds, range: 0.3...20, unit: "с")
                    reverbFader("Размер", keyPath: \.size)
                    reverbFader("Пауза", keyPath: \.preDelayMs, range: 0...100, unit: "мс")
                    reverbFader("Тембр", keyPath: \.tone)
                    reverbFader("Ширина", keyPath: \.width)
                    reverbFader("Движение", keyPath: \.modulation)
                    Button("Сбросить пресет") { state.resetReverbPreset() }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.textSoft)
                        .disabled(!state.effects.reverbParameters.isModified)
                }
                .padding(.top, 8)
            } label: {
                Text(state.effects.reverbParameters.isModified ? "Настроить · изменён" : "Настроить")
            }
            .font(Theme.ui(10.5))
            .foregroundStyle(Theme.textSoft)
        }
        .padding(.bottom, 8)
    }

    private func reverbFader(_ title: String, keyPath: WritableKeyPath<ReverbParameters, Float>,
                             range: ClosedRange<Float> = 0...1, unit: String = "%") -> some View {
        let parameter = state.effects.reverbParameters[keyPath: keyPath]
        let display = unit == "%" ? parameter * 100 : parameter
        return VStack(spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(unit == "с" ? String(format: "%.1f %@", display, unit) : "\(Int(display.rounded())) \(unit)")
            }
            MinimalFader(value: Binding(
                get: { Double((state.effects.reverbParameters[keyPath: keyPath] - range.lowerBound) / (range.upperBound - range.lowerBound)) },
                set: { state.updateReverbParameter(keyPath, value: range.lowerBound + Float($0) * (range.upperBound - range.lowerBound)) }
            ), title: title, isEnabled: state.effects.reverbOn)
        }
    }

    private var delay: some View {
        VStack(spacing: 0) {
            effectRow(
                title: "Дилей",
                isOn: state.effects.delayOn,
                toggle: { state.toggleDelay() },
                value: Binding(
                    get: { state.effects.delay },
                    set: { state.setDelay($0) }
                )
            )

            subFader(
                title: "Время",
                value: Binding(
                    get: { state.effects.delayTime },
                    set: { state.setDelayTime($0) }
                ),
                isEnabled: state.effects.delayOn
            )
            .padding(.bottom, 9)
        }
    }

    private var chorus: some View {
        effectRow(
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
        effectRow(
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
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    EffectDotToggle(
                        isOn: state.effects.eqOn,
                        title: "Эквалайзер"
                    ) {
                        state.toggleEQ()
                    }
                    Text("Эквалайзер")
                        .font(Theme.ui(12.5, weight: .medium))
                        .foregroundStyle(Theme.text)
                    Spacer()
                }
            }
            .padding(.vertical, 9)

            subFader(
                title: "Низ",
                value: Binding(
                    get: { state.effects.eqLow },
                    set: { state.setEQ(low: $0) }
                ),
                isEnabled: state.effects.eqOn
            )
            .padding(.bottom, 7)

            subFader(
                title: "Верх",
                value: Binding(
                    get: { state.effects.eqHigh },
                    set: { state.setEQ(high: $0) }
                ),
                isEnabled: state.effects.eqOn
            )
            .padding(.bottom, 9)
        }
    }

    // MARK: - Громкость

    private var volume: some View {
        VStack(spacing: 0) {
            Hairline()

            VStack(spacing: 9) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Громкость")
                        .font(Theme.ui(12.5, weight: .medium))
                        .foregroundStyle(Theme.textSoft)
                    Spacer()
                    Text("\(Int((state.masterVolume * 100).rounded()))%")
                        .font(Theme.display(19))
                        .foregroundStyle(Theme.text)
                }

                MinimalFader(
                    value: Binding(
                        get: { state.masterVolume },
                        set: { state.setMasterVolume($0) }
                    ),
                    title: "Общая громкость"
                )
            }
            .padding(.top, 12)
        }
    }

    // MARK: - Строки

    private func effectRow(
        title: String,
        isOn: Bool,
        toggle: @escaping () -> Void,
        value: Binding<Double>
    ) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                EffectDotToggle(isOn: isOn, title: title, action: toggle)
                Text(title)
                    .font(Theme.ui(12.5, weight: .medium))
                    .foregroundStyle(isOn ? Theme.text : Theme.text.opacity(0.6))
                Spacer()
            }

            MinimalFader(
                value: value,
                title: title,
                isEnabled: isOn
            )
            .padding(.top, 7)
            .padding(.leading, 30)
        }
        .padding(.vertical, 9)
    }

    private func subFader(
        title: String,
        value: Binding<Double>,
        isEnabled: Bool
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(Theme.ui(10.5))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
                .fixedSize()
                .frame(width: 38, alignment: .leading)
            MinimalFader(
                value: value,
                title: title,
                isEnabled: isEnabled
            )
        }
        .padding(.leading, 30)
    }
}
