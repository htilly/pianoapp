import Foundation
import CoreMIDI
import Observation

/// En MIDI-enhet (källa eller mål).
struct MIDIDevice: Identifiable, Hashable {
    let id: MIDIUniqueID
    let name: String
    let endpoint: MIDIEndpointRef
}

/// Ansluter till alla MIDI-källor (USB, Bluetooth, nätverk) och skickar
/// tangenttryck vidare. Kan också skicka toner till pianot.
@MainActor
@Observable
final class MIDIManager {

    private(set) var sources: [MIDIDevice] = []
    private(set) var destinations: [MIDIDevice] = []
    private(set) var lastError: String?
    /// Toner som just nu hålls nere på pianot.
    private(set) var pressedKeys: Set<Int> = []

    /// Valt mål för appens toner (nil = automatiskt första).
    var selectedDestinationID: MIDIUniqueID? {
        didSet { UserDefaults.standard.set(Int(selectedDestinationID ?? 0), forKey: "midi.destination") }
    }

    /// Anropas på huvudtråden för varje tangent (tonhöjd, nedtryckt?, styrka).
    @ObservationIgnored var onNote: (@MainActor (Int, Bool, Int) -> Void)?

    @ObservationIgnored private var client = MIDIClientRef()
    @ObservationIgnored private var inputPort = MIDIPortRef()
    @ObservationIgnored private var outputPort = MIDIPortRef()
    @ObservationIgnored private var connected: Set<MIDIEndpointRef> = []
    /// Toner vi själva skickat – för att inte tolka ett eko från pianot som ett tryck.
    @ObservationIgnored private var recentlySent: [Int: Date] = [:]

    var isConnected: Bool { !sources.isEmpty }

    var activeDestination: MIDIDevice? {
        if let id = selectedDestinationID, let d = destinations.first(where: { $0.id == id }) { return d }
        return destinations.first
    }

    init() {
        let stored = UserDefaults.standard.integer(forKey: "midi.destination")
        selectedDestinationID = stored == 0 ? nil : MIDIUniqueID(stored)
        setUp()
    }

    // MARK: - Uppsättning

    private func setUp() {
        let box = MIDIWeakBox(self)
        let status = MIDIClientCreateWithBlock("Pianoskola" as CFString, &client, Self.makeNotifyBlock(box))
        guard status == noErr else {
            lastError = "Kunde inte starta MIDI (\(status))."
            return
        }
        MIDIInputPortCreateWithProtocol(client, "Pianoskola in" as CFString, ._1_0, &inputPort, Self.makeReceiveBlock(box))
        MIDIOutputPortCreate(client, "Pianoskola ut" as CFString, &outputPort)
        refresh()
    }

    /// Blocken anropas på CoreMIDI:s egen tråd, så de skapas utanför huvudaktören.
    nonisolated private static func makeNotifyBlock(_ box: MIDIWeakBox) -> MIDINotifyBlock {
        return { notification in
            let id = notification.pointee.messageID
            if id == .msgSetupChanged || id == .msgObjectAdded || id == .msgObjectRemoved {
                Task { @MainActor in box.manager?.refresh() }
            }
        }
    }

    nonisolated private static func makeReceiveBlock(_ box: MIDIWeakBox) -> MIDIReceiveBlock {
        return { eventList, _ in
            let messages = MIDIManager.decode(eventList)
            guard !messages.isEmpty else { return }
            Task { @MainActor in box.manager?.handle(messages) }
        }
    }

    /// Läser om listan över enheter och ansluter till nya källor.
    func refresh() {
        var newSources: [MIDIDevice] = []
        for i in 0..<MIDIGetNumberOfSources() {
            let ep = MIDIGetSource(i)
            guard ep != 0 else { continue }
            newSources.append(MIDIDevice(id: Self.uniqueID(ep), name: Self.name(of: ep), endpoint: ep))
            if !connected.contains(ep) {
                if MIDIPortConnectSource(inputPort, ep, nil) == noErr { connected.insert(ep) }
            }
        }
        let current = Set(newSources.map(\.endpoint))
        for ep in connected where !current.contains(ep) {
            MIDIPortDisconnectSource(inputPort, ep)
        }
        connected = connected.intersection(current)
        sources = newSources

        var newDest: [MIDIDevice] = []
        for i in 0..<MIDIGetNumberOfDestinations() {
            let ep = MIDIGetDestination(i)
            guard ep != 0 else { continue }
            newDest.append(MIDIDevice(id: Self.uniqueID(ep), name: Self.name(of: ep), endpoint: ep))
        }
        destinations = newDest
        if sources.isEmpty { pressedKeys = [] }
    }

    // MARK: - In

    fileprivate struct Message: Sendable {
        var status: UInt8
        var data1: UInt8
        var data2: UInt8
    }

    /// Avkodar Universal MIDI Packets (MIDI 1.0 kanalmeddelanden, typ 2).
    nonisolated fileprivate static func decode(_ list: UnsafePointer<MIDIEventList>) -> [Message] {
        var out: [Message] = []
        for packet in list.unsafeSequence() {
            let count = Int(packet.pointee.wordCount)
            withUnsafeBytes(of: packet.pointee.words) { raw in
                let words = raw.bindMemory(to: UInt32.self)
                var i = 0
                while i < count && i < words.count {
                    let w = words[i]
                    let type = w >> 28
                    switch type {
                    case 0x2:
                        out.append(Message(status: UInt8((w >> 16) & 0xFF), data1: UInt8((w >> 8) & 0x7F), data2: UInt8(w & 0x7F)))
                        i += 1
                    case 0x4:
                        // MIDI 2.0 kanalmeddelande (64 bitar) – om enheten ändå skickar det.
                        let status = UInt8((w >> 16) & 0xFF)
                        let note = UInt8((w >> 8) & 0x7F)
                        let v16 = i + 1 < words.count ? words[i + 1] >> 16 : 0
                        out.append(Message(status: status, data1: note, data2: UInt8(min(127, v16 >> 9))))
                        i += 2
                    case 0x0, 0x1, 0x6, 0x7:
                        i += 1
                    case 0x3, 0x8, 0x9, 0xA:
                        i += 2
                    case 0xB, 0xC:
                        i += 3
                    default:
                        i += 4
                    }
                }
            }
        }
        return out
    }

    fileprivate func handle(_ messages: [Message]) {
        for m in messages {
            let kind = m.status & 0xF0
            let pitch = Int(m.data1)
            switch kind {
            case 0x90 where m.data2 > 0:
                if let t = recentlySent[pitch], Date().timeIntervalSince(t) < 0.08 { continue } // eko
                pressedKeys.insert(pitch)
                onNote?(pitch, true, Int(m.data2))
            case 0x80, 0x90:
                if pressedKeys.remove(pitch) != nil {
                    onNote?(pitch, false, 0)
                }
            default:
                break
            }
        }
    }

    // MARK: - Ut

    var canSend: Bool { activeDestination != nil }

    func sendNoteOn(_ pitch: Int, velocity: Int, channel: UInt8 = 0) {
        recentlySent[pitch] = Date()
        send(status: 0x90 | channel, pitch, UInt8(min(127, max(1, velocity))))
    }

    func sendNoteOff(_ pitch: Int, channel: UInt8 = 0) {
        send(status: 0x80 | channel, pitch, 0)
    }

    /// Släpp alla toner (CC 123) på alla mål.
    func allNotesOff() {
        for ch in 0..<UInt8(16) { send(status: 0xB0 | ch, 123, 0) }
    }

    private func send(status: UInt8, _ d1: Int, _ d2: UInt8) {
        guard let dest = activeDestination?.endpoint, outputPort != 0 else { return }
        let word: UInt32 = (0x2 << 28) | (UInt32(status) << 16) | (UInt32(d1 & 0x7F) << 8) | UInt32(d2)
        var list = MIDIEventList()
        withUnsafeMutablePointer(to: &list) { listPtr in
            let packet = MIDIEventListInit(listPtr, ._1_0)
            var w = word
            _ = MIDIEventListAdd(listPtr, MemoryLayout<MIDIEventList>.size, packet, 0, 1, &w)
            _ = MIDISendEventList(outputPort, dest, listPtr)
        }
    }

    // MARK: - Hjälp

    private static func name(of obj: MIDIObjectRef) -> String {
        var cf: Unmanaged<CFString>?
        if MIDIObjectGetStringProperty(obj, kMIDIPropertyDisplayName, &cf) == noErr, let s = cf?.takeRetainedValue() {
            return s as String
        }
        if MIDIObjectGetStringProperty(obj, kMIDIPropertyName, &cf) == noErr, let s = cf?.takeRetainedValue() {
            return s as String
        }
        return "MIDI-enhet"
    }

    private static func uniqueID(_ obj: MIDIObjectRef) -> MIDIUniqueID {
        var id = MIDIUniqueID()
        MIDIObjectGetIntegerProperty(obj, kMIDIPropertyUniqueID, &id)
        return id
    }
}

/// Svag referens som kan skickas mellan trådar.
final class MIDIWeakBox: @unchecked Sendable {
    weak var manager: MIDIManager?
    init(_ m: MIDIManager) { manager = m }
}
