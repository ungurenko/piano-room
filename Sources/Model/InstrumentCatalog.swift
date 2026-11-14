import Foundation

/// Каталог всех инструментов приложения.
///
/// Первый и главный инструмент — качественный рояль из SF2-банка Salamander.
/// Остальные 128 — стандартные программы General MIDI, которые играет системный
/// синтезатор AUMIDISynth. Переключение между ними мгновенное, без загрузки банков.
enum InstrumentCatalog {

    // MARK: - Рояль

    static let grandPiano = Instrument(
        id: "grand-salamander",
        name: "Рояль",
        subtitle: "Salamander Grand Piano",
        source: .grandPiano,
        category: .piano,
        isFavorite: true
    )

    // MARK: - Избранные

    /// Шесть инструментов на главном экране.
    static let favoriteIDs: [String] = [
        "grand-salamander",
        "gm-0",
        "gm-4",
        "gm-16",
        "gm-48",
        "gm-89"
    ]

    static var favorites: [Instrument] {
        favoriteIDs.compactMap { id in all.first { $0.id == id } }
    }

    // MARK: - General MIDI

    /// 128 программ General MIDI: (русское название, оригинальное название).
    private static let gmNames: [(String, String)] = [
        ("Тёплый рояль", "Acoustic Grand Piano"),
        ("Яркий рояль", "Bright Acoustic Piano"),
        ("Электророяль", "Electric Grand Piano"),
        ("Хонки-тонк", "Honky-tonk Piano"),
        ("Электропиано 1", "Electric Piano 1"),
        ("Электропиано 2", "Electric Piano 2"),
        ("Клавесин", "Harpsichord"),
        ("Клавинет", "Clavi"),
        ("Челеста", "Celesta"),
        ("Глокеншпиль", "Glockenspiel"),
        ("Музыкальная шкатулка", "Music Box"),
        ("Вибрафон", "Vibraphone"),
        ("Маримба", "Marimba"),
        ("Ксилофон", "Xylophone"),
        ("Колокольчики", "Tubular Bells"),
        ("Цимбалы", "Dulcimer"),
        ("Орган", "Drawbar Organ"),
        ("Перкуссионный орган", "Percussive Organ"),
        ("Рок-орган", "Rock Organ"),
        ("Церковный орган", "Church Organ"),
        ("Фисгармония", "Reed Organ"),
        ("Аккордеон", "Accordion"),
        ("Губная гармоника", "Harmonica"),
        ("Танго-аккордеон", "Tango Accordion"),
        ("Гитара нейлон", "Acoustic Guitar (nylon)"),
        ("Гитара сталь", "Acoustic Guitar (steel)"),
        ("Электрогитара джаз", "Electric Guitar (jazz)"),
        ("Электрогитара чистая", "Electric Guitar (clean)"),
        ("Электрогитара приглушённая", "Electric Guitar (muted)"),
        ("Перегруженная гитара", "Overdriven Guitar"),
        ("Гитара с дисторшном", "Distortion Guitar"),
        ("Гитара флажолеты", "Guitar Harmonics"),
        ("Акустический бас", "Acoustic Bass"),
        ("Бас пальцами", "Electric Bass (finger)"),
        ("Бас медиатором", "Electric Bass (pick)"),
        ("Безладовый бас", "Fretless Bass"),
        ("Слэп-бас 1", "Slap Bass 1"),
        ("Слэп-бас 2", "Slap Bass 2"),
        ("Синт-бас 1", "Synth Bass 1"),
        ("Синт-бас 2", "Synth Bass 2"),
        ("Скрипка", "Violin"),
        ("Альт", "Viola"),
        ("Виолончель", "Cello"),
        ("Контрабас", "Contrabass"),
        ("Тремоло струнные", "Tremolo Strings"),
        ("Пиццикато", "Pizzicato Strings"),
        ("Арфа", "Orchestral Harp"),
        ("Литавры", "Timpani"),
        ("Струнный ансамбль", "String Ensemble 1"),
        ("Струнные 2", "String Ensemble 2"),
        ("Синт-струнные 1", "Synth Strings 1"),
        ("Синт-струнные 2", "Synth Strings 2"),
        ("Хор «а»", "Choir Aahs"),
        ("Хор «у»", "Voice Oohs"),
        ("Синт-голос", "Synth Voice"),
        ("Оркестровый удар", "Orchestra Hit"),
        ("Труба", "Trumpet"),
        ("Тромбон", "Trombone"),
        ("Туба", "Tuba"),
        ("Труба с сурдиной", "Muted Trumpet"),
        ("Валторна", "French Horn"),
        ("Духовые", "Brass Section"),
        ("Синт-брасс 1", "Synth Brass 1"),
        ("Синт-брасс 2", "Synth Brass 2"),
        ("Сопрано-сакс", "Soprano Sax"),
        ("Альт-сакс", "Alto Sax"),
        ("Тенор-сакс", "Tenor Sax"),
        ("Баритон-сакс", "Baritone Sax"),
        ("Гобой", "Oboe"),
        ("Английский рожок", "English Horn"),
        ("Фагот", "Bassoon"),
        ("Кларнет", "Clarinet"),
        ("Пикколо", "Piccolo"),
        ("Флейта", "Flute"),
        ("Блокфлейта", "Recorder"),
        ("Пан-флейта", "Pan Flute"),
        ("Бутылочный звук", "Blown Bottle"),
        ("Сякухати", "Shakuhachi"),
        ("Свист", "Whistle"),
        ("Окарина", "Ocarina"),
        ("Лид квадрат", "Lead 1 (square)"),
        ("Лид пила", "Lead 2 (sawtooth)"),
        ("Лид каллиопа", "Lead 3 (calliope)"),
        ("Лид чифф", "Lead 4 (chiff)"),
        ("Лид чаранг", "Lead 5 (charang)"),
        ("Лид голос", "Lead 6 (voice)"),
        ("Лид квинты", "Lead 7 (fifths)"),
        ("Лид бас+лид", "Lead 8 (bass+lead)"),
        ("Пэд нью-эйдж", "Pad 1 (new age)"),
        ("Тёплый пэд", "Pad 2 (warm)"),
        ("Полисинт-пэд", "Pad 3 (polysynth)"),
        ("Хоровой пэд", "Pad 4 (choir)"),
        ("Смычковый пэд", "Pad 5 (bowed)"),
        ("Металлический пэд", "Pad 6 (metallic)"),
        ("Пэд гало", "Pad 7 (halo)"),
        ("Свип-пэд", "Pad 8 (sweep)"),
        ("Эффект дождь", "FX 1 (rain)"),
        ("Саундтрек", "FX 2 (soundtrack)"),
        ("Кристалл", "FX 3 (crystal)"),
        ("Атмосфера", "FX 4 (atmosphere)"),
        ("Яркость", "FX 5 (brightness)"),
        ("Гоблины", "FX 6 (goblins)"),
        ("Эхо", "FX 7 (echoes)"),
        ("Sci-fi", "FX 8 (sci-fi)"),
        ("Ситар", "Sitar"),
        ("Банджо", "Banjo"),
        ("Сямисэн", "Shamisen"),
        ("Кото", "Koto"),
        ("Калимба", "Kalimba"),
        ("Волынка", "Bagpipe"),
        ("Народная скрипка", "Fiddle"),
        ("Шанай", "Shanai"),
        ("Бубенцы", "Tinkle Bell"),
        ("Агого", "Agogo"),
        ("Стальные барабаны", "Steel Drums"),
        ("Вудблок", "Woodblock"),
        ("Тайко", "Taiko Drum"),
        ("Томы", "Melodic Tom"),
        ("Синт-барабаны", "Synth Drum"),
        ("Обратные тарелки", "Reverse Cymbal"),
        ("Шум ладов", "Guitar Fret Noise"),
        ("Дыхание", "Breath Noise"),
        ("Морской прибой", "Seashore"),
        ("Пение птиц", "Bird Tweet"),
        ("Телефон", "Telephone Ring"),
        ("Вертолёт", "Helicopter"),
        ("Аплодисменты", "Applause"),
        ("Выстрел", "Gunshot")
    ]

    static let gm: [Instrument] = gmNames.enumerated().map { index, pair in
        Instrument(
            id: "gm-\(index)",
            name: pair.0,
            subtitle: pair.1,
            source: .gm,
            gmProgram: index,
            category: category(for: index),
            isFavorite: favoriteIDs.contains("gm-\(index)")
        )
    }

    static let all: [Instrument] = [grandPiano] + gm

    static func instrument(id: String) -> Instrument? {
        all.first { $0.id == id }
    }

    static func category(for program: Int) -> GMCategory {
        switch program {
        case 0...7: return .piano
        case 8...15: return .chromatic
        case 16...23: return .organ
        case 24...31: return .guitar
        case 32...39: return .bass
        case 40...47: return .strings
        case 48...55: return .ensemble
        case 56...63: return .brass
        case 64...71: return .reed
        case 72...79: return .pipe
        case 80...87: return .synthLead
        case 88...95: return .synthPad
        case 96...103: return .synthFX
        case 104...111: return .ethnic
        case 112...119: return .percussive
        default: return .soundFX
        }
    }
}
