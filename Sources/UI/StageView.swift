import SwiftUI

struct StageView: View {
    @Environment(AppState.self) private var state

    private static let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    var body: some View {
        VStack(spacing: 0) {
            topRow

            Spacer(minLength: 20)

            centerContent

            bottomContent
                .padding(.top, 20)

            Spacer(minLength: 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Верх

    private var topRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.group) {
            Text("Сейчас играет")
                .font(Theme.ui(10.5))
                .foregroundStyle(Theme.muted)
                .fixedSize()

            Spacer(minLength: Theme.Space.group)

            Text("\(state.sampleRateLabel) · буфер \(state.bufferFrames) · ≈ \(max(1, Int(state.latencyMilliseconds.rounded()))) мс")
                .font(Theme.ui(10.5))
                .foregroundStyle(Theme.muted)
                .fixedSize()
        }
    }

    // MARK: - Центр

    private var centerContent: some View {
        VStack(spacing: 0) {
            Text(displayName)
                .font(Theme.display(nameSize(for: displayName)))
                .tracking(-0.03 * nameSize(for: displayName))
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .contentTransition(.opacity)

            Text(state.loadingInstrumentName == nil ? state.currentInstrument.subtitle : "")
                .font(Theme.ui(11.5))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.top, 10)
                .contentTransition(.opacity)

            liveArea
                .padding(.top, 14)
        }
        .animation(.easeInOut(duration: 0.18), value: state.currentInstrument.id)
        .animation(.easeInOut(duration: 0.18), value: state.loadingInstrumentName)
    }

    private var liveArea: some View {
        Group {
            if state.loadingInstrumentName != nil {
                ProgressView("Загружаем инструмент…")
                    .font(Theme.ui(12))
                    .tint(Theme.accent)
            } else if state.runningNotes.isEmpty {
                Text(idleHint)
                    .font(Theme.ui(12))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            } else {
                HStack(alignment: .center, spacing: 14) {
                    ForEach(state.runningNotes.sorted().prefix(8), id: \.self) { note in
                        Text(noteName(note))
                            .font(Theme.ui(22, weight: .medium))
                            .foregroundStyle(Theme.text)
                            .overlay(alignment: .bottom) {
                                Rectangle()
                                    .fill(Theme.accent)
                                    .frame(height: 2)
                                    .offset(y: 4)
                            }
                    }

                    if state.sustainDown {
                        Text("Педаль")
                            .font(Theme.ui(10.5, weight: .medium))
                            .foregroundStyle(Theme.muted)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .overlay(
                                Capsule()
                                    .strokeBorder(Theme.line, lineWidth: 1)
                            )
                    }
                }
            }
        }
        .frame(height: 58)
        .animation(.easeOut(duration: 0.12), value: state.runningNotes)
    }

    // MARK: - Низ

    private var bottomContent: some View {
        VStack(spacing: 10) {
            OutlinePillButton(title: "Проверить звук", systemImage: "play.fill") {
                state.noteFromScreen(60, velocity: 100)
            }
            .disabled(!state.isReady)

            Text("Grace CP-250 · 88 клавиш")
                .font(Theme.ui(9.5))
                .foregroundStyle(Theme.mutedSoft)
        }
    }

    // MARK: - Тексты

    private var displayName: String {
        state.loadingInstrumentName ?? state.currentInstrument.name
    }

    private var idleHint: String {
        if state.pianoConnected {
            return "Нажми клавишу — звук уже здесь"
        }
        return "Подключи пианино USB-кабелем — звук пойдёт в его динамики"
    }

    private func nameSize(for name: String) -> CGFloat {
        switch name.count {
        case 19...: return 42
        case 15...18: return 48
        case 12...14: return 56
        case 9...11: return 66
        default: return 82
        }
    }

    private func noteName(_ note: UInt8) -> String {
        let index = Int(note) % 12
        let octave = Int(note) / 12 - 1
        return "\(Self.noteNames[index])\(octave)"
    }
}
