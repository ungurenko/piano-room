import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        ZStack {
            Theme.gradient
                .ignoresSafeArea()

            // Мягкие световые пятна на фоне.
            Circle()
                .fill(Theme.accentPale.opacity(0.55))
                .frame(width: 620, height: 620)
                .blur(radius: 140)
                .offset(x: -420, y: -300)
            Circle()
                .fill(Color(hex: 0xF8EEDF).opacity(0.7))
                .frame(width: 520, height: 520)
                .blur(radius: 130)
                .offset(x: 460, y: -240)

            VStack(spacing: 14) {
                TopBar()

                HStack(spacing: 14) {
                    InstrumentsPanel()
                        .frame(width: 268)
                    StageView()
                    EffectsPanel()
                        .frame(width: 306)
                }
                .frame(minHeight: 320)

                KeyboardView()
                    .frame(height: 186)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .padding(.top, 12)

            if state.isStarting {
                StartingOverlay()
            }

            if let error = state.startupError {
                ErrorOverlay(message: error)
            }
        }
        .sheet(isPresented: $state.showAllInstruments) {
            AllInstrumentsView()
                .environmentObject(state)
        }
    }
}

// MARK: - Загрузка

private struct StartingOverlay: View {
    @State private var pulse = false

    var body: some View {
        ZStack {
            Color(hex: 0xF5EFE5).opacity(0.72)
                .ignoresSafeArea()
            VStack(spacing: 18) {
                AppLogo(size: 58)
                    .scaleEffect(pulse ? 1.04 : 0.98)
                    .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: pulse)
                Text("Готовим рояль…")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.text)
                Text("Загружаем звук, это займёт пару секунд")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
            }
            .padding(34)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Theme.panel.opacity(0.9))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Theme.line, lineWidth: 1)
            )
            .shadow(color: Theme.shadow, radius: 30, x: 0, y: 14)
        }
        .onAppear { pulse = true }
    }
}

private struct ErrorOverlay: View {
    let message: String

    var body: some View {
        ZStack {
            Color(hex: 0xF5EFE5).opacity(0.8)
                .ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(Theme.accentDeep)
                Text("Не получилось запустить звук")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
            .padding(30)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Theme.panel.opacity(0.95))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Theme.line, lineWidth: 1)
            )
        }
    }
}
