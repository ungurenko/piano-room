import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        return ZStack {
            Theme.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                TopBar()

                GeometryReader { geometry in
                    let keyboardHeight = min(
                        Theme.Layout.keyboardMaxHeight,
                        max(
                            Theme.Layout.keyboardMinHeight,
                            geometry.size.height * Theme.Layout.keyboardRatio
                        )
                    )

                    VStack(spacing: Theme.Layout.keyboardGap) {
                        HStack(alignment: .top, spacing: Theme.Layout.columnGap) {
                            InstrumentsPanel()
                                .frame(width: Theme.Layout.instrumentsWidth)
                            StageView()
                            EffectsPanel()
                                .frame(width: Theme.Layout.effectsWidth)
                        }
                        .frame(maxHeight: .infinity)

                        KeyboardView()
                            .frame(height: keyboardHeight)
                    }
                    .padding(.horizontal, Theme.Layout.horizontalInset)
                    .padding(.top, Theme.Layout.bodyTop)
                    .padding(.bottom, Theme.Layout.bodyBottom)
                }
            }

            if state.isStarting {
                StartingOverlay()
            }

            if let error = state.startupError {
                ErrorOverlay(message: error)
            }
        }
        .sheet(isPresented: $state.showAllInstruments) {
            AllInstrumentsView()
                .environment(state)
        }
    }
}

// MARK: - Загрузка

private struct StartingOverlay: View {
    var body: some View {
        ZStack {
            Theme.background.opacity(0.94)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                Wordmark(size: 20)

                ProgressView()
                    .controlSize(.small)
                    .tint(Theme.muted)
                    .padding(.top, 6)

                Text("Готовим рояль…")
                    .font(Theme.ui(14, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .padding(.top, 2)

                Text("Загружаем звук, это займёт пару секунд")
                    .font(Theme.ui(11.5))
                    .foregroundStyle(Theme.muted)
            }
        }
    }
}

// MARK: - Ошибка запуска

private struct ErrorOverlay: View {
    @Environment(AppState.self) private var state
    @Environment(\.openSettings) private var openSettings
    let message: String

    var body: some View {
        ZStack {
            Theme.background.opacity(0.94)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(Theme.muted)

                Text("Не получилось запустить звук")
                    .font(Theme.ui(15, weight: .semibold))
                    .foregroundStyle(Theme.text)

                Text(message)
                    .font(Theme.ui(12))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)

                HStack(spacing: 12) {
                    OutlinePillButton(title: "Повторить") {
                        state.retryAudio()
                    }
                    .keyboardShortcut(.defaultAction)

                    Button("Настройки…") {
                        openSettings()
                    }
                    .buttonStyle(.plain)
                    .font(Theme.ui(11.5))
                    .foregroundStyle(Theme.muted)

                    Button("Закрыть") {
                        state.startupError = nil
                    }
                    .buttonStyle(.plain)
                    .font(Theme.ui(11.5))
                    .foregroundStyle(Theme.muted)
                }
                .padding(.top, 6)
            }
            .padding(30)
        }
    }
}
