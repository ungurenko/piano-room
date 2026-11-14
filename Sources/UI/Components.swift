import SwiftUI

// MARK: - Панель

struct PanelStyle: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
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
            .shadow(color: Theme.shadowSoft, radius: 16, x: 0, y: 8)
    }
}

extension View {
    func panelStyle(padding: CGFloat = 16) -> some View {
        modifier(PanelStyle(padding: padding))
    }
}

// MARK: - Заголовок панели

struct PanelHeader: View {
    let title: String
    var trailing: String? = nil

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(1.1)
                .foregroundStyle(Theme.muted)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.system(size: 10.5, weight: .regular))
                    .foregroundStyle(Theme.mutedSoft)
            }
        }
    }
}

// MARK: - Тумблер

struct ToggleSwitch: View {
    @Binding var isOn: Bool
    var tint: Color = Theme.accent

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.16)) {
                isOn.toggle()
            }
        } label: {
            Capsule()
                .fill(isOn ? tint : Theme.line.opacity(0.85))
                .frame(width: 34, height: 20)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 16, height: 16)
                        .padding(2)
                        .shadow(color: .black.opacity(0.16), radius: 1.5, x: 0, y: 1)
                }
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.16), value: isOn)
    }
}

// MARK: - Ползунок

struct Fader: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var tint: Color = Theme.accent

    var body: some View {
        Slider(value: $value, in: range)
            .controlSize(.small)
            .tint(tint)
    }
}

// MARK: - Иконка приложения

struct AppLogo: View {
    var size: CGFloat = 34

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: 0xD99A63), Color(hex: 0xB06F3C)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            HStack(spacing: size * 0.14) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: size * 0.05, style: .continuous)
                        .fill(Color(hex: 0xFFF6E9))
                        .frame(width: size * 0.13, height: size * 0.53)
                }
            }
            .offset(y: size * 0.03)
        }
        .frame(width: size, height: size)
        .shadow(color: Color(hex: 0xA0693A).opacity(0.24), radius: 6, x: 0, y: 3)
    }
}

// MARK: - Кнопка в шапке

struct ToolbarPill: View {
    var icon: String? = nil
    let title: String
    var trailingChevron = false

    var body: some View {
        HStack(spacing: 7) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.muted)
            }
            Text(title)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Theme.text)
            if trailingChevron {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.mutedSoft)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.line, lineWidth: 1)
        )
    }
}
