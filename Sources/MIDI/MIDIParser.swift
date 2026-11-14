import Foundation

/// Разбор потока MIDI 1.0: running status, служебные сообщения и склейка
/// сообщений, разрезанных между пакетами CoreMIDI.
///
/// Состояние живёт между вызовами: парсер сам дополняет недописанное сообщение.
struct MIDIParser {

    private var runningStatus: UInt8 = 0
    private var leftover: [UInt8] = []

    mutating func reset() {
        runningStatus = 0
        leftover = []
    }

    /// Разобрать очередную порцию байтов.
    mutating func parse(_ bytes: [UInt8]) -> [MIDIEvent] {
        var events: [MIDIEvent] = []
        var data = leftover
        data.append(contentsOf: bytes)
        leftover = []

        var index = 0
        while index < data.count {
            let byte = data[index]

            // Служебные сообщения реального времени можно игнорировать.
            if byte >= 0xF8 {
                index += 1
                continue
            }

            if byte & 0x80 != 0 {
                if byte >= 0xF0 {
                    runningStatus = 0
                    if byte == 0xF0 {
                        // SysEx: пропускаем до конца сообщения.
                        index += 1
                        while index < data.count && data[index] != 0xF7 { index += 1 }
                        if index < data.count { index += 1 }
                    } else {
                        index += 1
                    }
                    continue
                }
                runningStatus = byte
                index += 1
                continue
            }

            guard runningStatus != 0 else {
                index += 1
                continue
            }

            let type = runningStatus & 0xF0
            let channel = runningStatus & 0x0F
            let dataCount = (type == 0xC0 || type == 0xD0) ? 1 : 2

            guard index + dataCount <= data.count else {
                leftover = Array(data[index...])
                return events
            }

            let first = data[index]
            let second = dataCount == 2 ? data[index + 1] : 0
            append(type: type, channel: channel, first: first, second: second, into: &events)
            index += dataCount
        }

        return events
    }

    private func append(type: UInt8, channel: UInt8, first: UInt8, second: UInt8, into events: inout [MIDIEvent]) {
        switch type {
        case 0x80:
            events.append(.noteOff(note: first, channel: channel))
        case 0x90:
            if second == 0 {
                events.append(.noteOff(note: first, channel: channel))
            } else {
                events.append(.noteOn(note: first, velocity: second, channel: channel))
            }
        case 0xA0:
            events.append(.polyPressure(note: first, value: second, channel: channel))
        case 0xB0:
            events.append(.controlChange(controller: first, value: second, channel: channel))
        case 0xC0:
            events.append(.programChange(program: first, channel: channel))
        case 0xD0:
            events.append(.channelPressure(value: first, channel: channel))
        case 0xE0:
            let value = UInt16(first) | (UInt16(second) << 7)
            events.append(.pitchBend(value: value, channel: channel))
        default:
            break
        }
    }
}
