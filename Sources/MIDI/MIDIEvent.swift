import Foundation

/// Разобранное MIDI-событие.
enum MIDIEvent: Equatable, Sendable {
    case noteOn(note: UInt8, velocity: UInt8, channel: UInt8)
    case noteOff(note: UInt8, channel: UInt8)
    case controlChange(controller: UInt8, value: UInt8, channel: UInt8)
    case programChange(program: UInt8, channel: UInt8)
    case pitchBend(value: UInt16, channel: UInt8)
    case channelPressure(value: UInt8, channel: UInt8)
    case polyPressure(note: UInt8, value: UInt8, channel: UInt8)
}
