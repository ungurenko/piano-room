// Настоящие callbacks CoreMIDI в Swift 6 Release. Сообщения идут только
// от созданного здесь виртуального источника; аппаратные MIDI-выходы не используются.
import CoreMIDI
import Foundation
import os

private enum ReceiveTestError: Error {
    case failed(String)
}

@main
struct MIDIReceiveTest {
    @MainActor
    static func main() async {
        do {
            try await run()
            print("CoreMIDI: виртуальный вход, уведомление и 3 события в Swift 6 Release — OK")
        } catch {
            print("Ошибка проверки CoreMIDI: \(error)")
            exit(1)
        }
    }

    @MainActor
    private static func run() async throws {
        let service = MIDIService()
        let recorded = OSAllocatedUnfairLock(initialState: [MIDIEvent]())
        let sourceChanges = OSAllocatedUnfairLock(initialState: 0)
        service.onEvent = { event in recorded.withLock { $0.append(event) } }
        service.onSourcesChanged = { _ in sourceChanges.withLock { $0 += 1 } }
        guard service.start() else { throw ReceiveTestError.failed("MIDIService.start") }
        defer { service.shutdown() }

        var client = MIDIClientRef()
        try check(MIDIClientCreateWithBlock("MIDI Receive Regression" as CFString, &client) { @Sendable _ in }, operation: "MIDIClientCreateWithBlock")
        defer {
            let status = MIDIClientDispose(client)
            if status != noErr {
                print("MIDIClientDispose: \(status)")
                exit(1)
            }
        }
        var endpoint = MIDIEndpointRef()
        try check(MIDISourceCreateWithProtocol(client, "MIDI Receive Regression" as CFString, ._1_0, &endpoint), operation: "MIDISourceCreateWithProtocol")
        try await wait("уведомление о новом источнике") { sourceChanges.withLock { $0 > 0 } }
        guard let source = service.sources().first(where: { $0.endpoint == endpoint }), service.connect(to: source) else {
            throw ReceiveTestError.failed("Виртуальный вход не подключён")
        }

        var packets = MIDIPacketList()
        let packet = MIDIPacketListInit(&packets)
        let bytes: [UInt8] = [0xC0, 16, 0x90, 60, 100, 0x80, 60, 0]
        let added = bytes.withUnsafeBufferPointer { buffer -> UnsafeMutablePointer<MIDIPacket>? in
            MIDIPacketListAdd(&packets, MemoryLayout<MIDIPacketList>.size, packet, 0, buffer.count, buffer.baseAddress!)
        }
        guard added != nil else { throw ReceiveTestError.failed("MIDIPacketListAdd") }
        try check(MIDIReceived(endpoint, &packets), operation: "MIDIReceived")
        try await wait("приём событий CoreMIDI") { recorded.withLock { $0.count >= 3 } }
        let expected: [MIDIEvent] = [
            .programChange(program: 16, channel: 0),
            .noteOn(note: 60, velocity: 100, channel: 0),
            .noteOff(note: 60, channel: 0)
        ]
        let actual = recorded.withLock { $0 }
        guard actual == expected else {
            throw ReceiveTestError.failed("Ожидалось \(expected), получено \(actual)")
        }
        service.disconnect()
    }

    @MainActor
    private static func wait(_ operation: String, until ready: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !ready() {
            guard ContinuousClock.now < deadline else { throw ReceiveTestError.failed("Истекло ожидание: \(operation)") }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    private static func check(_ status: OSStatus, operation: String) throws {
        guard status == noErr else { throw ReceiveTestError.failed("\(operation): \(status)") }
    }
}
