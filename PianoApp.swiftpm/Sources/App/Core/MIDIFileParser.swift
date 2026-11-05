import Foundation

public enum SongImportError: Error, Equatable, LocalizedError {
    case unrecognizedFormat
    case invalidMIDI(String)
    case invalidABC(String)
    case noNotes

    public var errorDescription: String? {
        switch self {
        case .unrecognizedFormat:
            return "Känner inte igen formatet. Klistra in ABC-noter, eller en MIDI-fil som base64/hex."
        case .invalidMIDI(let why):
            return "Kunde inte läsa MIDI-filen: \(why)"
        case .invalidABC(let why):
            return "Kunde inte läsa ABC-noterna: \(why)"
        case .noNotes:
            return "Hittade inga noter att spela."
        }
    }
}

/// Läser Standard MIDI Files (typ 0 och 1).
public enum MIDIFileParser {

    public static func parse(_ data: Data, fallbackTitle: String = "MIDI-låt") throws -> Song {
        var r = ByteReader(bytes: [UInt8](data))

        guard try r.readString(4) == "MThd" else { throw SongImportError.invalidMIDI("saknar MThd-huvud") }
        let headerLength = Int(try r.u32())
        guard headerLength >= 6 else { throw SongImportError.invalidMIDI("för kort huvud") }
        let format = Int(try r.u16())
        let trackCount = Int(try r.u16())
        let division = try r.u16()
        try r.skip(headerLength - 6)
        guard format <= 2 else { throw SongImportError.invalidMIDI("okänt format \(format)") }

        // Tick -> fjärdedelar.
        let ticksPerQuarter: Double
        var smpte = false
        if division & 0x8000 != 0 {
            let fps = Double(-Int(Int8(bitPattern: UInt8(division >> 8))))
            let tpf = Double(division & 0xFF)
            // Låtsas att 120 bpm gäller: en fjärdedel = 0,5 s.
            ticksPerQuarter = max(1, fps * tpf / 2)
            smpte = true
        } else {
            ticksPerQuarter = Double(max(1, division))
        }

        struct OpenNote { var tick: Int; var velocity: Int }
        var tempoEvents: [TempoMap.Event] = []
        var timeSig: (Int, Int)? = nil
        var raw: [RawNote] = []
        var trackNames: [Int: String] = [:]
        var firstTrackName: String?
        // Virtuella spår: (spår, kanal) -> index
        var virtualIndex: [Int: Int] = [:]
        var virtualKeys: [(track: Int, channel: Int)] = []
        var trackNamePerSourceTrack: [Int: String] = [:]

        func vIndex(track: Int, channel: Int) -> Int {
            let key = track << 4 | channel
            if let v = virtualIndex[key] { return v }
            let v = virtualKeys.count
            virtualIndex[key] = v
            virtualKeys.append((track, channel))
            return v
        }

        var tracksRead = 0
        while tracksRead < trackCount && !r.isAtEnd {
            let chunkID = try r.readString(4)
            let length = Int(try r.u32())
            guard chunkID == "MTrk" else {
                try r.skip(length) // okänd chunk
                continue
            }
            let trackIndex = tracksRead
            tracksRead += 1
            let end = min(r.position + length, r.count)
            var tick = 0
            var runningStatus: UInt8 = 0
            var open: [Int: [OpenNote]] = [:] // (kanal<<8|tonhöjd) -> stack

            func close(channel: Int, pitch: Int, at tick: Int) {
                let key = channel << 8 | pitch
                guard var stack = open[key], !stack.isEmpty else { return }
                let on = stack.removeFirst()
                open[key] = stack
                let startBeat = Double(on.tick) / ticksPerQuarter
                let dur = Double(tick - on.tick) / ticksPerQuarter
                raw.append(RawNote(pitch: pitch, startBeat: startBeat, durationBeats: dur, velocity: on.velocity,
                                   track: vIndex(track: trackIndex, channel: channel)))
            }

            while r.position < end {
                tick += Int(try r.vlq())
                var status = try r.u8()
                if status < 0x80 {
                    // Running status: byten var data.
                    guard runningStatus != 0 else { throw SongImportError.invalidMIDI("data utan status") }
                    r.position -= 1
                    status = runningStatus
                }

                switch status {
                case 0xFF:
                    let type = try r.u8()
                    let len = Int(try r.vlq())
                    let payload = try r.bytes(len)
                    switch type {
                    case 0x51 where payload.count >= 3 && !smpte:
                        let usPerQuarter = Int(payload[0]) << 16 | Int(payload[1]) << 8 | Int(payload[2])
                        if usPerQuarter > 0 {
                            tempoEvents.append(.init(beat: Double(tick) / ticksPerQuarter, bpm: 60_000_000.0 / Double(usPerQuarter)))
                        }
                    case 0x58 where payload.count >= 2:
                        if timeSig == nil {
                            timeSig = (Int(payload[0]), 1 << Int(min(payload[1], 6)))
                        }
                    case 0x03:
                        let name = String(decoding: payload, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                        if !name.isEmpty {
                            trackNamePerSourceTrack[trackIndex] = name
                            if trackIndex == 0 { firstTrackName = name }
                        }
                    case 0x2F:
                        r.position = end
                    default:
                        break
                    }
                case 0xF0, 0xF7:
                    let len = Int(try r.vlq())
                    try r.skip(len)
                default:
                    runningStatus = status
                    let kind = status & 0xF0
                    let channel = Int(status & 0x0F)
                    switch kind {
                    case 0x80, 0x90:
                        let pitch = Int(try r.u8() & 0x7F)
                        let velocity = Int(try r.u8() & 0x7F)
                        guard channel != 9 else { break } // trummor
                        if kind == 0x90 && velocity > 0 {
                            open[channel << 8 | pitch, default: []].append(OpenNote(tick: tick, velocity: velocity))
                        } else {
                            close(channel: channel, pitch: pitch, at: tick)
                        }
                    case 0xA0, 0xB0, 0xE0:
                        try r.skip(2)
                    case 0xC0, 0xD0:
                        try r.skip(1)
                    default:
                        throw SongImportError.invalidMIDI("okänd status \(String(status, radix: 16))")
                    }
                }
            }
            // Stäng noter som aldrig släpptes.
            for (key, stack) in open {
                for _ in stack { close(channel: key >> 8, pitch: key & 0xFF, at: tick) }
            }
            r.position = end
        }

        guard !raw.isEmpty else { throw SongImportError.noNotes }

        // Namn på virtuella spår.
        let channelsPerTrack = Dictionary(grouping: virtualKeys, by: \.track).mapValues(\.count)
        for (i, key) in virtualKeys.enumerated() {
            var name = trackNamePerSourceTrack[key.track] ?? "Spår \(key.track + 1)"
            if (channelsPerTrack[key.track] ?? 1) > 1 { name += " (kanal \(key.channel + 1))" }
            trackNames[i] = name
        }

        let tempo = TempoMap(events: tempoEvents.isEmpty ? [.init(beat: 0, bpm: 120)] : tempoEvents)
        let (bpb, beatLen) = SongBuilder.beatGrid(numerator: timeSig?.0 ?? 4, denominator: timeSig?.1 ?? 4)

        // Spår 0 i typ 1 är oftast ett "dirigentspår" med låtens namn.
        var title = fallbackTitle
        if let n = firstTrackName, format == 1 || trackCount == 1 { title = n }

        return SongBuilder.build(
            title: title,
            raw: raw,
            trackNames: trackNames,
            tempoMap: tempo,
            beatsPerBar: bpb,
            beatLength: beatLen
        )
    }
}

/// Enkel big-endian byteläsare.
struct ByteReader {
    let bytes: [UInt8]
    var position = 0

    var count: Int { bytes.count }
    var isAtEnd: Bool { position >= bytes.count }

    mutating func u8() throws -> UInt8 {
        guard position < bytes.count else { throw SongImportError.invalidMIDI("filen tar slut för tidigt") }
        defer { position += 1 }
        return bytes[position]
    }

    mutating func u16() throws -> UInt16 {
        UInt16(try u8()) << 8 | UInt16(try u8())
    }

    mutating func u32() throws -> UInt32 {
        var v: UInt32 = 0
        for _ in 0..<4 { v = v << 8 | UInt32(try u8()) }
        return v
    }

    mutating func vlq() throws -> UInt32 {
        var v: UInt32 = 0
        for _ in 0..<4 {
            let b = try u8()
            v = v << 7 | UInt32(b & 0x7F)
            if b & 0x80 == 0 { return v }
        }
        throw SongImportError.invalidMIDI("felaktigt längdfält")
    }

    mutating func bytes(_ n: Int) throws -> [UInt8] {
        guard n >= 0, position + n <= bytes.count else { throw SongImportError.invalidMIDI("filen tar slut för tidigt") }
        defer { position += n }
        return Array(bytes[position..<position + n])
    }

    mutating func skip(_ n: Int) throws {
        guard n >= 0, position + n <= bytes.count else { throw SongImportError.invalidMIDI("filen tar slut för tidigt") }
        position += n
    }

    mutating func readString(_ n: Int) throws -> String {
        String(decoding: try bytes(n), as: UTF8.self)
    }
}
