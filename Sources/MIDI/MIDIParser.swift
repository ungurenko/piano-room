import Foundation

/// Разбор потока MIDI 1.0: running status, служебные сообщения и склейка
/// сообщений, разрезанных между пакетами CoreMIDI.
///
/// Состояние живёт между вызовами: парсер сам дополняет недописанное сообщение.
struct MIDIParser {

    private var runningStatus: UInt8 = 0
    private var firstDataByte: UInt8?
    private var isInSysEx = false

    mutating func reset() {
        runningStatus = 0
        firstDataByte = nil
        isInSysEx = false
    }

    /// Разобрать очередную порцию байтов.
    mutating func parse(_ bytes: [UInt8]) -> [MIDIEvent] {
        var events: [MIDIEvent] = []
        for byte in bytes {
            // Realtime может стоять даже между двумя байтами одной ноты.
            if byte >= 0xF8 { continue }

            if byte & 0x80 != 0 {
                // Любой следующий статус завершает незаконченное сообщение,
                // включая SysEx без явного F7.
                firstDataByte = nil
                isInSysEx = byte == 0xF0
                runningStatus = byte < 0xF0 ? byte : 0
                continue
            }

            guard !isInSysEx, runningStatus != 0 else { continue }

            let type = runningStatus & 0xF0
            let channel = runningStatus & 0x0F
            if type == 0xC0 || type == 0xD0 {
                append(type: type, channel: channel, first: byte, second: 0, into: &events)
            } else if let first = firstDataByte {
                append(type: type, channel: channel, first: first, second: byte, into: &events)
                firstDataByte = nil
            } else {
                firstDataByte = byte
            }
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
