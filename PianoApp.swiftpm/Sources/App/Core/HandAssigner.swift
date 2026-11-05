import Foundation

/// Vad ett spår/en stämma ska användas till.
public enum TrackRole: String, Codable, CaseIterable, Hashable, Sendable {
    case right          // höger hand
    case left           // vänster hand
    case split          // dela på tonhöjd: under delningspunkten = vänster
    case accompaniment  // appen spelar, inget att öva på
    case mute           // tas bort

    public var label: String {
        switch self {
        case .right: return "Höger hand"
        case .left: return "Vänster hand"
        case .split: return "Dela (båda händer)"
        case .accompaniment: return "Komp (appen spelar)"
        case .mute: return "Tyst"
        }
    }
}

public struct HandAssignment: Codable, Hashable, Sendable {
    public var roles: [Int: TrackRole]
    /// Toner under denna (MIDI-nummer) går till vänster hand vid `.split`. 60 = mitt-C.
    public var splitPitch: Int

    public init(roles: [Int: TrackRole] = [:], splitPitch: Int = 60) {
        self.roles = roles
        self.splitPitch = splitPitch
    }

    public func role(for track: Int) -> TrackRole { roles[track] ?? .split }
}

public enum HandAssigner {

    /// Gissar en rimlig handfördelning.
    public static func automatic(for song: Song) -> HandAssignment {
        let tracks = song.tracks.filter { $0.noteCount > 0 }
        var roles: [Int: TrackRole] = [:]

        guard tracks.count > 1 else {
            if let t = tracks.first { roles[t.id] = t.isBassClef ? .left : .split }
            return HandAssignment(roles: roles, splitPitch: splitPoint(for: song))
        }

        // 1. Namn som avslöjar handen.
        var unresolved: [TrackInfo] = []
        for t in tracks {
            let n = t.name.lowercased()
            if t.isBassClef || ["left", "vänster", "lh", "bass", "bas"].contains(where: { word(n, $0) }) {
                roles[t.id] = .left
            } else if ["right", "höger", "rh", "treble", "melod", "diskant"].contains(where: { word(n, $0) }) {
                roles[t.id] = .right
            } else {
                unresolved.append(t)
            }
        }
        if unresolved.isEmpty { return HandAssignment(roles: roles) }

        // 2. Två spår: det ljusaste är höger hand.
        if tracks.count == 2 {
            let sorted = tracks.sorted { $0.averagePitch > $1.averagePitch }
            for t in unresolved {
                if roles.values.contains(.right) {
                    roles[t.id] = .left
                } else if roles.values.contains(.left) {
                    roles[t.id] = .right
                } else {
                    roles[t.id] = t.id == sorted[0].id ? .right : .left
                }
            }
            return HandAssignment(roles: roles)
        }

        // 3. Många spår (t.ex. en hel orkester): spåret med flest toner över mitt-C
        //    blir höger hand, det med lägst medelton vänster, övriga komp.
        if !roles.values.contains(.right),
           let melody = unresolved.max(by: { score($0) < score($1) }) {
            roles[melody.id] = .right
            unresolved.removeAll { $0.id == melody.id }
        }
        if !roles.values.contains(.left),
           let bass = unresolved.min(by: { $0.averagePitch < $1.averagePitch }), bass.averagePitch < 60 {
            roles[bass.id] = .left
            unresolved.removeAll { $0.id == bass.id }
        }
        for t in unresolved { roles[t.id] = .accompaniment }
        return HandAssignment(roles: roles)
    }

    /// Lägger på handfördelningen; tysta spår tas bort.
    public static func apply(_ assignment: HandAssignment, to song: Song) -> Song {
        var out = song
        out.notes = song.notes.compactMap { n in
            var note = n
            switch assignment.role(for: n.track) {
            case .right: note.part = .right
            case .left: note.part = .left
            case .accompaniment: note.part = .accompaniment
            case .split: note.part = n.pitch < assignment.splitPitch ? .left : .right
            case .mute: return nil
            }
            return note
        }
        return out
    }

    /// Mitt-C om låten låter båda sidor klinga samtidigt (två händer i ett spår),
    /// annars hela låten till en hand.
    static func splitPoint(for song: Song) -> Int {
        let notes = song.notes
        guard !notes.isEmpty else { return 60 }
        var twoHanded = false
        outer: for (i, a) in notes.enumerated() {
            var j = i + 1
            while j < notes.count && notes[j].start < a.end - 0.01 {
                let b = notes[j]
                if min(a.pitch, b.pitch) < 60 && max(a.pitch, b.pitch) >= 60 && abs(a.pitch - b.pitch) >= 7 {
                    twoHanded = true
                    break outer
                }
                j += 1
            }
        }
        if twoHanded { return 60 }
        let avg = Double(notes.map(\.pitch).reduce(0, +)) / Double(notes.count)
        return avg < 55 ? 128 : 0  // 0 = allt höger, 128 = allt vänster
    }

    private static func word(_ text: String, _ w: String) -> Bool {
        if w.count <= 3 {
            let tokens = text.split(whereSeparator: { !$0.isLetter }).map(String.init)
            return tokens.contains(w)
        }
        return text.contains(w)
    }

    private static func score(_ t: TrackInfo) -> Double {
        Double(t.noteCount) * (t.averagePitch >= 60 ? 1 : 0.2) + t.averagePitch
    }
}
