// Тесты разбора MIDI-потока. Компилируется вместе с MIDIEvent.swift и MIDIParser.swift.
import Foundation

var failures = 0
var checks = 0

func check(_ name: String, _ actual: [MIDIEvent], _ expected: [MIDIEvent]) {
    checks += 1
    if actual != expected {
        failures += 1
        print("✗ \(name)")
        print("   ожидалось: \(expected)")
        print("   получено:  \(actual)")
    }
}

// 1. Простые ноты
var parser = MIDIParser()
check("noteOn", parser.parse([0x90, 60, 100]),
      [.noteOn(note: 60, velocity: 100, channel: 0)])

parser = MIDIParser()
check("noteOff", parser.parse([0x80, 60, 0]),
      [.noteOff(note: 60, channel: 0)])

parser = MIDIParser()
check("noteOn с нулевой скоростью — это noteOff", parser.parse([0x90, 60, 0]),
      [.noteOff(note: 60, channel: 0)])

// 2. Running status: второй байт данных без повторного статуса
parser = MIDIParser()
check("running status", parser.parse([0x90, 60, 100, 64, 90]),
      [.noteOn(note: 60, velocity: 100, channel: 0),
       .noteOn(note: 64, velocity: 90, channel: 0)])

// 3. Однобайтовые сообщения
parser = MIDIParser()
check("program change", parser.parse([0xC0, 16]),
      [.programChange(program: 16, channel: 0)])

parser = MIDIParser()
check("channel pressure", parser.parse([0xD0, 100]),
      [.channelPressure(value: 100, channel: 0)])

// 4. Контроллеры и изгиб
parser = MIDIParser()
check("контроллер", parser.parse([0xB0, 64, 127]),
      [.controlChange(controller: 64, value: 127, channel: 0)])

parser = MIDIParser()
check("pitch bend по центру", parser.parse([0xE0, 0, 64]),
      [.pitchBend(value: 8192, channel: 0)])

parser = MIDIParser()
check("poly pressure", parser.parse([0xA0, 60, 80]),
      [.polyPressure(note: 60, value: 80, channel: 0)])

// 5. Каналы
parser = MIDIParser()
check("второй канал", parser.parse([0x91, 60, 100]),
      [.noteOn(note: 60, velocity: 100, channel: 1)])

// 6. Байты реального времени игнорируются
parser = MIDIParser()
check("realtime между сообщениями", parser.parse([0xFE, 0x90, 60, 100, 0xF8]),
      [.noteOn(note: 60, velocity: 100, channel: 0)])

// 7. SysEx пропускается, running status сбрасывается
parser = MIDIParser()
check("SysEx пропущен", parser.parse([0xF0, 1, 2, 3, 0xF7, 0x90, 60, 100]),
      [.noteOn(note: 60, velocity: 100, channel: 0)])

// 8. Сообщение разрезано между пакетами
parser = MIDIParser()
let firstPart = parser.parse([0x90, 60])
check("первая половина сообщения", firstPart, [])
check("вторая половина сообщения", parser.parse([100]),
      [.noteOn(note: 60, velocity: 100, channel: 0)])

// 9. Running status, разрезанный между пакетами
parser = MIDIParser()
check("running status, часть 1", parser.parse([0x90, 60, 100, 64]), 
      [.noteOn(note: 60, velocity: 100, channel: 0)])
check("running status, часть 2", parser.parse([90]),
      [.noteOn(note: 64, velocity: 90, channel: 0)])

// 10. Данные без статуса игнорируются
parser = MIDIParser()
check("данные без статуса", parser.parse([0x00, 0x01, 0x02]), [])

// 11. Частичный status в начале потока
parser = MIDIParser()
check("половинный noteOn без статуса", parser.parse([60, 100]), [])

if failures == 0 {
    print("Все тесты парсера пройдены: \(checks) проверок")
} else {
    print("Провалено \(failures) из \(checks)")
    exit(1)
}
