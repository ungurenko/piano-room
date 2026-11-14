#!/bin/bash
# Прогоняет тесты MIDI-парсера и каталога инструментов.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "1/2 Разбор MIDI-потока"
mkdir -p /tmp/pianoroom_midi_test
cp Tools/midi_parser_test.swift /tmp/pianoroom_midi_test/main.swift
swiftc Sources/MIDI/MIDIEvent.swift Sources/MIDI/MIDIParser.swift \
  /tmp/pianoroom_midi_test/main.swift -o /tmp/pianoroom_midi_test/run
/tmp/pianoroom_midi_test/run

echo "2/2 Каталог инструментов"
mkdir -p /tmp/pianoroom_catalog_test
cp Tools/catalog_test.swift /tmp/pianoroom_catalog_test/main.swift
swiftc Sources/Model/Instrument.swift Sources/Model/InstrumentCatalog.swift \
  /tmp/pianoroom_catalog_test/main.swift -o /tmp/pianoroom_catalog_test/run
/tmp/pianoroom_catalog_test/run

echo "Все тесты пройдены."
