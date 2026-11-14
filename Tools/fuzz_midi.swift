// Отправляет случайные MIDI-сообщения: проверка, что приложение не падает на мусоре.
import CoreMIDI
import Foundation

var client = MIDIClientRef()
MIDIClientCreateWithBlock("PianoRoomFuzz" as CFString, &client) { _ in }
var source = MIDIEndpointRef()
MIDISourceCreateWithProtocol(client, "Fuzz Keyboard" as CFString, ._1_0, &source)

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

var generator = SystemRandomNumberGenerator()
for index in 0..<2000 {
    let length = Int.random(in: 1...14, using: &generator)
    let bytes = (0..<length).map { _ in UInt8.random(in: 0...255, using: &generator) }
    send(bytes)
    if index % 500 == 0 { print("отправлено \(index)") }
    usleep(2500)
}
print("fuzz: 2000 случайных сообщений отправлены")
sleep(2)
