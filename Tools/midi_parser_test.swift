// Тесты разбора MIDI-потока. Компилируется вместе с MIDIEvent.swift и MIDIParser.swift.
import CoreMIDI
import Foundation

var failures = 0
var checks = 0

@MainActor
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

// 12. Realtime разрешён внутри сообщения и между его частями.
parser = MIDIParser()
check("realtime внутри noteOn", parser.parse([0x90, 60, 0xF8, 100]),
      [.noteOn(note: 60, velocity: 100, channel: 0)])
parser = MIDIParser()
check("realtime после статуса", parser.parse([0x90, 0xFE, 60, 100]),
      [.noteOn(note: 60, velocity: 100, channel: 0)])
parser = MIDIParser()
check("realtime в разрезанном сообщении, часть 1", parser.parse([0x90, 60]), [])
check("realtime в разрезанном сообщении, часть 2", parser.parse([0xF8, 100]),
      [.noteOn(note: 60, velocity: 100, channel: 0)])

// 13. Новый статус отменяет незаконченное сообщение.
parser = MIDIParser()
check("noteOff прерывает noteOn", parser.parse([0x90, 60, 0x80, 60, 0]),
      [.noteOff(note: 60, channel: 0)])
parser = MIDIParser()
check("новый канал прерывает noteOn", parser.parse([0x90, 60, 0x91, 64, 100]),
      [.noteOn(note: 64, velocity: 100, channel: 1)])
parser = MIDIParser()
check("system common сбрасывает running status", parser.parse([0x90, 60, 100, 0xF2, 1, 2, 64, 100]),
      [.noteOn(note: 60, velocity: 100, channel: 0)])

// 14. SysEx продолжается между пакетами и завершается следующим статусом.
parser = MIDIParser()
check("SysEx, часть 1", parser.parse([0xF0, 1, 2]), [])
check("SysEx, часть 2", parser.parse([3, 0xF8, 4]), [])
check("SysEx, конец", parser.parse([0xF7, 0x90, 60, 100]),
      [.noteOn(note: 60, velocity: 100, channel: 0)])
parser = MIDIParser()
check("статус прерывает SysEx", parser.parse([0xF0, 1, 0x90, 60, 100]),
      [.noteOn(note: 60, velocity: 100, channel: 0)])

// 15. Сброс между входами не переносит незаконченную ноту и running status.
parser = MIDIParser()
check("незаконченная нота перед reset", parser.parse([0x90, 60]), [])
parser.reset()
check("данные после reset без статуса", parser.parse([100]), [])
check("новый источник после reset", parser.parse([0x90, 64, 100]),
      [.noteOn(note: 64, velocity: 100, channel: 0)])

// 16. CoreMIDI-пакет может содержать больше 256 байт.
let packetStorage = UnsafeMutableRawPointer.allocate(byteCount: 2048, alignment: 8)
defer { packetStorage.deallocate() }
let packetList = packetStorage.bindMemory(to: MIDIPacketList.self, capacity: 1)
var lastPacket = MIDIPacketListInit(packetList)
let longBytes = (0..<100).flatMap { [UInt8(0x90), UInt8($0), UInt8(100)] }
lastPacket = longBytes.withUnsafeBufferPointer { bytes in
    MIDIPacketListAdd(packetList, 2048, lastPacket, 1, bytes.count, bytes.baseAddress!)
}
let releaseBytes: [UInt8] = [0x80, 99, 0]
lastPacket = releaseBytes.withUnsafeBufferPointer { bytes in
    MIDIPacketListAdd(packetList, 2048, lastPacket, 2, bytes.count, bytes.baseAddress!)
}
parser = MIDIParser()
check("полный пакет и следующий noteOff", MIDIService.events(in: UnsafePointer(packetList), parser: &parser),
      (0..<100).map { .noteOn(note: UInt8($0), velocity: 100, channel: 0) } + [.noteOff(note: 99, channel: 0)])

// 17. После отключения и смены поколения старые пакеты игнорируются.
final class EventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [MIDIEvent] = []

    func append(_ event: MIDIEvent) { lock.withLock { events.append(event) } }
    func snapshot() -> [MIDIEvent] { lock.withLock { events } }
}
let recorder = EventRecorder()
let receiver = MIDIReceiver()
receiver.onEvent = { recorder.append($0) }
let oldGeneration = receiver.beginConnection()
receiver.invalidate()
receiver.receive(UnsafePointer(packetList), generation: oldGeneration)
check("отключённый вход не посылает события", recorder.snapshot(), [])
let generation = receiver.beginConnection()
receiver.receive(UnsafePointer(packetList), generation: oldGeneration)
check("старое поколение не посылает события", recorder.snapshot(), [])
receiver.receive(UnsafePointer(packetList), generation: generation)
check("текущее поколение принимает полный пакет", recorder.snapshot(),
      (0..<100).map { .noteOn(note: UInt8($0), velocity: 100, channel: 0) } + [.noteOff(note: 99, channel: 0)])

// 18. Смена поколения сбрасывает недописанное сообщение в самом получателе.
let resetRecorder = EventRecorder()
let resetReceiver = MIDIReceiver()
resetReceiver.onEvent = { resetRecorder.append($0) }
let partialGeneration = resetReceiver.beginConnection()
lastPacket = MIDIPacketListInit(packetList)
let partialBytes: [UInt8] = [0x90, 60]
lastPacket = partialBytes.withUnsafeBufferPointer { bytes in
    MIDIPacketListAdd(packetList, 2048, lastPacket, 0, bytes.count, bytes.baseAddress!)
}
resetReceiver.receive(UnsafePointer(packetList), generation: partialGeneration)
check("недописанная нота получателя", resetRecorder.snapshot(), [])
resetReceiver.invalidate()
let nextGeneration = resetReceiver.beginConnection()
lastPacket = MIDIPacketListInit(packetList)
let nextBytes: [UInt8] = [0x90, 64, 100]
lastPacket = nextBytes.withUnsafeBufferPointer { bytes in
    MIDIPacketListAdd(packetList, 2048, lastPacket, 0, bytes.count, bytes.baseAddress!)
}
resetReceiver.receive(UnsafePointer(packetList), generation: nextGeneration)
check("новый вход без остатка старой ноты", resetRecorder.snapshot(),
      [.noteOn(note: 64, velocity: 100, channel: 0)])

if failures == 0 {
    print("Все тесты парсера пройдены: \(checks) проверок")
} else {
    print("Провалено \(failures) из \(checks)")
    exit(1)
}
