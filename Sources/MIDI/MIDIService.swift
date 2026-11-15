import CoreMIDI
import Foundation
import os

private let midiLogger = Logger(subsystem: "com.alexpianoroom.PianoRoom", category: "midi")

struct MIDISource: Identifiable, Hashable, Sendable {
    let id: Int32
    let endpoint: MIDIEndpointRef
    let name: String
    let online: Bool
}

struct MIDIDestination: Identifiable, Hashable, Sendable {
    let id: Int32
    let endpoint: MIDIEndpointRef
    let name: String
}

/// Приём и отправка MIDI через CoreMIDI. Управление соединением выполняется
/// на MainActor; приём остаётся в потоке CoreMIDI, отдельно от интерфейса.
@MainActor
final class MIDIService {

    var onEvent: (@Sendable (MIDIEvent) -> Void)? {
        get { receiver.onEvent }
        set { receiver.onEvent = newValue }
    }
    var onSourcesChanged: (@Sendable ([MIDISource]) -> Void)?

    private var client = MIDIClientRef()
    private var inputPort = MIDIPortRef()
    private var outputPort = MIDIPortRef()
    private var connectedEndpoint: MIDIEndpointRef = 0
    private var connectedUniqueID: Int32 = 0
    private let receiver = MIDIReceiver()

    // MARK: - Жизненный цикл

    @discardableResult
    func start() -> Bool {
        guard client == 0 else { return true }
        var newClient = MIDIClientRef()
        let clientStatus = MIDIClientCreateWithBlock("Piano Room" as CFString, &newClient) { @Sendable [weak self] notification in
            guard notification.pointee.messageID == .msgSetupChanged else { return }
            Task { @MainActor [weak self] in
                self?.handleSetupChanged()
            }
        }
        guard check(clientStatus, operation: "Создать MIDI-клиент") else { return false }

        let inputStatus = MIDIInputPortCreateWithBlock(newClient, "Piano Room In" as CFString, &inputPort) { @Sendable [receiver] packetList, connection in
            guard let connection else { return }
            receiver.receive(packetList, generation: UInt(bitPattern: connection))
        }
        guard check(inputStatus, operation: "Создать MIDI-вход") else {
            check(MIDIClientDispose(newClient), operation: "Закрыть MIDI-клиент")
            inputPort = 0
            return false
        }

        let outputStatus = MIDIOutputPortCreate(newClient, "Piano Room Out" as CFString, &outputPort)
        guard check(outputStatus, operation: "Создать MIDI-выход") else {
            check(MIDIClientDispose(newClient), operation: "Закрыть MIDI-клиент")
            inputPort = 0
            outputPort = 0
            return false
        }
        client = newClient
        return true
    }

    func shutdown() {
        disconnect()
        if client != 0 { check(MIDIClientDispose(client), operation: "Закрыть MIDI-клиент") }
        client = 0
        inputPort = 0
        outputPort = 0
    }

    deinit {
        receiver.invalidate()
        if client != 0 {
            let status = MIDIClientDispose(client)
            if status != noErr { midiLogger.error("Закрыть MIDI-клиент: \(status)") }
        }
    }

    // MARK: - Источники и назначения

    func sources() -> [MIDISource] {
        var result: [MIDISource] = []
        for index in 0..<MIDIGetNumberOfSources() {
            let endpoint = MIDIGetSource(index)
            guard endpoint != 0 else { continue }
            var uniqueID: Int32 = 0
            guard check(MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &uniqueID), operation: "Прочитать MIDI ID") else { continue }
            var offline: Int32 = 0
            let offlineStatus = MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyOffline, &offline)
            // Виртуальный endpoint может не иметь унаследованного свойства offline.
            guard offlineStatus == kMIDIUnknownProperty || check(offlineStatus, operation: "Проверить MIDI-вход") else { continue }
            result.append(MIDISource(
                id: uniqueID,
                endpoint: endpoint,
                name: displayName(of: endpoint) ?? "MIDI-устройство",
                online: offline == 0
            ))
        }
        return result
    }

    func destinations() -> [MIDIDestination] {
        var result: [MIDIDestination] = []
        for index in 0..<MIDIGetNumberOfDestinations() {
            let endpoint = MIDIGetDestination(index)
            guard endpoint != 0 else { continue }
            var uniqueID: Int32 = 0
            guard check(MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &uniqueID), operation: "Прочитать MIDI ID") else { continue }
            var offline: Int32 = 0
            let offlineStatus = MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyOffline, &offline)
            guard offlineStatus == kMIDIUnknownProperty || check(offlineStatus, operation: "Проверить MIDI-выход"), offline == 0 else { continue }
            result.append(MIDIDestination(
                id: uniqueID,
                endpoint: endpoint,
                name: displayName(of: endpoint) ?? "MIDI-устройство"
            ))
        }
        return result
    }

    /// Подключить вход к источнику по его уникальному номеру.
    @discardableResult
    func connect(toUniqueID uniqueID: Int32) -> Bool {
        guard let source = sources().first(where: { $0.id == uniqueID && $0.online }) else { return false }
        return connect(to: source)
    }

    @discardableResult
    func connect(to source: MIDISource) -> Bool {
        guard inputPort != 0, source.online, source.endpoint != 0 else { return false }
        if connectedEndpoint == source.endpoint, connectedUniqueID == source.id { return true }
        disconnect()
        let generation = receiver.beginConnection()
        // Это числовая метка соединения: указатель не разыменовывается.
        let status = MIDIPortConnectSource(inputPort, source.endpoint, UnsafeMutableRawPointer(bitPattern: generation))
        guard check(status, operation: "Подключить MIDI-вход") else {
            receiver.invalidate()
            return false
        }
        connectedEndpoint = source.endpoint
        connectedUniqueID = source.id
        return true
    }

    /// Отменяет также уже поступившие пакеты старого соединения.
    func disconnect() {
        receiver.invalidate()
        let endpoint = connectedEndpoint
        connectedEndpoint = 0
        connectedUniqueID = 0
        if endpoint != 0, inputPort != 0 {
            check(MIDIPortDisconnectSource(inputPort, endpoint), operation: "Отключить MIDI-вход")
        }
    }

    var currentUniqueID: Int32 { connectedUniqueID }

    private func handleSetupChanged() {
        guard client != 0 else { return }
        let all = sources()
        if connectedUniqueID != 0 {
            if let fresh = all.first(where: { $0.id == connectedUniqueID && $0.online }) {
                connect(to: fresh)
            } else {
                disconnect()
            }
        }
        onSourcesChanged?(all)
    }

    // MARK: - Отправка

    /// Управляет внешним устройством, например встроенным звуком через CC122.
    @discardableResult
    func sendController(_ controller: UInt8, value: UInt8, channel: UInt8, to destination: MIDIDestination) -> Bool {
        guard outputPort != 0, controller < 128, value < 128, channel < 16 else { return false }
        var packetList = MIDIPacketList()
        let bytes: [UInt8] = [0xB0 | channel, controller, value]
        let packet = MIDIPacketListInit(&packetList)
        let added = bytes.withUnsafeBufferPointer { buffer -> UnsafeMutablePointer<MIDIPacket>? in
            MIDIPacketListAdd(&packetList, MemoryLayout<MIDIPacketList>.size, packet, 0, buffer.count, buffer.baseAddress!)
        }
        guard added != nil else { return false }
        return check(MIDISend(outputPort, destination.endpoint, &packetList), operation: "Отправить MIDI-контроллер")
    }

    func pianoDestination() -> MIDIDestination? {
        destinations().first { destination in
            let lowered = destination.name.lowercased()
            return lowered.contains("5704") || lowered.contains("piano") || lowered.contains("pia")
        }
    }

    // MARK: - Разбор входящего потока

    /// Читает переменную длину прямо из памяти CoreMIDI, включая байты за data[256].
    nonisolated static func events(in packetList: UnsafePointer<MIDIPacketList>, parser: inout MIDIParser) -> [MIDIEvent] {
        guard let packetOffset = MemoryLayout<MIDIPacketList>.offset(of: \.packet),
              let dataOffset = MemoryLayout<MIDIPacket>.offset(of: \.data) else { return [] }
        var events: [MIDIEvent] = []
        var packet = UnsafeMutablePointer<MIDIPacket>(mutating:
            UnsafeRawPointer(packetList).advanced(by: packetOffset).assumingMemoryBound(to: MIDIPacket.self))
        for _ in 0..<packetList.pointee.numPackets {
            let length = Int(packet.pointee.length)
            let bytes = UnsafeRawPointer(packet).advanced(by: dataOffset).assumingMemoryBound(to: UInt8.self)
            events.append(contentsOf: parser.parse(Array(UnsafeBufferPointer(start: bytes, count: length))))
            packet = MIDIPacketNext(packet)
        }
        return events
    }

    private func displayName(of endpoint: MIDIEndpointRef) -> String? {
        var name: Unmanaged<CFString>?
        guard check(MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &name), operation: "Прочитать имя MIDI-устройства"), let name else { return nil }
        return name.takeRetainedValue() as String
    }

    @discardableResult
    private func check(_ status: OSStatus, operation: String) -> Bool {
        guard status != noErr else { return true }
        midiLogger.error("\(operation, privacy: .public): \(status)")
        return false
    }
}

/// Все поля и доставка callback защищены lock. invalidate ждёт завершения
/// текущего callback, поэтому после отключения старые ноты уже не поступят.
/// Callback передаёт события клиенту; управление MIDI-сервисом из него
/// выполняется асинхронно на MainActor.
final class MIDIReceiver: @unchecked Sendable {
    private let lock = NSLock()
    private var parser = MIDIParser()
    private var generation: UInt = 0
    private var accepting = false
    private var handler: (@Sendable (MIDIEvent) -> Void)?

    var onEvent: (@Sendable (MIDIEvent) -> Void)? {
        get { lock.withLock { handler } }
        set { lock.withLock { handler = newValue } }
    }

    func beginConnection() -> UInt {
        lock.withLock {
            generation &+= 1
            if generation == 0 { generation = 1 }
            accepting = true
            parser.reset()
            return generation
        }
    }

    func invalidate() {
        lock.withLock {
            accepting = false
            parser.reset()
        }
    }

    func receive(_ packetList: UnsafePointer<MIDIPacketList>, generation: UInt) {
        lock.withLock {
            guard accepting, self.generation == generation else { return }
            for event in MIDIService.events(in: packetList, parser: &parser) {
                handler?(event)
            }
        }
    }
}
