#!/bin/bash
# Проверяет MIDI, каталог и хорус, включая настоящие callbacks виртуального входа.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "1/6 Разбор MIDI-потока"
mkdir -p /tmp/pianoroom_midi_test
cp Tools/midi_parser_test.swift /tmp/pianoroom_midi_test/main.swift
swiftc -swift-version 6 Sources/MIDI/MIDIEvent.swift Sources/MIDI/MIDIParser.swift Sources/MIDI/MIDIService.swift \
  /tmp/pianoroom_midi_test/main.swift -o /tmp/pianoroom_midi_test/run
/tmp/pianoroom_midi_test/run

echo "2/6 Каталог инструментов"
mkdir -p /tmp/pianoroom_catalog_test
cp Tools/catalog_test.swift /tmp/pianoroom_catalog_test/main.swift
swiftc -swift-version 6 Sources/Model/Instrument.swift Sources/Model/InstrumentCatalog.swift \
  /tmp/pianoroom_catalog_test/main.swift -o /tmp/pianoroom_catalog_test/run
/tmp/pianoroom_catalog_test/run

echo "3/6 Хорус без аудиоустройства"
mkdir -p /tmp/pianoroom_chorus_test
cp Tools/chorus_test.swift /tmp/pianoroom_chorus_test/main.swift
swiftc -swift-version 6 Sources/Audio/ChorusUnit.swift /tmp/pianoroom_chorus_test/main.swift -o /tmp/pianoroom_chorus_test/run
/tmp/pianoroom_chorus_test/run

echo "4/6 Настоящий приём CoreMIDI в Release"
mkdir -p /tmp/pianoroom_receive_test
swiftc -O -swift-version 6 -strict-concurrency=complete \
  Sources/MIDI/MIDIEvent.swift Sources/MIDI/MIDIParser.swift Sources/MIDI/MIDIService.swift \
  Tools/midi_receive_test.swift -o /tmp/pianoroom_receive_test/run
/tmp/pianoroom_receive_test/run

echo "5/6 Встроенный реверб без аудиоустройства"
bash Tools/run-reverb-tests.sh

echo "6/6 Проигрыватель записанных инструментов"
mkdir -p build
clang++ -std=c++17 -O2 Tools/piano_dsp_test.cpp Sources/Audio/PianoDSP.cpp \
  ThirdParty/SFZPlayer/WAVReader.cpp ThirdParty/SFZPlayer/SampleBuffer.cpp -o build/piano_dsp_test
build/piano_dsp_test Resources/Instruments/Osiris/Instrument.sfz Resources/Instruments/Headroom/Instrument.sfz

echo "Все тесты пройдены."
