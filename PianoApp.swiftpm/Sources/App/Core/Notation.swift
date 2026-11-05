import Foundation

// Gör om en låts toner till vanlig notskrift: tonart, notvärden, förtecken,
// pauser, balkar och bindebågar. Ren logik utan ritkod, så att den kan testas.
//
// Låtarna lagras som toner med tider, utan notbild. Därför gissas tonarten och
// rytmen avrundas till läsbara notvärden. Varje system visas enstämmigt: en ton
// som klingar vidare när nästa ton börjar skrivs bara fram till den tonen.

public enum Accidental: Sendable {
    case sharp, flat, natural
}

public enum Clef: Sendable, Hashable {
    case treble, bass

    /// Steget (se `SpelledPitch.step`) för systemets nedersta linje: E4 eller G2.
    var bottomLineStep: Int { self == .treble ? 30 : 18 }
}

/// En ton stavad med notnamn, t.ex. Bb4: letter 6 (B), alter -1, octave 4.
public struct SpelledPitch: Hashable, Sendable {
    /// 0 = C, 1 = D … 6 = B.
    public var letter: Int
    /// -1 = sänkt, 0 = oförändrad, 1 = höjd.
    public var alter: Int
    public var octave: Int

    /// Stamtonens plats i hela tonhöjdsskalan, ett steg per linje eller mellanrum.
    public var step: Int { octave * 7 + letter }
}

public struct KeySignature: Hashable, Sendable {
    /// Antal korsförtecken, negativt för b-förtecken.
    public var fifths: Int

    private static let naturalPitchClass = [0, 2, 4, 5, 7, 9, 11]
    private static let sharpOrder = [3, 0, 4, 1, 5, 2, 6]  // F C G D A E B
    private static let flatOrder = [6, 2, 5, 1, 4, 0, 3]   // B E A D G C F

    public init(fifths: Int) {
        self.fifths = max(-7, min(7, fifths))
    }

    public func alter(ofLetter letter: Int) -> Int {
        if fifths > 0 { return Self.sharpOrder.prefix(fifths).contains(letter) ? 1 : 0 }
        if fifths < 0 { return Self.flatOrder.prefix(-fifths).contains(letter) ? -1 : 0 }
        return 0
    }

    /// Stavar en ton: tonartens egna toner först, annars stamton eller löst förtecken.
    public func spell(_ pitch: Int) -> SpelledPitch {
        let pc = ((pitch % 12) + 12) % 12
        var letter = 0
        var alter = 0
        if let inKey = (0..<7).first(where: {
            ((Self.naturalPitchClass[$0] + self.alter(ofLetter: $0)) % 12 + 12) % 12 == pc
        }) {
            letter = inKey
            alter = self.alter(ofLetter: inKey)
        } else if let natural = Self.naturalPitchClass.firstIndex(of: pc) {
            letter = natural
        } else if fifths < 0 {
            letter = Self.naturalPitchClass.firstIndex(of: pc + 1) ?? 0
            alter = -1
        } else {
            letter = Self.naturalPitchClass.firstIndex(of: pc - 1) ?? 0
            alter = 1
        }
        // Oktaven följer stamtonen: Cb5 klingar som H4.
        let naturalPitch = pitch - alter
        let octave = Int(floor(Double(naturalPitch) / 12)) - 1
        return SpelledPitch(letter: letter, alter: alter, octave: octave)
    }

    /// Den dur-tonart där tonerna behöver minst lösa förtecken. Enklast vinner vid lika.
    public static func estimate(pitches: [Int]) -> KeySignature {
        var counts = [Int](repeating: 0, count: 12)
        for p in pitches { counts[((p % 12) + 12) % 12] += 1 }
        var best = KeySignature(fifths: 0)
        var bestCost = Double.infinity
        for fifths in -6...6 {
            let key = KeySignature(fifths: fifths)
            let inKey = Set((0..<7).map { ((naturalPitchClass[$0] + key.alter(ofLetter: $0)) % 12 + 12) % 12 })
            let outside = (0..<12).filter { !inKey.contains($0) }.map { counts[$0] }.reduce(0, +)
            let cost = Double(outside) + (0.02 * Double(pitches.count) / 6 + 0.001) * Double(abs(fifths))
            if cost < bestCost {
                bestCost = cost
                best = key
            }
        }
        return best
    }

    /// Var förtecknen i tonartssignaturen står (se `NotationHead.position`).
    public func signaturePositions(clef: Clef) -> [(position: Int, accidental: Accidental)] {
        let shift = clef == .treble ? 0 : -2
        let sharps = [8, 5, 9, 6, 3, 7, 4]
        let flats = [4, 7, 3, 6, 2, 5, 1]
        if fifths > 0 { return sharps.prefix(fifths).map { ($0 + shift, .sharp) } }
        if fifths < 0 { return flats.prefix(-fifths).map { ($0 + shift, .flat) } }
        return []
    }
}

public enum NoteValue: Sendable {
    case whole, half, quarter, eighth, sixteenth

    /// Antal balkar eller flaggor.
    public var beams: Int {
        switch self {
        case .eighth: return 1
        case .sixteenth: return 2
        default: return 0
        }
    }
}

public struct NotationHead: Hashable, Sendable {
    /// Index i `Song.notes`.
    public var noteIndex: Int
    public var pitch: Int
    public var spelled: SpelledPitch
    /// Halva radavstånd över systemets nedersta linje: 0 = nedersta linjen,
    /// 1 = mellanrummet ovanför, 8 = översta linjen, -2 = första hjälplinjen under.
    public var position: Int
    /// Förtecken som ska skrivas ut framför noten.
    public var accidental: Accidental?
    public var part: Part
}

public struct NotationChord: Hashable, Sendable {
    public var clef: Clef
    /// Position i tick (12 per fjärdedel).
    public var start: Int
    public var ticks: Int
    public var value: NoteValue
    public var dotted: Bool
    public var triplet: Bool
    /// Sorterade nedifrån och upp.
    public var heads: [NotationHead]
    public var stemUp: Bool
    /// Index i `Notation.beamGroups`.
    public var beamGroup: Int?
    /// Bindebåge till nästa del av samma ton.
    public var tiesToNext: Bool

    public var end: Int { start + ticks }
}

public struct NotationRest: Hashable, Sendable {
    public var clef: Clef
    public var start: Int
    public var ticks: Int
    public var value: NoteValue
    public var triplet: Bool
    /// Hel takts paus: ritas mitt i takten.
    public var fillsBar: Bool
}

public struct Notation: Sendable {
    public static let ticksPerQuarter = 12

    public let key: KeySignature
    public let timeSignature: (numerator: Int, denominator: Int)
    public let barTicks: Int
    public let barCount: Int
    /// Notsystemen uppifrån och ner: bara de som låten använder.
    public let clefs: [Clef]
    /// Sorterade efter position.
    public let chords: [NotationChord]
    public let rests: [NotationRest]
    /// Index i `chords` för noter som binds ihop med en balk.
    public let beamGroups: [[Int]]
    /// Kortaste notvärde, i tick. Styr hur glest noterna står.
    public let shortestTicks: Int

    private let tempoMap: TempoMap

    public var endTick: Int { barCount * barTicks }

    /// Position i tick vid en tid i låten.
    public func tick(atTime seconds: Double) -> Double {
        tempoMap.beat(atSeconds: seconds) * Double(Self.ticksPerQuarter)
    }

    public func time(atTick tick: Double) -> Double {
        tempoMap.seconds(atBeat: tick / Double(Self.ticksPerQuarter))
    }

    /// Vilket system en tangent skrivs i, och var, när den inte kommer från noterna.
    public func placement(ofPitch pitch: Int) -> (clef: Clef, spelled: SpelledPitch, position: Int) {
        let preferred: Clef = pitch >= 60 ? .treble : .bass
        let clef = clefs.contains(preferred) ? preferred : (clefs.first ?? .treble)
        let spelled = key.spell(pitch)
        return (clef, spelled, spelled.step - clef.bottomLineStep)
    }

    public init(song: Song) {
        tempoMap = song.tempoMap
        key = KeySignature.estimate(pitches: song.notes.map(\.pitch))

        let quarterAt = { (seconds: Double) in song.tempoMap.beat(atSeconds: seconds) }
        var beatQuarters = 1.0
        if song.beatTimes.count >= 2 {
            beatQuarters = quarterAt(song.beatTimes[1]) - quarterAt(song.beatTimes[0])
        }
        let meter = Self.meter(beatsPerBar: song.beatsPerBar, beatQuarters: beatQuarters)
        timeSignature = meter
        let bar = max(3, meter.numerator * 48 / meter.denominator)
        barTicks = bar

        // Toner per system, avrundade till läsbar rytm.
        struct Quantized {
            var index: Int
            var note: Note
            var start: Int
            var end: Int
        }
        var perClef: [Clef: [Quantized]] = [:]
        for (i, n) in song.notes.enumerated() {
            let start = Self.quantize(quarterAt(n.start))
            let end = max(Self.quantize(quarterAt(n.end)), start + 3)
            perClef[Self.clef(for: n), default: []]
                .append(Quantized(index: i, note: n, start: start, end: end))
        }

        let lastEnd = perClef.values.joined().map(\.end).max() ?? bar
        let bars = max(1, Int((Double(lastEnd) / Double(bar)).rounded(.up)))
        barCount = bars
        clefs = [Clef.treble, .bass].filter { perClef[$0] != nil }

        var chords: [NotationChord] = []
        var rests: [NotationRest] = []
        let key = self.key
        for clef in clefs {
            let notes = perClef[clef] ?? []
            let starts = Set(notes.map(\.start)).sorted()
            let grouped = Dictionary(grouping: notes, by: \.start)
            var accidentals = BarAccidentals(key: key)
            var cursor = 0
            for (i, start) in starts.enumerated() {
                let group = grouped[start] ?? []
                var end = group.map(\.end).max() ?? start + 3
                if i + 1 < starts.count {
                    let next = starts[i + 1]
                    // Enstämmigt: stanna vid nästa ton, och täpp till små luckor
                    // så att spelad legato inte blir fulla av sextondelspauser.
                    if end > next || next - end <= 3 { end = next }
                } else {
                    // Sista tonen: täpp på samma sätt till fram till taktstrecket.
                    let barEnd = (end + bar - 1) / bar * bar
                    if barEnd - end <= 3 { end = barEnd }
                }
                if start > cursor {
                    rests += Self.rests(clef: clef, from: cursor, to: start, bar: bar)
                }
                cursor = end

                var heads: [NotationHead] = []
                var seen = Set<Int>()
                for q in group where seen.insert(q.note.pitch).inserted {
                    let spelled = key.spell(q.note.pitch)
                    heads.append(NotationHead(
                        noteIndex: q.index,
                        pitch: q.note.pitch,
                        spelled: spelled,
                        position: spelled.step - clef.bottomLineStep,
                        accidental: nil,
                        part: q.note.part
                    ))
                }
                heads.sort { $0.position < $1.position }

                let pieces = Self.pieces(from: start, to: end, bar: bar)
                for (p, piece) in pieces.enumerated() {
                    if piece.start / bar != accidentals.bar {
                        accidentals.startBar(piece.start / bar)
                    }
                    var pieceHeads = heads
                    for h in pieceHeads.indices {
                        let shown = accidentals.update(heads[h].spelled)
                        // Fortsättningen på en bunden ton skriver inte om förtecknet.
                        pieceHeads[h].accidental = p == 0 ? shown : nil
                    }
                    chords.append(NotationChord(
                        clef: clef,
                        start: piece.start,
                        ticks: piece.ticks,
                        value: piece.value,
                        dotted: piece.dotted,
                        triplet: piece.triplet,
                        heads: pieceHeads,
                        stemUp: Self.stemUp(heads: pieceHeads),
                        beamGroup: nil,
                        tiesToNext: p < pieces.count - 1
                    ))
                }
            }
            if bars * bar > cursor {
                rests += Self.rests(clef: clef, from: cursor, to: bars * bar, bar: bar)
            }
        }
        chords.sort { ($0.start, $0.clef == .treble ? 0 : 1) < ($1.start, $1.clef == .treble ? 0 : 1) }
        rests.sort { $0.start < $1.start }

        // Balkar: åttondelar och kortare i följd inom samma taktslag.
        let beamTicks = meter.denominator == 8 && meter.numerator % 3 == 0 ? 18 : 12
        var groups: [[Int]] = []
        for clef in clefs {
            var current: [Int] = []
            var previousEnd: Int?
            var currentBeat = -1
            func flush() {
                if current.count >= 2 { groups.append(current) }
                current = []
            }
            for i in chords.indices where chords[i].clef == clef {
                let c = chords[i]
                guard c.value.beams > 0 else {
                    flush()
                    previousEnd = nil
                    continue
                }
                let inBar = c.start % bar
                let beat = (c.start / bar) * 1000 + inBar / beamTicks
                if previousEnd != c.start || beat != currentBeat { flush() }
                current.append(i)
                currentBeat = beat
                previousEnd = c.end
            }
            flush()
        }
        for (g, members) in groups.enumerated() {
            let positions = members.flatMap { chords[$0].heads.map(\.position) }
            let average = Double(positions.reduce(0, +)) / Double(max(1, positions.count))
            for m in members {
                chords[m].beamGroup = g
                chords[m].stemUp = average < 4
            }
        }

        self.chords = chords
        self.rests = rests
        beamGroups = groups
        shortestTicks = chords.map(\.ticks).min() ?? 12
    }

    // MARK: - Hjälpare

    private struct BarAccidentals {
        let key: KeySignature
        var bar = 0
        private var current: [Int: Int] = [:]

        init(key: KeySignature) {
            self.key = key
        }

        mutating func startBar(_ index: Int) {
            bar = index
            current = [:]
        }

        /// Ett förtecken gäller takten ut, på just den linjen eller det mellanrummet.
        mutating func update(_ p: SpelledPitch) -> Accidental? {
            let active = current[p.step] ?? key.alter(ofLetter: p.letter)
            guard active != p.alter else { return nil }
            current[p.step] = p.alter
            switch p.alter {
            case 1: return .sharp
            case -1: return .flat
            default: return .natural
            }
        }
    }

    private static func clef(for note: Note) -> Clef {
        switch note.part {
        case .right: return note.pitch < 53 ? .bass : .treble
        case .left: return note.pitch > 67 ? .treble : .bass
        case .accompaniment: return note.pitch >= 60 ? .treble : .bass
        }
    }

    private static func meter(beatsPerBar: Int, beatQuarters: Double) -> (numerator: Int, denominator: Int) {
        let beats = max(1, beatsPerBar)
        if abs(beatQuarters - 1.5) < 0.01 { return (beats * 3, 8) }
        if abs(beatQuarters - 0.5) < 0.01 { return (beats, 8) }
        if abs(beatQuarters - 2) < 0.01 { return (beats, 2) }
        if abs(beatQuarters - 0.25) < 0.01 { return (beats, 16) }
        return (beats, 4)
    }

    /// Avrundar till sextondelar, eller till trioler när det tydligt stämmer bättre.
    private static func quantize(_ quarters: Double) -> Int {
        let whole = floor(quarters)
        let frac = quarters - whole
        let straight = (frac * 4).rounded() / 4
        let triplet = (frac * 3).rounded() / 3
        let useStraight = abs(frac - straight) <= abs(frac - triplet) + 0.04
        return Int(((whole + (useStraight ? straight : triplet)) * Double(ticksPerQuarter)).rounded())
    }

    private static func stemUp(heads: [NotationHead]) -> Bool {
        guard let low = heads.first?.position, let high = heads.last?.position else { return true }
        return low + high < 8
    }

    private struct Piece {
        var start: Int
        var ticks: Int
        var value: NoteValue
        var dotted: Bool
        var triplet: Bool
    }

    private static let table: [(ticks: Int, value: NoteValue, dotted: Bool, triplet: Bool)] = [
        (48, .whole, false, false),
        (36, .half, true, false),
        (24, .half, false, false),
        (18, .quarter, true, false),
        (12, .quarter, false, false),
        (9, .eighth, true, false),
        (8, .quarter, false, true),
        (6, .eighth, false, false),
        (4, .eighth, false, true),
        (3, .sixteenth, false, false)
    ]

    /// Delar en ton vid taktstreck och i notvärden som går att skriva.
    private static func pieces(from start: Int, to end: Int, bar: Int) -> [Piece] {
        var out: [Piece] = []
        var pos = start
        while pos < end {
            let segmentEnd = min(end, (pos / bar + 1) * bar)
            var remaining = segmentEnd - pos
            var at = pos
            while let t = table.first(where: { $0.ticks <= remaining }) {
                out.append(Piece(start: at, ticks: t.ticks, value: t.value, dotted: t.dotted, triplet: t.triplet))
                at += t.ticks
                remaining -= t.ticks
            }
            pos = segmentEnd
        }
        return out
    }

    private static func rests(clef: Clef, from start: Int, to end: Int, bar: Int) -> [NotationRest] {
        var out: [NotationRest] = []
        var pos = start
        while pos < end {
            let barStart = pos / bar * bar
            let segmentEnd = min(end, barStart + bar)
            if pos == barStart && segmentEnd == barStart + bar {
                out.append(NotationRest(clef: clef, start: pos, ticks: bar, value: .whole, triplet: false, fillsBar: true))
                pos = segmentEnd
                continue
            }
            while pos < segmentEnd {
                let offset = pos - barStart
                let remaining = segmentEnd - pos
                // Pauser skrivs på taktslagen, så att man ser var i takten man är.
                if let t = table.first(where: { !$0.dotted && $0.ticks <= remaining && offset % $0.ticks == 0 }) {
                    out.append(NotationRest(clef: clef, start: pos, ticks: t.ticks, value: t.value, triplet: t.triplet, fillsBar: false))
                    pos += t.ticks
                } else {
                    pos += 1
                }
            }
        }
        return out
    }
}
