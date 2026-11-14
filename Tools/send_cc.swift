// Отправляет MIDI-контроллер виртуальной клавиатурой: send_cc 91 127
import CoreMIDI
import Foundation

var client = MIDIClientRef()
MIDIClientCreateWithBlock("PianoRoomCC" as CFString, &client) { _ in }
var source = MIDIEndpointRef()
MIDISourceCreateWithProtocol(client, "CC Keyboard" as CFString, ._1_0, &source)

func send(_ bytes: [UInt8]) {
    var packetList = MIDIPacketList()
    let packet = MIDIPacketListInit(&packetList)
    _ = bytes.withUnsafeBufferPointer { buffer in
        MIDIPacketListAdd(&packetList, 1024, packet, 0, buffer.count, buffer.baseAddress!)
    }
    MIDIReceived(source, &packetList)
}

let args = CommandLine.arguments
let controller = args.count > 1 ? UInt8(args[1]) ?? 91 : 91
let value = args.count > 2 ? UInt8(args[2]) ?? 127 : 127

print("ждём подключения приложения…")
sleep(3)
send([0xB0, controller, value])
print("отправлено CC \(controller) = \(value)")
sleep(4)
