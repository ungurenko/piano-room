// Двухминутная непрерывная игра: аккорды, переключение программ, педаль.
import CoreMIDI
import Foundation

var client = MIDIClientRef()
MIDIClientCreateWithBlock("PianoRoomSoak" as CFString, &client) { _ in }
var source = MIDIEndpointRef()
MIDISourceCreateWithProtocol(client, "Soak Keyboard" as CFString, ._1_0, &source)

func send(_ bytes: [UInt8]) {
    var packetList = MIDIPacketList()
    let packet = MIDIPacketListInit(&packetList)
    _ = bytes.withUnsafeBufferPointer { buffer in
        MIDIPacketListAdd(&packetList, 1024, packet, 0, buffer.count, buffer.baseAddress!)
    }
    MIDIReceived(source, &packetList)
}

sleep(3)
let duration = 120.0
let start = Date()
var step = 0
while Date().timeIntervalSince(start) < duration {
    let base = UInt8(48 + (step % 24))
    send([0x90, base, 90])
    send([0x90, base + 4, 90])
    send([0x90, base + 7, 90])
    if step % 8 == 0 { send([0xB0, 64, 127]) }
    usleep(60_000)
    send([0x80, base, 0])
    send([0x80, base + 4, 0])
    send([0x80, base + 7, 0])
    usleep(60_000)
    step += 1
    if step % 40 == 0 {
        send([0xC0, UInt8(step % 128)])
        send([0xB0, 64, 0])
    }
}
print("soak: отправлено \(step) аккордов за \(Int(duration)) секунд")
