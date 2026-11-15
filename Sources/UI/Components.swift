import SwiftUI

// MARK: - Линии

/// Волосяная линия вместо карточки: интерфейс держится на воздухе и тонких границах.
struct Hairline: View {
    var color: Color = Theme.line
    var height: CGFloat = 1

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(height: height)
    }
}

// MARK: - Словесный знак

struct Wordmark: View {
    var size: CGFloat = 16

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Text("Piano Room")
                .font(Theme.display(size))
                .tracking(-0.01 * size)
                .foregroundStyle(Theme.text)
                .fixedSize()
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(Theme.accent)
                .frame(width: max(5, size * 0.34), height: max(5, size * 0.34))
                .offset(y: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Piano Room")
    }
}

// MARK: - Ползунок

/// Тонкий ползунок в духе «Белого листа»: линия 2 pt и светлая ручка.
struct MinimalFader: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var title: String
    var isEnabled = true
    var step: Double = 0.02

    var body: some View {
        GeometryReader { geometry in
            let width = max(1, geometry.size.width)
            let progress = Self.progress(value: value, in: range)
            let thumbSize: CGFloat = 11
            let thumbX = min(max(0, width * progress - thumbSize / 2), width - thumbSize)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.line)
                    .frame(height: 2)

                Capsule()
                    .fill(isEnabled ? Theme.text : Theme.mutedSoft.opacity(0.45))
                    .frame(width: max(0, width * progress), height: 2)

                Circle()
                    .fill(Color.white)
                    .overlay(
                        Circle()
                            .strokeBorder(
                                isEnabled ? Theme.text : Theme.mutedSoft.opacity(0.7),
                                lineWidth: 1.5
                            )
                    )
                    .frame(width: thumbSize, height: thumbSize)
                    .shadow(color: .black.opacity(0.08), radius: 1, x: 0, y: 1)
                    .offset(x: thumbX)
            }
            .frame(height: 16)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        guard isEnabled else { return }
                        let ratio = min(max(0, gesture.location.x / width), 1)
                        value = range.lowerBound + Double(ratio) * (range.upperBound - range.lowerBound)
                    }
            )
        }
        .frame(height: 16)
        .opacity(isEnabled ? 1 : 0.5)
        .allowsHitTesting(isEnabled)
        .accessibilityRepresentation {
            Slider(value: $value, in: range) {
                Text(title)
            }
            .labelsHidden()
            .accessibilityLabel(title)
        }
    }

    private static func progress(value: Double, in range: ClosedRange<Double>) -> CGFloat {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return CGFloat((value - range.lowerBound) / span)
    }
}

// MARK: - Точечный переключатель эффекта

/// Кружок 16 pt: контур — эффект выключен, красная точка — включён.
struct EffectDotToggle: View {
    let isOn: Bool
    let title: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isHovering ? Theme.hover : Color.clear)
                    .frame(width: 22, height: 22)

                Circle()
                    .strokeBorder(isOn ? Theme.accent : Color(hex: 0xC9C9D2), lineWidth: 1.5)
                    .frame(width: 14, height: 14)

                if isOn {
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 7, height: 7)
                }
            }
            .frame(width: 22, height: 22)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(isOn ? "Выключить эффект" : "Включить эффект")
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "Включено" : "Выключено")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Тумблер в шапке

struct PillSwitch: View {
    let isOn: Bool

    var body: some View {
        Capsule()
            .fill(isOn ? Theme.text : Color(hex: 0xE4E4EA))
            .frame(width: 27, height: 16)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(Color.white)
                    .frame(width: 12, height: 12)
                    .padding(2)
                    .shadow(color: .black.opacity(0.14), radius: 1, x: 0, y: 1)
            }
            .animation(.easeOut(duration: 0.16), value: isOn)
    }
}

// MARK: - Кнопка-иконка

struct IconButton: View {
    let systemName: String
    let title: String
    var action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(isHovering ? Theme.text : Theme.muted)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isHovering ? Theme.hover : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(title)
        .accessibilityLabel(title)
    }
}

// MARK: - Кнопка-пилюля

/// Контурная кнопка действия: на наведении заливается чернилами.
struct OutlinePillButton: View {
    let title: String
    var systemImage: String? = nil
    var isEnabled = true
    var action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 9, weight: .bold))
                }
                Text(title)
                    .font(Theme.ui(11.5, weight: .medium))
            }
            .foregroundStyle(isHovering ? Color.white : Theme.text)
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(
                Capsule()
                    .fill(isHovering ? Theme.text : Color.clear)
            )
            .overlay(
                Capsule()
                    .strokeBorder(Theme.text.opacity(isHovering ? 1 : 0.85), lineWidth: 1)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
    }
}
