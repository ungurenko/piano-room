import SwiftUI

struct AllInstrumentsView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var search = ""
    @State private var selectedCategory: GMCategory?

    private var filtered: [Instrument] {
        InstrumentCatalog.all.filter { instrument in
            let matchesCategory = selectedCategory == nil || instrument.category == selectedCategory
            guard matchesCategory else { return false }
            guard !search.isEmpty else { return true }
            return instrument.name.localizedCaseInsensitiveContains(search)
                || instrument.subtitle.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            header
            searchField
            categoryChips

            ScrollView {
                LazyVStack(spacing: 3) {
                    ForEach(filtered) { instrument in
                        row(instrument)
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollContentBackground(.hidden)
        }
        .padding(20)
        .frame(width: 760, height: 700)
        .background(Theme.gradient)
    }

    // MARK: - Шапка

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Все инструменты")
                    .font(.system(size: 20, weight: .semibold))
                    .tracking(-0.4)
                    .foregroundStyle(Theme.text)
                Text("128 программ General MIDI и рояль Salamander")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
            Text("\(filtered.count)")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(Theme.accentDeep)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(Theme.accent.opacity(0.12)))
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 28, height: 28)
                    .background(
                        Circle().fill(Color.white.opacity(0.6))
                    )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Поиск

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(Theme.mutedSoft)
            TextField("Найти инструмент", text: $search)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
            if !search.isEmpty {
                Button {
                    search = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.mutedSoft)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.white.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Theme.line, lineWidth: 1)
        )
    }

    // MARK: - Категории

    private var categoryChips: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 148), spacing: 6, alignment: .leading)],
            alignment: .leading,
            spacing: 6
        ) {
            chip(title: "Все", isActive: selectedCategory == nil) {
                selectedCategory = nil
            }
            ForEach(GMCategory.allCases) { category in
                chip(title: category.rawValue, isActive: selectedCategory == category) {
                    selectedCategory = category
                }
            }
        }
    }

    private func chip(title: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? Theme.accentDeep : Theme.muted)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(isActive ? Theme.accent.opacity(0.14) : Color.white.opacity(0.45))
                )
                .overlay(
                    Capsule()
                        .strokeBorder(isActive ? Theme.accent.opacity(0.25) : Theme.line, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Строка

    private func row(_ instrument: Instrument) -> some View {
        let isActive = state.currentInstrument.id == instrument.id
        return Button {
            state.selectInstrument(instrument)
            dismiss()
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Theme.accent.opacity(isActive ? 0.16 : 0.07))
                    Image(systemName: instrument.symbolName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.accent)
                }
                .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 1) {
                    Text(instrument.name)
                        .font(.system(size: 12.5, weight: isActive ? .semibold : .regular))
                        .foregroundStyle(Theme.text)
                    Text(instrument.subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.mutedSoft)
                }

                Spacer()

                Text(instrument.category.rawValue)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.mutedSoft)
                    .lineLimit(1)

                if isActive {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.accent)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isActive ? Theme.accentPale.opacity(0.7) : Color.white.opacity(0.001))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
