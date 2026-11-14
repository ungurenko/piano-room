import CoreMIDI
import Foundation

struct MIDISource: Identifiable, Hashable {
    let id: Int32
    let endpoint: MIDIEndpointRef
    let name: String
    let online: Bool
}

struct MIDIDestination: Identifiable, Hashable {
    let id: Int32
    let endpoint: MIDIEndpointRef
    let name: String
}

/// Приём и отправка MIDI через CoreMIDI.
///
/// События разбираются прямо в колбэке CoreMIDI и сразу отдаются движку: это
/// быстрый и безопасный путь без записи на диск и без блокировок.
final class MIDIService {

    var onEvent: ((MIDIEvent) -> Void)?
    var onSourcesChanged: (([MIDISource]) -> Void)?

    private var client = MIDIClientRef()
    private var inputPort = MIDIPortRef()
    private var outputPort = MIDIPortRef()
    private var connectedEndpoint: MIDIEndpointRef = 0
    private var connectedUniqueID: Int32 = 0
    private var isRunning = false

    private var parser = MIDIParser()

    private let lock = NSLock()

    // MARK: - Жизненный цикл

    func start() {
        guard !isRunning else { return }
        isRunning = true

        MIDIClientCreateWithBlock("Piano Room" as CFString, &client) { [weak self] notification in
            guard let self else { return }
            if notification.pointee.messageID == .msgSetupChanged {
                DispatchQueue.main.async {
                    self.onSourcesChanged?(self.sources())
                }
                self.reconnectIfNeeded()
            }
        }

        MIDIInputPortCreateWithBlock(client, "Piano Room In" as CFString, &inputPort) { [weak self] packetList, _ in
            self?.handlePackets(packetList)
        }

        MIDIOutputPortCreate(client, "Piano Room Out" as CFString, &outputPort)
    }

    func shutdown() {
        guard isRunning else { return }
        if connectedEndpoint != 0 {
            MIDIPortDisconnectSource(inputPort, connectedEndpoint)
            connectedEndpoint = 0
        }
        if client != 0 { MIDIClientDispose(client) }
        client = 0
        isRunning = false
    }

    // MARK: - Источники и назначения

    func sources() -> [MIDISource] {
        var result: [MIDISource] = []
        let count = MIDIGetNumberOfSources()
        guard count > 0 else { return result }

        for index in 0..<count {
            let endpoint = MIDIGetSource(index)
            guard endpoint != 0 else { continue }

            var uniqueID: Int32 = 0
            MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &uniqueID)

            var offline: Int32 = 0
            MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyOffline, &offline)

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
        let count = MIDIGetNumberOfDestinations()
        guard count > 0 else { return result }

        for index in 0..<count {
            let endpoint = MIDIGetDestination(index)
            guard endpoint != 0 else { continue }
            var uniqueID: Int32 = 0
            MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &uniqueID)
            result.append(MIDIDestination(
                id: uniqueID,
                endpoint: endpoint,
                name: displayName(of: endpoint) ?? "MIDI-устройство"
            ))
        }
        return result
    }

    /// Подключить вход к источнику по его уникальному номеру.
    func connect(toUniqueID uniqueID: Int32) {
        let all = sources()
        guard let source = all.first(where: { $0.id == uniqueID }) else { return }
        connect(to: source)
    }

    func connect(to source: MIDISource) {
        lock.lock()
        defer { lock.unlock() }

        if connectedEndpoint != 0 {
            MIDIPortDisconnectSource(inputPort, connectedEndpoint)
            connectedEndpoint = 0
        }
        let status = MIDIPortConnectSource(inputPort, source.endpoint, nil)
        if status == noErr {
            connectedEndpoint = source.endpoint
            connectedUniqueID = source.id
        }
    }

    var currentUniqueID: Int32 {
        lock.lock()
        defer { lock.unlock() }
        return connectedUniqueID
    }

    private func reconnectIfNeeded() {
        lock.lock()
        let wanted = connectedUniqueID
        lock.unlock()
        guard wanted != 0 else { return }

        let all = sources()
        if let fresh = all.first(where: { $0.id == wanted }), fresh.online {
            connect(to: fresh)
        }
    }

    // MARK: - Отправка

    /// Отправить управляющее сообщение во внешнее устройство (например, заглушить
    /// встроенный звук цифрового пианино командой CC122).
    @discardableResult
    func sendController(_ controller: UInt8, value: UInt8, channel: UInt8, to destination: MIDIDestination) -> Bool {
        var packetList = MIDIPacketList()
        let bytes: [UInt8] = [0xB0 | (channel & 0x0F), controller, value]
        let packet = MIDIPacketListInit(&packetList)
        let added = bytes.withUnsafeBufferPointer { buffer -> UnsafeMutablePointer<MIDIPacket>? in
            MIDIPacketListAdd(&packetList, 1024, packet, 0, buffer.count, buffer.baseAddress!)
        }
        guard added != nil else { return false }
        return MIDISend(outputPort, destination.endpoint, &packetList) == noErr
    }

    /// Найти MIDI-назначение пианино Grace CP-250 по имени.
    func pianoDestination() -> MIDIDestination? {
        destinations().first { destination in
            let lowered = destination.name.lowercased()
            return lowered.contains("5704") || lowered.contains("piano") || lowered.contains("pia")
        }
    }

    // MARK: - Разбор входящего потока

    private func handlePackets(_ packetList: UnsafePointer<MIDIPacketList>) {
        var events: [MIDIEvent] = []
        guard let packetOffset = MemoryLayout<MIDIPacketList>.offset(of: \.packet) else { return }
        var packetPointer = UnsafeMutablePointer<MIDIPacket>(
            mutating: UnsafeRawPointer(packetList)
                .advanced(by: packetOffset)
                .assumingMemoryBound(to: MIDIPacket.self)
        )

        for _ in 0..<packetList.pointee.numPackets {
            let packet = packetPointer.pointee
            let length = Int(packet.length)
            if length > 0 {
                withUnsafeBytes(of: packet.data) { raw in
                    let bytes = Array(raw.prefix(length))
                    events.append(contentsOf: parser.parse(bytes))
                }
            }
            packetPointer = MIDIPacketNext(packetPointer)
        }

        guard !events.isEmpty else { return }
        for event in events {
            onEvent?(event)
        }
    }

    private func displayName(of endpoint: MIDIEndpointRef) -> String? {
        var name: Unmanaged<CFString>?
        let status = MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &name)
        guard status == noErr, let name else { return nil }
        return name.takeRetainedValue() as String
    }
}
