// Создаёт виртуальную MIDI-клавиатуру и прогоняет все 128 программ General MIDI.
import CoreMIDI
import Foundation

var client = MIDIClientRef()
MIDIClientCreateWithBlock("PianoRoomStress" as CFString, &client) { _ in }

var source = MIDIEndpointRef()
MIDISourceCreateWithProtocol(client, "Stress Keyboard" as CFString, ._1_0, &source)

func send(_ bytes: [UInt8]) {
    var packetList = MIDIPacketList()
    let packet = MIDIPacketListInit(&packetList)
    _ = bytes.withUnsafeBufferPointer { buffer in
        MIDIPacketListAdd(&packetList, 1024, packet, 0, buffer.count, buffer.baseAddress!)
    }
    MIDIReceived(source, &packetList)
}

print("ждём подключения приложения…")
sleep(3)

for program in 0..<128 {
    send([0xC0, UInt8(program)])
    usleep(40_000)
    send([0x90, 60, 80])
    usleep(20_000)
    send([0x80, 60, 0])
}
print("все 128 программ отправлены")
sleep(3)
print("готово")
