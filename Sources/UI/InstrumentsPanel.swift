import SwiftUI

struct InstrumentsPanel: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(InstrumentCatalog.favorites) { instrument in
                        InstrumentRow(
                            instrument: instrument,
                            isActive: state.currentInstrument.id == instrument.id,
                            shortcut: InstrumentCatalog.shortcut(for: instrument)
                        ) {
                            state.selectInstrument(instrument)
                        }
                    }
                }
                .padding(.top, 5)
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: .infinity, alignment: .top)

            allInstrumentsButton
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Шапка

    private var header: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Инструменты")
                    .font(Theme.ui(12.5, weight: .medium))
                    .foregroundStyle(Theme.textSoft)
                Spacer()
                Text("\(InstrumentCatalog.favorites.count) из \(InstrumentCatalog.all.count)")
                    .font(Theme.ui(10))
                    .foregroundStyle(Theme.mutedSoft)
            }
            .padding(.leading, 14)
            .padding(.bottom, 10)

            Hairline()
        }
    }

    // MARK: - Все инструменты

    private var allInstrumentsButton: some View {
        VStack(spacing: 0) {
            Hairline()

            Button {
                state.showAllInstruments = true
            } label: {
                HStack(spacing: 8) {
                    Text("Все инструменты")
                        .font(Theme.ui(12.5, weight: .medium))
                        .foregroundStyle(Theme.textSoft)
                    Spacer()
                    Text("\(InstrumentCatalog.all.count)")
                        .font(Theme.ui(10))
                        .foregroundStyle(Theme.mutedSoft)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.mutedSoft)
                }
                .padding(.leading, 14)
                .padding(.trailing, 8)
                .frame(height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("0", modifiers: .command)
            .accessibilityLabel("Все \(InstrumentCatalog.all.count) инструмента")
        }
    }
}

// MARK: - Строка инструмента

private struct InstrumentRow: View {
    let instrument: Instrument
    let isActive: Bool
    var shortcut: String?
    let action: () -> Void

    @State private var isHovering = false

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
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(instrument.name)
                        .font(Theme.ui(13, weight: isActive ? .semibold : .medium))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    Text(instrument.subtitle)
                        .font(Theme.ui(9.5))
                        .foregroundStyle(Theme.mutedSoft)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if let shortcut {
                    Text("⌘\(shortcut)")
                        .font(Theme.ui(9.5, weight: .medium).monospacedDigit())
                        .foregroundStyle(Theme.mutedSoft)
                        .opacity(isActive ? 1 : 0.55)
                }
            }
            .padding(.leading, 14)
            .padding(.trailing, 8)
            .frame(minHeight: 53)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isHovering ? Theme.hover : Color.clear)
            )
            .overlay(alignment: .leading) {
                if isActive {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Theme.accent)
                        .frame(width: 3, height: 21)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel("\(instrument.name), \(instrument.subtitle)")
        .accessibilityValue(isActive ? "Выбран" : "")
    }
}
