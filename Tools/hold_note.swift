// Виртуальная клавиатура: зажимает ноту и держит, чтобы проверить залипание.
import CoreMIDI
import Foundation

var client = MIDIClientRef()
MIDIClientCreateWithBlock("PianoRoomHold" as CFString, &client) { _ in }
var source = MIDIEndpointRef()
MIDISourceCreateWithProtocol(client, "Hold Keyboard" as CFString, ._1_0, &source)

func send(_ bytes: [UInt8]) {
    var packetList = MIDIPacketList()
    let packet = MIDIPacketListInit(&packetList)
    _ = bytes.withUnsafeBufferPointer { buffer in
        MIDIPacketListAdd(&packetList, 1024, packet, 0, buffer.count, buffer.baseAddress!)
    }
    MIDIReceived(source, &packetList)
}

sleep(3)
send([0x90, 60, 100])
send([0x90, 64, 100])
print("ноты зажаты и не отпускаются")
sleep(40)
