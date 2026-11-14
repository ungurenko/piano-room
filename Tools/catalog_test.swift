// Проверка целостности каталога инструментов.
// Собирается вместе с Sources/Model/Instrument.swift и InstrumentCatalog.swift.
import Foundation

var failures: [String] = []

let all = InstrumentCatalog.all
if all.count != 129 {
    failures.append("Ожидалось 129 инструментов, получено \(all.count)")
}

let gm = InstrumentCatalog.gm
if gm.count != 128 {
    failures.append("Ожидалось 128 GM-инструментов, получено \(gm.count)")
}

let programs = gm.compactMap(\.gmProgram)
if Set(programs) != Set(0...127) {
    failures.append("Набор GM-программ не совпадает с 0…127")
}

let ids = all.map(\.id)
if Set(ids).count != ids.count {
    failures.append("Есть повторяющиеся id инструментов")
}

let favorites = InstrumentCatalog.favorites
if favorites.count != 6 {
    failures.append("Ожидалось 6 избранных, получено \(favorites.count)")
}
for favorite in favorites where !all.contains(where: { $0.id == favorite.id }) {
    failures.append("Избранный инструмент отсутствует в каталоге: \(favorite.id)")
}

if all.contains(where: { $0.name.isEmpty || $0.subtitle.isEmpty }) {
    failures.append("Есть инструменты без названия или подписи")
}

if InstrumentCatalog.grandPiano.source != .grandPiano {
    failures.append("Главный рояль должен играть через сэмплер")
}

for instrument in gm where instrument.source != .gm {
    failures.append("GM-инструмент с неверным источником: \(instrument.id)")
}

if failures.isEmpty {
    print("Каталог в порядке: \(all.count) инструментов, \(gm.count) GM, 6 избранных")
    print("Избранные: " + favorites.map(\.name).joined(separator: ", "))
} else {
    print("ОШИБКИ КАТАЛОГА:")
    for failure in failures { print(" - \(failure)") }
    exit(1)
}
