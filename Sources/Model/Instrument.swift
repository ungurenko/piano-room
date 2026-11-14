import Foundation

/// Откуда берётся звук инструмента.
enum InstrumentSource: String, Codable {
    /// Качественный рояль из SF2-банка через AUSampler.
    case grandPiano
    /// General MIDI-программа через AUMIDISynth (мгновенное переключение, без загрузки банков).
    case gm
}

struct Instrument: Identifiable, Hashable {
    let id: String
    let name: String
    let subtitle: String
    let source: InstrumentSource
    /// Номер программы General MIDI (0…127), нужен только для .gm.
    let gmProgram: Int?
    let category: GMCategory
    var isFavorite: Bool

    init(
        id: String,
        name: String,
        subtitle: String,
        source: InstrumentSource,
        gmProgram: Int? = nil,
        category: GMCategory,
        isFavorite: Bool = false
    ) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.source = source
        self.gmProgram = gmProgram
        self.category = category
        self.isFavorite = isFavorite
    }
}

enum GMCategory: String, CaseIterable, Identifiable {
    case piano = "Пианино"
    case chromatic = "Хроматическая перкуссия"
    case organ = "Орган"
    case guitar = "Гитара"
    case bass = "Бас"
    case strings = "Струнные"
    case ensemble = "Ансамбли"
    case brass = "Духовые"
    case reed = "Язычковые"
    case pipe = "Флейты"
    case synthLead = "Синт-лид"
    case synthPad = "Синт-пэд"
    case synthFX = "Синт-эффекты"
    case ethnic = "Этника"
    case percussive = "Перкуссия"
    case soundFX = "Звуковые эффекты"

    var id: String { rawValue }
}
