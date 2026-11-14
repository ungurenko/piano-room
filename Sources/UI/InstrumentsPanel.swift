import SwiftUI

extension Instrument {
    var symbolName: String {
        switch id {
        case "grand-salamander", "gm-0", "gm-1", "gm-2", "gm-3": return "pianokeys"
        case "gm-4", "gm-5", "gm-6", "gm-7": return "pianokeys.inverse"
        case "gm-16", "gm-17", "gm-18", "gm-19", "gm-20", "gm-21", "gm-22", "gm-23": return "music.note.list"
        case "gm-48", "gm-49", "gm-50", "gm-51": return "music.quarternote.3"
        default:
            switch category {
            case .piano, .chromatic: return "pianokeys"
            case .organ: return "music.note.list"
            case .guitar: return "guitars"
            case .bass: return "waveform.path"
            case .strings, .ensemble: return "music.quarternote.3"
            case .brass, .reed: return "music.mic"
            case .pipe: return "wind"
            case .synthLead, .synthPad, .synthFX: return "waveform"
            case .ethnic: return "globe"
            case .percussive: return "circle.grid.2x2"
            case .soundFX: return "sparkles"
            }
        }
    }
}

struct InstrumentsPanel: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(spacing: 12) {
            PanelHeader(title: "Инструменты", trailing: "\(InstrumentCatalog.favorites.count) из 128")

            VStack(spacing: 5) {
                ForEach(Array(InstrumentCatalog.favorites.enumerated()), id: \.element.id) { index, instrument in
                    InstrumentRow(
                        instrument: instrument,
                        isActive: state.currentInstrument.id == instrument.id,
                        shortcut: index < 6 ? String(index + 1) : nil
                    ) {
                        state.selectInstrument(instrument)
                    }
                }
            }

            Spacer(minLength: 0)

            Button {
                state.showAllInstruments = true
            } label: {
                HStack {
                    Text("Все 128 инструментов")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.text)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.55))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Theme.line, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .keyboardShortcut("0", modifiers: .command)
        }
        .panelStyle()
    }
}

private struct InstrumentRow: View {
    let instrument: Instrument
    let isActive: Bool
    var shortcut: String?
    let action: () -> Void

    var body: some View {
        if let key = shortcutKey {
            row.keyboardShortcut(key, modifiers: .command)
        } else {
            row
        }
    }

    private var shortcutKey: KeyEquivalent? {
        guard let shortcut, let character = shortcut.first else { return nil }
        return KeyEquivalent(character)
    }

    private var row: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Theme.accent.opacity(isActive ? 0.16 : 0.08))
                    Image(systemName: instrument.symbolName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.accent)
                }
                .frame(width: 26, height: 26)

                VStack(alignment: .leading, spacing: 1) {
                    Text(instrument.name)
                        .font(.system(size: 13, weight: isActive ? .semibold : .medium))
                        .foregroundStyle(Theme.text)
                    Text(instrument.subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if let shortcut {
                    Text("⌘\(shortcut)")
                        .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                        .foregroundStyle(Theme.mutedSoft)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color.white.opacity(0.55))
                        )
                        .opacity(isActive ? 1 : 0.55)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        isActive
                            ? AnyShapeStyle(LinearGradient(
                                colors: [Color(hex: 0xFFF8EC), Color(hex: 0xFDEFD9)],
                                startPoint: .top, endPoint: .bottom
                            ))
                            : AnyShapeStyle(Color.clear)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isActive ? Theme.accent.opacity(0.22) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
