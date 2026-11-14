import CoreMIDI
import Foundation

var client = MIDIClientRef()
MIDIClientCreateWithBlock("PianoRoomTest" as CFString, &client) { _ in }

var source = MIDIEndpointRef()
MIDISourceCreateWithProtocol(client, "Test Keyboard" as CFString, ._1_0, &source)

func send(_ bytes: [UInt8]) {
    var packetList = MIDIPacketList()
    let packet = MIDIPacketListInit(&packetList)
    _ = bytes.withUnsafeBufferPointer { buffer in
        MIDIPacketListAdd(&packetList, 1024, packet, 0, buffer.count, buffer.baseAddress!)
    }
    MIDIReceived(source, &packetList)
}

let arguments = CommandLine.arguments
let program: UInt8 = arguments.count > 1 ? UInt8(arguments[1]) ?? 0 : 0
let playNotes = !arguments.contains("--no-notes")

print("источник создан, ждём подключения приложения…")
sleep(3)
print("отправляем Program Change \(program)")
send([0xC0, program])
sleep(1)
if playNotes {
    let notes: [UInt8] = [60, 64, 67]
    for note in notes { send([0x90, note, 96]); usleep(120_000) }
    print("аккорд играет")
    sleep(4)
    for note in notes { send([0x80, note, 0]) }
}
print("готово")
