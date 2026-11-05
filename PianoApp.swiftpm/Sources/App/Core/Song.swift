import Foundation

/// Vilken del av musiken en not tillhör.
public enum Part: String, Codable, CaseIterable, Hashable, Sendable {
    case right          // höger hand
    case left           // vänster hand
    case accompaniment  // spelas av appen, aldrig något att öva på
}

/// En not i en låt. Tider är i sekunder vid 100 % tempo.
public struct Note: Codable, Hashable, Sendable {
    public var pitch: Int
    public var start: Double
    public var duration: Double
    public var velocity: Int
    /// Spår (MIDI) eller stämma (ABC) som noten kommer ifrån.
    public var track: Int
    public var part: Part

    public var end: Double { start + duration }

    public init(pitch: Int, start: Double, duration: Double, velocity: Int = 80, track: Int = 0, part: Part = .right) {
        self.pitch = pitch
        self.start = start
        self.duration = duration
        self.velocity = velocity
        self.track = track
        self.part = part
    }
}

/// Information om ett spår/en stämma, används för att välja hand vid import.
public struct TrackInfo: Codable, Hashable, Identifiable, Sendable {
    public var id: Int
    public var name: String
    public var noteCount: Int
    public var averagePitch: Double
    public var lowestPitch: Int
    public var highestPitch: Int
    /// Sant om stämman uttryckligen är skriven i basklav (ABC `clef=bass`).
    public var isBassClef: Bool
}

/// Tempokarta. Positioner anges i fjärdedelsslag ("beats").
public struct TempoMap: Codable, Hashable, Sendable {
    public struct Event: Codable, Hashable, Sendable {
        public var beat: Double
        public var bpm: Double
    }

    public private(set) var events: [Event]
    private var startSeconds: [Double]

    public init(events: [Event]) {
        var sorted = events.filter { $0.bpm > 0 && $0.beat >= 0 }.sorted { $0.beat < $1.beat }
        if sorted.first?.beat != 0 {
            sorted.insert(Event(beat: 0, bpm: sorted.first?.bpm ?? 120), at: 0)
        }
        // Ta bort dubbletter på samma position (sista vinner).
        var unique: [Event] = []
        for e in sorted {
            if let last = unique.last, abs(last.beat - e.beat) < 1e-9 {
                unique[unique.count - 1] = e
            } else {
                unique.append(e)
            }
        }
        self.events = unique
        var secs: [Double] = []
        var acc = 0.0
        for (i, e) in unique.enumerated() {
            if i > 0 {
                let prev = unique[i - 1]
                acc += (e.beat - prev.beat) * 60.0 / prev.bpm
            }
            secs.append(acc)
            _ = e
        }
        self.startSeconds = secs
    }

    public init(bpm: Double) {
        self.init(events: [Event(beat: 0, bpm: bpm)])
    }

    public var initialBPM: Double { events.first?.bpm ?? 120 }

    public func seconds(atBeat beat: Double) -> Double {
        var i = events.count - 1
        while i > 0 && events[i].beat > beat { i -= 1 }
        return startSeconds[i] + (beat - events[i].beat) * 60.0 / events[i].bpm
    }

    /// Omvändningen av `seconds(atBeat:)`.
    public func beat(atSeconds seconds: Double) -> Double {
        var i = events.count - 1
        while i > 0 && startSeconds[i] > seconds { i -= 1 }
        return events[i].beat + (seconds - startSeconds[i]) * events[i].bpm / 60.0
    }
}

/// En färdigtolkad låt.
public struct Song: Codable, Hashable, Sendable {
    public var title: String
    /// Sorterade efter starttid, sedan tonhöjd.
    public var notes: [Note]
    public var tracks: [TrackInfo]
    public var tempoMap: TempoMap
    public var beatsPerBar: Int
    /// Tider (sekunder) för varje metronomslag.
    public var beatTimes: [Double]

    public init(title: String, notes: [Note], tracks: [TrackInfo], tempoMap: TempoMap, beatsPerBar: Int, beatTimes: [Double]) {
        self.title = title
        self.notes = notes.sorted { ($0.start, $0.pitch) < ($1.start, $1.pitch) }
        self.tracks = tracks
        self.tempoMap = tempoMap
        self.beatsPerBar = max(1, beatsPerBar)
        self.beatTimes = beatTimes
    }

    public var duration: Double { notes.map(\.end).max() ?? 0 }
    public var lowestPitch: Int { notes.map(\.pitch).min() ?? 60 }
    public var highestPitch: Int { notes.map(\.pitch).max() ?? 72 }

    /// Längden på ett metronomslag i början av låten (sekunder).
    public var firstBeatInterval: Double {
        if beatTimes.count >= 2 { return max(0.1, beatTimes[1] - beatTimes[0]) }
        return 60.0 / tempoMap.initialBPM
    }

    /// Taktstreck (sekunder), härledda ur metronomslagen.
    public var barTimes: [Double] {
        stride(from: 0, to: beatTimes.count, by: beatsPerBar).map { beatTimes[$0] }
    }
}

/// Gemensam byggare som MIDI- och ABC-tolkarna använder.
struct RawNote {
    var pitch: Int
    var startBeat: Double
    var durationBeats: Double
    var velocity: Int
    var track: Int
}

enum SongBuilder {
    /// - Parameters:
    ///   - beatLength: längden på ett metronomslag i fjärdedelar (t.ex. 1.5 för 6/8).
    static func build(
        title: String,
        raw: [RawNote],
        trackNames: [Int: String],
        bassClefTracks: Set<Int> = [],
        tempoMap: TempoMap,
        beatsPerBar: Int,
        beatLength: Double
    ) -> Song {
        let notes: [Note] = raw.compactMap { r in
            guard (0...127).contains(r.pitch) else { return nil }
            let start = tempoMap.seconds(atBeat: r.startBeat)
            let end = tempoMap.seconds(atBeat: r.startBeat + max(r.durationBeats, 0))
            return Note(
                pitch: r.pitch,
                start: start,
                duration: max(0.05, end - start),
                velocity: min(127, max(1, r.velocity)),
                track: r.track,
                part: .right
            )
        }

        var tracks: [TrackInfo] = []
        for id in Set(notes.map(\.track)).sorted() {
            let pitches = notes.filter { $0.track == id }.map(\.pitch)
            tracks.append(TrackInfo(
                id: id,
                name: trackNames[id] ?? "Stämma \(id + 1)",
                noteCount: pitches.count,
                averagePitch: Double(pitches.reduce(0, +)) / Double(max(1, pitches.count)),
                lowestPitch: pitches.min() ?? 60,
                highestPitch: pitches.max() ?? 60,
                isBassClef: bassClefTracks.contains(id)
            ))
        }

        let lastBeat = raw.map { $0.startBeat + $0.durationBeats }.max() ?? 0
        let len = max(0.25, beatLength)
        var beatTimes: [Double] = []
        var b = 0.0
        while b <= lastBeat + 1e-6 && beatTimes.count < 20000 {
            beatTimes.append(tempoMap.seconds(atBeat: b))
            b += len
        }

        return Song(
            title: title,
            notes: notes,
            tracks: tracks,
            tempoMap: tempoMap,
            beatsPerBar: beatsPerBar,
            beatTimes: beatTimes
        )
    }

    /// Metronomslag för en taktart: (slag per takt, slaglängd i fjärdedelar).
    static func beatGrid(numerator: Int, denominator: Int) -> (Int, Double) {
        let num = max(1, numerator)
        let den = max(1, denominator)
        if den == 8 && num % 3 == 0 && num > 3 {
            return (num / 3, 1.5) // 6/8, 9/8, 12/8 räknas i punkterade fjärdedelar
        }
        return (num, 4.0 / Double(den))
    }
}

/// Notnamn.
public enum NoteNaming: String, Codable, CaseIterable, Sendable {
    case swedish   // C D E F G A H (B = Bb)
    case english   // C D E F G A B

    public func name(for pitch: Int, withOctave: Bool = false) -> String {
        let sv = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "B", "H"]
        let en = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let pc = ((pitch % 12) + 12) % 12
        let base = self == .swedish ? sv[pc] : en[pc]
        return withOctave ? "\(base)\(pitch / 12 - 1)" : base
    }

    /// Namn för en ton så som den står i noterna, t.ex. Eb i stället för D#.
    public func name(for spelled: SpelledPitch) -> String {
        let letters = ["C", "D", "E", "F", "G", "A", "B"]
        if self == .swedish && spelled.letter == 6 {
            // Svenska: H är stamtonen och B är den sänkta tonen.
            switch spelled.alter {
            case 0: return "H"
            case -1: return "B"
            default: return "H♯"
            }
        }
        let suffix = spelled.alter > 0 ? "♯" : spelled.alter < 0 ? "♭" : ""
        return letters[spelled.letter] + suffix
    }
}

public extension Int {
    var isBlackKey: Bool { [1, 3, 6, 8, 10].contains(((self % 12) + 12) % 12) }
}

/// Väljer vilket tonomfång klaviaturen ska visa.
public enum KeyboardRange {

    /// Antal vita tangenter i ett omfång (inklusive ändarna).
    public static func whiteKeyCount(_ lo: Int, _ hi: Int) -> Int {
        guard lo <= hi else { return 0 }
        return (lo...hi).filter { !$0.isBlackKey }.count
    }

    /// Omfång som passar en låt: hela oktaver, minst två, inom 88 tangenter.
    /// Ryms det inte (`maxWhiteKeys`, t.ex. på en smal iPhone) kortas det runt `focus`.
    public static func fit(lowest: Int, highest: Int, focus: Int? = nil, maxWhiteKeys: Int = 52) -> (Int, Int) {
        var lo = lowest - 2
        var hi = highest + 2
        lo -= ((lo % 12) + 12) % 12          // ner till C
        hi += 12 - (((hi % 12) + 12) % 12)   // upp till nästa C
        while hi - lo < 24 {
            if lo > 36 { lo -= 12 } else { hi += 12 }
        }
        lo = max(21, min(lo, 84))
        hi = min(108, max(hi, lo + 24))

        let limit = max(8, maxWhiteKeys)
        let center = focus ?? (lowest + highest) / 2
        while whiteKeyCount(lo, hi) > limit {
            // Ta bort från den sida som ligger längst från fokus.
            if center - lo > hi - center { lo += 1 } else { hi -= 1 }
            while lo.isBlackKey { lo += 1 }
            while hi.isBlackKey { hi -= 1 }
        }
        return (lo, hi)
    }
}
