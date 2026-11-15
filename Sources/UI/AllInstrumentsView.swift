import Foundation
import SwiftUI

/// Каталог всех инструментов в теме «Белый лист»:
/// белый холст, чернильная типографика, волосяные линии и один акцент — красный фетр.
struct AllInstrumentsView: View {
    @Environment(AppState.self) private var state
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
        VStack(alignment: .leading, spacing: 14) {
            header
            searchField
            categoryChips

            if filtered.isEmpty {
                emptyState
            } else {
                instrumentList
            }
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 22)
        .frame(width: 760, height: 700)
        .background(Theme.background)
        .onExitCommand { dismiss() }
    }

    // MARK: - Шапка

    private var header: some View {
        HStack(alignment: .center, spacing: Theme.Space.group) {
            VStack(alignment: .leading, spacing: Theme.Space.tight) {
                Text("Все инструменты")
                    .font(Theme.display(22))
                    .tracking(-0.4)
                    .foregroundStyle(Theme.text)
                Text("4 фортепиано и 128 тембров General MIDI")
                    .font(Theme.ui(11.5))
                    .foregroundStyle(Theme.muted)
            }

            Spacer(minLength: Theme.Space.group)

            HStack(spacing: Theme.Space.related) {
                Text("\(filtered.count) из \(InstrumentCatalog.all.count)")
                    .font(Theme.ui(10.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(Theme.mutedSoft)
                    .fixedSize()

                IconButton(systemName: "xmark", title: "Закрыть список инструментов") {
                    dismiss()
                }
            }
        }
    }

    // MARK: - Поиск

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(Theme.mutedSoft)

            TextField("Найти инструмент", text: $search)
                .textFieldStyle(.plain)
                .font(Theme.ui(12.5))
                .foregroundStyle(Theme.text)
                .accessibilityLabel("Найти инструмент")

            if !search.isEmpty {
                Button {
                    search = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.mutedSoft)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Очистить поиск")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.lineSoft)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.line, lineWidth: 1)
        )
    }

    // MARK: - Категории

    private var categoryChips: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 3),
            alignment: .leading,
            spacing: 7
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
                .font(Theme.ui(11.5, weight: isActive ? .medium : .regular))
                .foregroundStyle(isActive ? Color.white : Theme.muted)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isActive ? Theme.text : Theme.lineSoft)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    // MARK: - Список

    private var instrumentList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filtered) { instrument in
                    CatalogRow(
                        instrument: instrument,
                        catalogIndex: InstrumentCatalog.all.firstIndex { $0.id == instrument.id } ?? 0,
                        isActive: state.currentInstrument.id == instrument.id
                    ) {
                        state.selectInstrument(instrument)
                        dismiss()
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollContentBackground(.hidden)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Пустое состояние

    private var emptyState: some View {
        VStack(spacing: Theme.Space.tight) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20))
                .foregroundStyle(Theme.mutedSoft)
                .padding(.bottom, Theme.Space.tight)

            Text("Ничего не нашлось")
                .font(Theme.ui(13, weight: .medium))
                .foregroundStyle(Theme.text)

            Text("Попробуй другое слово или сбрось фильтр")
                .font(Theme.ui(11.5))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)

            OutlinePillButton(title: "Сбросить фильтр") {
                search = ""
                selectedCategory = nil
            }
            .accessibilityLabel("Сбросить фильтр")
            .padding(.top, Theme.Space.control)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Строка каталога

private struct CatalogRow: View {
    let instrument: Instrument
    /// Индекс в полном каталоге, а не в отфильтрованном списке.
    let catalogIndex: Int
    let isActive: Bool
    let action: () -> Void

    @State private var isHovering = false

    private var rowBackground: Color {
        if isActive { return Theme.accentWash }
        return isHovering ? Theme.hover : Color.clear
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Text(String(format: "%03d", catalogIndex + 1))
                        .font(Theme.ui(9.5, weight: .medium).monospacedDigit())
                        .foregroundStyle(Theme.mutedSoft)
                        .frame(width: 32, alignment: .leading)

                    Text(instrument.name)
                        .font(Theme.ui(12.5, weight: isActive ? .semibold : .regular))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)

                    Spacer(minLength: Theme.Space.control)

                    Text(instrument.category.rawValue)
                        .font(Theme.ui(10))
                        .foregroundStyle(Theme.mutedSoft)
                        .lineLimit(1)

                    // Место под галочку зарезервировано всегда, чтобы колонка
                    // категорий не прыгала у выбранной строки.
                    ZStack {
                        if isActive {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Theme.accent)
                        }
                    }
                    .frame(width: 12)
                }
                .padding(.horizontal, 10)
                .frame(height: 46)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(rowBackground)
                )

                Hairline(color: Theme.lineSoft)
                    .padding(.leading, 42)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel(instrument.name)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}
