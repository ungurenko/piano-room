# Кредиты и сторонние ресурсы

## Рояль Salamander Grand Piano

- Запись: Yamaha C5, 48 кГц / 24 бита, 16 уровней скорости.
- Автор: Alexander Holm.
- Лицензия: [Creative Commons Attribution 3.0](https://creativecommons.org/licenses/by/3.0/).
- Источник: [FreePats](https://freepats.zenvoid.org/Piano/acoustic-grand-piano.html).

Банк в репозиторий не входит из-за размера (~1,2 ГБ распакованного).
Скачивается скриптом `Tools/download-soundbank.sh`.

## General MIDI

128 инструментов GM играет системный синтезатор Apple **DLSMusicDevice** (macOS),
отдельных файлов не требуется.

## Иконка

Нарисована для проекта в тёплой палитре приложения.

## Код

MIT, см. [LICENSE](LICENSE).

## Реверберация Signalsmith

Алгоритм основан на [Signalsmith Basics](https://github.com/Signalsmith-Audio/basics), автор Geraint Luff / Signalsmith Audio; MIT. Вспомогательные алгоритмы — [Signalsmith DSP](https://github.com/Signalsmith-Audio/dsp) v1.7.1, MIT.

Версии и изменения описаны в `ThirdParty/SignalsmithReverb/README.md`. Полные лицензии входят в приложение в `ThirdPartyNotices.txt`.

## Дополнительные акустические инструменты

- [Osiris Piano](https://github.com/sfzinstruments/Osiris_Piano), CC0.
- [Headroom Piano](https://github.com/sfzinstruments/BengtNilsson.HeadroomPiano), Bengt Nilsson, CC BY 4.0.
- [Fuchs & Möhr Felt Piano](https://www.polyphone.io/en/forum/your-creations/850-acoustic-felt-piano-upright-fuchs-mohr), Tom Guder, public domain.

Оригинальные записи сохраняются без потери качества. Подготовка SFZ описана рядом с библиотеками в `TRANSFORMATIONS.txt`; скрипт `Tools/download-pianos.sh` фиксирует источники и контрольные суммы. Проигрыватель использует MIT-компоненты SFZPlayer и dr_flac, лицензии находятся в `ThirdParty` и внутри приложения.
