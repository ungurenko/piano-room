import SwiftUI

struct StageView: View {
    @EnvironmentObject private var state: AppState

    private let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    var body: some View {
        VStack(spacing: 0) {
            topRow

            Spacer(minLength: 12)

            VStack(spacing: 8) {
                Text(state.currentInstrument.name)
                    .font(.system(size: 44, weight: .semibold))
                    .tracking(-1.1)
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.opacity)

                Text(state.currentInstrument.subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                    .contentTransition(.opacity)

                noteChips

                if !state.pianoConnected && state.runningNotes.isEmpty {
                    pianoHint
                }
            }
            .animation(.easeInOut(duration: 0.18), value: state.currentInstrument.id)

            Spacer(minLength: 12)
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(stageBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Theme.line, lineWidth: 1)
        )
        .shadow(color: Theme.shadowSoft, radius: 16, x: 0, y: 8)
    }

    private var topRow: some View {
        HStack {
            Text("СЕЙЧАС ИГРАЕТ")
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(1.1)
                .foregroundStyle(Theme.mutedSoft)

            Spacer()

            HStack(spacing: 6) {
                Text("\(state.sampleRateLabel)")
                Text("·")
                Text("буфер \(state.bufferFrames)")
                Text("·")
                Text("≈ \(max(1, Int(state.latencyMilliseconds.rounded()))) мс")
            }
            .font(.system(size: 10.5))
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(Color.white.opacity(0.55))
            )
            .overlay(
                Capsule().strokeBorder(Theme.line, lineWidth: 1)
            )
        }
    }

    private var pianoHint: some View {
        VStack(spacing: 8) {
            Text("Подключи пианино USB-кабелем — звук пойдёт в его динамики")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.mutedSoft)

            Button {
                state.noteFromScreen(60, velocity: 100)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 9, weight: .bold))
                    Text("Проверить звук")
                        .font(.system(size: 11.5, weight: .medium))
                }
                .foregroundStyle(Theme.accentDeep)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(Theme.accent.opacity(0.12))
                )
                .overlay(
                    Capsule().strokeBorder(Theme.accent.opacity(0.2), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 4)
    }

    private var noteChips: some View {
        HStack(spacing: 6) {
            if state.runningNotes.isEmpty {
                if state.pianoConnected {
                    Text("Нажми клавишу — звук уже здесь")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.mutedSoft)
                        .padding(.vertical, 5)
                }
            } else {
                ForEach(state.runningNotes.sorted().prefix(8), id: \.self) { note in
                    Text(noteName(note))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.accentDeep)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Theme.accent.opacity(0.14))
                        )
                }
                if state.sustainDown {
                    Text("Педаль")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.accentDeep)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Theme.accent.opacity(0.14))
                        )
                }
            }
        }
        .frame(height: 26)
        .animation(.easeOut(duration: 0.12), value: state.runningNotes)
    }

    private var stageBackground: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: 0xFFFDF8), Color(hex: 0xF7EDDD)],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(
                colors: [Color(hex: 0xFBF0DD), Color.clear],
                center: .bottom,
                startRadius: 20,
                endRadius: 420
            )
            Circle()
                .fill(Color(hex: 0xFDF6EA).opacity(0.9))
                .frame(width: 460, height: 460)
                .blur(radius: 60)
                .offset(x: -260, y: -190)
        }
    }

    private func noteName(_ note: UInt8) -> String {
        let index = Int(note) % 12
        let octave = Int(note) / 12 - 1
        return "\(noteNames[index])\(octave)"
    }
}
