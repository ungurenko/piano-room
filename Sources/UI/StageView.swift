import SwiftUI

struct StageView: View {
    @EnvironmentObject private var state: AppState

    private let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    var body: some View {
        VStack(spacing: 0) {
            topRow
                .frame(minHeight: Theme.Space.section)

            Spacer(minLength: Theme.Space.section)

            VStack(spacing: Theme.Space.related) {
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
                    .multilineTextAlignment(.center)
                    .contentTransition(.opacity)

                noteChips
                    .padding(.top, Theme.Space.related)
            }
            .animation(.easeInOut(duration: 0.18), value: state.currentInstrument.id)

            Spacer(minLength: Theme.Space.section)

            pianoHint
                .opacity(!state.pianoConnected && state.runningNotes.isEmpty ? 1 : 0)
                .allowsHitTesting(!state.pianoConnected && state.runningNotes.isEmpty)
                .accessibilityHidden(state.pianoConnected || !state.runningNotes.isEmpty)
        }
        .padding(Theme.Space.group)
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
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Space.group) {
                stageLabel
                Spacer(minLength: Theme.Space.group)
                audioStatus
            }
            VStack(alignment: .leading, spacing: Theme.Space.related) {
                stageLabel
                audioStatus
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var stageLabel: some View {
        Text("СЕЙЧАС ИГРАЕТ")
            .font(.system(size: 10.5, weight: .semibold))
            .tracking(1.1)
            .foregroundStyle(Theme.mutedSoft)
            .fixedSize()
    }

    private var audioStatus: some View {
        HStack(spacing: Theme.Space.tight) {
            Text(state.sampleRateLabel)
            Text("·")
            Text("буфер \(state.bufferFrames)")
            Text("·")
            Text("≈ \(max(1, Int(state.latencyMilliseconds.rounded()))) мс")
        }
        .font(.system(size: 10.5))
        .foregroundStyle(Theme.muted)
        .fixedSize()
        .padding(.horizontal, Theme.Space.related)
        .padding(.vertical, Theme.Space.tight)
        .background(Capsule().fill(Color.white.opacity(0.55)))
        .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
    }

    private var pianoHint: some View {
        VStack(spacing: Theme.Space.related) {
            Text("Подключи пианино USB-кабелем — звук пойдёт в его динамики")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.mutedSoft)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                state.noteFromScreen(60, velocity: 100)
            } label: {
                HStack(spacing: Theme.Space.tight) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 9, weight: .bold))
                    Text("Проверить звук")
                        .font(.system(size: 11.5, weight: .medium))
                }
                .foregroundStyle(Theme.accentDeep)
                .padding(.horizontal, 12)
                .padding(.vertical, Theme.Space.related)
                .background(
                    Capsule().fill(Theme.accent.opacity(0.12))
                )
                .overlay(
                    Capsule().strokeBorder(Theme.accent.opacity(0.2), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.top, Theme.Space.related)
    }

    private var noteChips: some View {
        HStack(spacing: Theme.Space.tight) {
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
        .frame(height: Theme.Space.spacious)
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
