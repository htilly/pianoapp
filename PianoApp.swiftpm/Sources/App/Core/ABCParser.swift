import Foundation

/// Tolkar ABC-notation (https://abcnotation.com) – den delmängd som behövs för pianolåtar:
/// huvudfält (X T M L Q K V), tonarter och lägen, förtecken, oktaver, notlängder,
/// pauser, ackord, bindebågar, punkterad rytm (> <), trioler, repriser med 1:a/2:a slut,
/// och flera stämmor (V:1, V:2 …, `clef=bass` ger vänster hand).
/// Text, ackordsymboler, ornament och förslag ignoreras.
public enum ABCParser {

    /// Delar upp en text med flera låtar (X:-fält) i separata låtar.
    public static func splitTunes(_ text: String) -> [String] {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        var tunes: [[String]] = []
        var current: [String] = []
        for line in lines {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("X:"), !current.isEmpty,
               current.contains(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("X:") || $0.hasPrefix("K:") }) {
                tunes.append(current)
                current = []
            }
            current.append(line)
        }
        if !current.isEmpty { tunes.append(current) }
        return tunes
            .map { $0.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    public static func parse(_ text: String, fallbackTitle: String = "ABC-låt") throws -> Song {
        var p = TuneParser()
        p.title = fallbackTitle
        try p.run(text)
        return try p.makeSong()
    }

    /// Ser texten ut som ABC-noter?
    public static func looksLikeABC(_ text: String) -> Bool {
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        if lines.contains(where: { $0.hasPrefix("K:") }) { return true }
        // Bara noter utan huvud, t.ex. "CDEF|GABc|"
        let music = lines.filter { !$0.isEmpty && !$0.hasPrefix("%") }
        guard !music.isEmpty else { return false }
        let allowed = Set("ABCDEFGabcdefgzZxX,'^_=/|:[]0123456789 -<>()~.\"!+{}")
        let joined = music.joined()
        let ratio = Double(joined.filter { allowed.contains($0) }.count) / Double(max(1, joined.count))
        return ratio > 0.97 && joined.contains(where: { "ABCDEFGabcdefg".contains($0) })
    }
}

// MARK: - Implementation

private enum Item {
    case notes(pitches: [Int], ties: [Bool], duration: Double)
    case rest(Double)
    case bar
    case repeatStart
    case repeatEnd
    case ending(Int)
    case tempo(Double)

    var isMusic: Bool {
        switch self {
        case .notes, .rest: return true
        default: return false
        }
    }
}

private struct Voice {
    var id: String
    var items: [Item] = []
    var bassClef = false
    var key: [Int: Int] = [:]          // bokstav (0=C…6=H) -> förtecken
    var barAccidentals: [Int: Int] = [:] // naturlig tonhöjd -> förtecken i takten
    var unitLength: Double             // i fjärdedelar
    var barLength: Double              // i fjärdedelar
    var tripletRemaining = 0
    var tripletFactor = 1.0
    var brokenNext: Double?
    var lastElement: Int?
}

private struct TuneParser {
    var title = ""
    private var hasTitle = false
    private var inHeader = true
    private var headerUnit: Double?
    private var meter: (num: Int, den: Int) = (4, 4)
    private var meterSet = false
    private var key: [Int: Int] = [:]
    private var headerBassClef = false
    private var tempoBPM: Double?
    private var pendingTempoValue: String?
    private var voices: [Voice] = []
    private var voiceIndex: [String: Int] = [:]
    private var current: Int?

    private var unitLength: Double {
        if let u = headerUnit { return u }
        let ratio = Double(meter.num) / Double(meter.den)
        return (ratio < 0.75 ? 1.0 / 16.0 : 1.0 / 8.0) * 4.0
    }
    private var barLength: Double { Double(meter.num) * 4.0 / Double(meter.den) }

    mutating func run(_ text: String) throws {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        var sawX = false
        for rawLine in lines {
            let line = stripComment(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                // En tom rad efter musiken avslutar låten.
                if !inHeader && voices.contains(where: { $0.items.contains(where: \.isMusic) }) && sawX { break }
                continue
            }
            if trimmed.hasPrefix("X:") { sawX = true }
            if let (field, value) = fieldLine(trimmed) {
                handleField(field, value)
                continue
            }
            if inHeader { finishHeader() }
            try parseMusic(trimmed)
        }
        if let q = pendingTempoValue { tempoBPM = parseTempo(q); pendingTempoValue = nil }
    }

    // MARK: Fält

    private func fieldLine(_ line: String) -> (Character, String)? {
        let chars = Array(line)
        guard chars.count >= 2, chars[1] == ":", chars[0].isLetter, chars[0].isASCII else { return nil }
        // "C:" är också ett giltigt fält (kompositör) – men "|:" osv. är inte bokstäver.
        let value = String(chars.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        return (chars[0], value)
    }

    private mutating func handleField(_ field: Character, _ value: String) {
        switch field {
        case "T":
            if !hasTitle && !value.isEmpty { title = value; hasTitle = true }
        case "M":
            if let m = parseMeter(value) {
                meter = m
                meterSet = true
                if let c = current { voices[c].barLength = barLength }
            }
        case "L":
            if let f = parseFraction(value) {
                if inHeader { headerUnit = f * 4 } else if let c = current { voices[c].unitLength = f * 4 } else { headerUnit = f * 4 }
            }
        case "Q":
            if inHeader {
                pendingTempoValue = value
            } else if let bpm = parseTempo(value, unit: current.map { voices[$0].unitLength }) {
                ensureVoice()
                if let c = current { voices[c].items.append(.tempo(bpm)) }
            }
        case "K":
            let (k, bass) = parseKey(value)
            if inHeader {
                if let k { key = k }
                if bass { headerBassClef = true }
                finishHeader()
            } else {
                ensureVoice()
                if let c = current {
                    if let k { voices[c].key = k }
                    if bass { voices[c].bassClef = true }
                }
            }
        case "V":
            let parts = value.split(separator: " ").map(String.init)
            guard let id = parts.first else { return }
            let bass = parts.dropFirst().contains { p in
                let l = p.lowercased()
                return l == "clef=bass" || l == "bass" || l == "clef=f" || l.hasPrefix("clef=bass")
            }
            let idx = voiceFor(id)
            if bass { voices[idx].bassClef = true }
            if let nm = value.range(of: "name=\"") {
                let rest = value[nm.upperBound...]
                if let endQ = rest.firstIndex(of: "\"") { voiceNames[idx] = String(rest[..<endQ]) }
            } else if let nm = value.range(of: "nm=\"") {
                let rest = value[nm.upperBound...]
                if let endQ = rest.firstIndex(of: "\"") { voiceNames[idx] = String(rest[..<endQ]) }
            }
            if !inHeader { current = idx }
        default:
            break // X, C, R, w, W, N, Z … ignoreras
        }
    }

    var voiceNames: [Int: String] = [:]

    private mutating func finishHeader() {
        guard inHeader else { return }
        inHeader = false
        if let q = pendingTempoValue { tempoBPM = parseTempo(q); pendingTempoValue = nil }
        // Stämmor som definierats i huvudet får tonart och längd nu.
        for i in voices.indices {
            voices[i].key = key
            voices[i].unitLength = unitLength
            voices[i].barLength = barLength
            if headerBassClef && voices.count == 1 { voices[i].bassClef = true }
        }
    }

    private mutating func voiceFor(_ id: String) -> Int {
        if let i = voiceIndex[id] { return i }
        let v = Voice(id: id, key: key, unitLength: unitLength, barLength: barLength)
        voices.append(v)
        voiceIndex[id] = voices.count - 1
        return voices.count - 1
    }

    private mutating func ensureVoice() {
        if current == nil {
            if voices.isEmpty {
                let i = voiceFor("1")
                if headerBassClef { voices[i].bassClef = true }
            }
            current = 0
        }
    }

    // MARK: Musik

    private mutating func parseMusic(_ line: String) throws {
        ensureVoice()
        var s = Scanner(Array(line))
        while let c = s.peek {
            guard let vi = current else { return }
            switch c {
            case " ", "\t", "`", "\\", ")", "y", "&":
                s.advance()
            case "%":
                return
            case "\"":
                s.advance(); s.skip(until: "\"")
            case "!":
                s.advance(); s.skip(until: "!")
            case "+":
                s.advance(); s.skip(until: "+")
            case "{":
                s.advance(); s.skip(until: "}")
            case "~", ".", "H", "L", "M", "O", "P", "S", "T", "u", "v", "J", "R":
                s.advance()
            case "(":
                s.advance()
                if let p = s.readInt() {
                    var q: Int? = nil
                    var r: Int? = nil
                    if s.peek == ":" {
                        s.advance()
                        q = s.readInt()
                        if s.peek == ":" { s.advance(); r = s.readInt() }
                    }
                    let defaultQ: Int
                    switch p {
                    case 2, 4, 8: defaultQ = 3
                    case 3, 6: defaultQ = 2
                    default: defaultQ = (meter.num % 3 == 0 && meter.den == 8) ? 3 : 2
                    }
                    voices[vi].tripletFactor = Double(q ?? defaultQ) / Double(max(1, p))
                    voices[vi].tripletRemaining = r ?? p
                }
            case "[":
                let next = s.peek(1)
                if let n = next, n.isNumber {
                    s.advance()
                    voices[vi].items.append(.ending(s.readInt() ?? 1))
                    s.skipEndingList()
                } else if next == "|" {
                    parseBar(&s, vi)
                } else if let n = next, n.isLetter, s.peek(2) == ":" {
                    // Inbäddat fält [K:G], [V:2], [L:1/8] …
                    s.advance()
                    var body = ""
                    while let ch = s.peek, ch != "]" { body.append(ch); s.advance() }
                    s.advance()
                    if let (f, v) = fieldLine(body.trimmingCharacters(in: .whitespaces)) { handleField(f, v) }
                } else {
                    try parseChord(&s, vi)
                }
            case "|", ":":
                parseBar(&s, vi)
            case "]":
                s.advance()
            case "z", "x":
                s.advance()
                let len = readLength(&s) * voices[vi].unitLength
                addElement(.rest(len), vi)
            case "Z", "X":
                s.advance()
                let bars = Double(s.readInt() ?? 1)
                addElement(.rest(bars * voices[vi].barLength), vi)
            case "-":
                s.advance()
            case ">", "<":
                var count = 0
                while s.peek == c { count += 1; s.advance() }
                let small = pow(0.5, Double(count))
                let (prev, next) = c == ">" ? (2 - small, small) : (small, 2 - small)
                if let li = voices[vi].lastElement {
                    voices[vi].items[li] = scaled(voices[vi].items[li], by: prev)
                }
                voices[vi].brokenNext = next
            default:
                if "^_=ABCDEFGabcdefg".contains(c) {
                    guard let n = try parseNote(&s, vi) else { s.advance(); continue }
                    let len = readLength(&s) * voices[vi].unitLength * n.lengthFactor
                    var tie = false
                    if s.peek == "-" { tie = true; s.advance() }
                    addElement(.notes(pitches: [n.pitch], ties: [tie], duration: len), vi)
                } else {
                    s.advance() // okänt tecken – hoppa över
                }
            }
        }
    }

    private struct ParsedNote { var pitch: Int; var lengthFactor: Double }

    private mutating func parseNote(_ s: inout Scanner, _ vi: Int) throws -> ParsedNote? {
        var accidental: Int? = nil
        while let c = s.peek, "^_=".contains(c) {
            s.advance()
            switch c {
            case "^": accidental = (accidental ?? 0) + 1
            case "_": accidental = (accidental ?? 0) - 1
            default: accidental = 0
            }
        }
        guard let letter = s.peek, "ABCDEFGabcdefg".contains(letter) else { return nil }
        s.advance()
        let upper = Character(letter.uppercased())
        let letterIndex = ["C": 0, "D": 1, "E": 2, "F": 3, "G": 4, "A": 5, "B": 6][String(upper)]!
        let semis = [0, 2, 4, 5, 7, 9, 11][letterIndex]
        var natural = 60 + semis + (letter.isLowercase ? 12 : 0)
        while let c = s.peek, c == "," || c == "'" {
            natural += c == "," ? -12 : 12
            s.advance()
        }
        let alt: Int
        if let a = accidental {
            voices[vi].barAccidentals[natural] = a
            alt = a
        } else {
            alt = voices[vi].barAccidentals[natural] ?? voices[vi].key[letterIndex] ?? 0
        }
        return ParsedNote(pitch: natural + alt, lengthFactor: 1)
    }

    private mutating func parseChord(_ s: inout Scanner, _ vi: Int) throws {
        s.advance() // [
        var pitches: [Int] = []
        var ties: [Bool] = []
        var firstLen: Double?
        while let c = s.peek, c != "]" {
            if "^_=ABCDEFGabcdefg".contains(c) {
                guard let n = try parseNote(&s, vi) else { s.advance(); continue }
                let len = readLength(&s)
                if firstLen == nil { firstLen = len }
                var tie = false
                if s.peek == "-" { tie = true; s.advance() }
                pitches.append(n.pitch)
                ties.append(tie)
            } else if c == "\"" {
                s.advance(); s.skip(until: "\"")
            } else if c == "!" {
                s.advance(); s.skip(until: "!")
            } else {
                s.advance()
            }
        }
        s.advance() // ]
        let mult = readLength(&s)
        if s.peek == "-" { ties = ties.map { _ in true }; s.advance() }
        guard !pitches.isEmpty else { return }
        let dur = (firstLen ?? 1) * mult * voices[vi].unitLength
        addElement(.notes(pitches: pitches, ties: ties, duration: dur), vi)
    }

    private mutating func parseBar(_ s: inout Scanner, _ vi: Int) {
        var run = ""
        if s.peek == "[" { run.append("["); s.advance() }
        while let c = s.peek {
            if c == "|" || c == ":" {
                run.append(c); s.advance()
            } else if c == "]" && run.contains("|") {
                run.append(c); s.advance()
            } else {
                break
            }
        }
        let chars = Array(run.filter { $0 == "|" || $0 == ":" })
        let firstBar = chars.firstIndex(of: "|")
        let lastBar = chars.lastIndex(of: "|")
        var repeatEnd = false
        var repeatStart = false
        if let f = firstBar, let l = lastBar {
            repeatEnd = chars[..<f].contains(":")
            repeatStart = chars[(l + 1)...].contains(":")
        } else if chars.count >= 2 {
            repeatEnd = true
            repeatStart = true // "::"
        }

        voices[vi].items.append(.bar)
        voices[vi].barAccidentals = [:]
        if repeatEnd { voices[vi].items.append(.repeatEnd) }
        if repeatStart { voices[vi].items.append(.repeatStart) }
        if let c = s.peek, c.isNumber {
            voices[vi].items.append(.ending(s.readInt() ?? 1))
            s.skipEndingList()
        }
    }

    private func readLength(_ s: inout Scanner) -> Double {
        let num = Double(s.readInt() ?? 1)
        var den = 1.0
        while s.peek == "/" {
            s.advance()
            if let d = s.readInt() { den *= Double(max(1, d)) } else { den *= 2 }
        }
        return num / den
    }

    private mutating func addElement(_ item: Item, _ vi: Int) {
        var it = item
        if let b = voices[vi].brokenNext {
            it = scaled(it, by: b)
            voices[vi].brokenNext = nil
        }
        if voices[vi].tripletRemaining > 0 {
            it = scaled(it, by: voices[vi].tripletFactor)
            voices[vi].tripletRemaining -= 1
        }
        voices[vi].items.append(it)
        voices[vi].lastElement = voices[vi].items.count - 1
    }

    private func scaled(_ item: Item, by f: Double) -> Item {
        switch item {
        case let .notes(p, t, d): return .notes(pitches: p, ties: t, duration: d * f)
        case let .rest(d): return .rest(d * f)
        default: return item
        }
    }

    // MARK: Värden

    private func stripComment(_ line: String) -> String {
        if line.hasPrefix("%") { return "" }
        var out = ""
        var prev: Character = " "
        for c in line {
            if c == "%" && prev != "\\" { break }
            out.append(c)
            prev = c
        }
        return out
    }

    private func parseFraction(_ v: String) -> Double? {
        let parts = v.trimmingCharacters(in: .whitespaces).split(separator: "/")
        guard let n = Double(parts.first ?? "") else { return nil }
        if parts.count > 1, let d = Double(parts[1]), d > 0 { return n / d }
        return n
    }

    private func parseMeter(_ v: String) -> (Int, Int)? {
        let t = v.trimmingCharacters(in: .whitespaces)
        if t == "C" { return (4, 4) }
        if t == "C|" { return (2, 2) }
        let parts = t.split(separator: "/")
        guard parts.count == 2 else { return nil }
        let num = parts[0].split(separator: "+").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }.reduce(0, +)
        guard num > 0, let den = Int(parts[1].trimmingCharacters(in: .whitespaces)), den > 0 else { return nil }
        return (num, den)
    }

    private func parseTempo(_ v: String, unit: Double? = nil) -> Double? {
        // Ta bort citerad text, t.ex. Q:"Allegro" 1/4=120
        var cleaned = ""
        var inQuote = false
        for c in v {
            if c == "\"" { inQuote.toggle(); continue }
            if !inQuote { cleaned.append(c) }
        }
        if let eq = cleaned.firstIndex(of: "=") {
            let left = cleaned[..<eq].split(separator: " ").compactMap { parseFraction(String($0)) }.reduce(0, +)
            guard let n = Double(cleaned[cleaned.index(after: eq)...].trimmingCharacters(in: .whitespaces)
                .prefix { $0.isNumber || $0 == "." }) else { return nil }
            let beatLen = left > 0 ? left * 4 : 1
            return n * beatLen
        }
        guard let n = Double(cleaned.trimmingCharacters(in: .whitespaces).prefix { $0.isNumber || $0 == "." }) else { return nil }
        return n * (unit ?? unitLength)
    }

    /// Returnerar (förtecken per bokstav, basklav?).
    private func parseKey(_ v: String) -> ([Int: Int]?, Bool) {
        let tokens = v.split(separator: " ").map(String.init)
        let bass = tokens.contains { let l = $0.lowercased(); return l == "clef=bass" || l == "bass" || l == "clef=f" }
        guard var first = tokens.first, !first.lowercased().hasPrefix("clef") else { return (nil, bass) }
        if first.lowercased() == "none" || first == "Hp" || first == "HP" { return ([:], bass) }
        guard let letter = first.first, "ABCDEFG".contains(letter) else { return (nil, bass) }
        first.removeFirst()
        var fifths = ["F": -1, "C": 0, "G": 1, "D": 2, "A": 3, "E": 4, "B": 5][String(letter)]!
        if first.hasPrefix("#") { fifths += 7; first.removeFirst() } else if first.hasPrefix("b") { fifths -= 7; first.removeFirst() }
        var mode = first.lowercased()
        if mode.isEmpty, tokens.count > 1, !tokens[1].contains("=") { mode = tokens[1].lowercased() }
        let m3 = String(mode.prefix(3))
        switch m3 {
        case "", "maj", "ion": break
        case "m", "min", "aeo": fifths -= 3
        case "mix": fifths -= 1
        case "dor": fifths -= 2
        case "phr": fifths -= 4
        case "lyd": fifths += 1
        case "loc": fifths -= 5
        default: if mode.hasPrefix("m") { fifths -= 3 }
        }
        var map: [Int: Int] = [:]
        let sharpOrder = [3, 0, 4, 1, 5, 2, 6] // F C G D A E H
        let flatOrder = [6, 2, 5, 1, 4, 0, 3]  // H E A D G C F
        if fifths > 0 {
            for i in 0..<min(7, fifths) { map[sharpOrder[i]] = 1 }
        } else if fifths < 0 {
            for i in 0..<min(7, -fifths) { map[flatOrder[i]] = -1 }
        }
        return (map, bass)
    }

    // MARK: Utdata

    func makeSong() throws -> Song {
        var raw: [RawNote] = []
        var tempoEvents: [TempoMap.Event] = [.init(beat: 0, bpm: tempoBPM ?? 100)]
        var names: [Int: String] = [:]
        var bass: Set<Int> = []
        var trackNo = 0

        for (vi, voice) in voices.enumerated() {
            let expanded = Self.expandRepeats(voice.items)
            guard expanded.contains(where: \.isMusic) else { continue }
            var pos = 0.0
            var openTies: [Int: Int] = [:] // tonhöjd -> index i raw
            var hasNotes = false
            for item in expanded {
                switch item {
                case let .notes(pitches, ties, dur):
                    var stillOpen: [Int: Int] = [:]
                    for (i, p) in pitches.enumerated() {
                        let tie = i < ties.count ? ties[i] : false
                        if let idx = openTies[p] {
                            raw[idx].durationBeats += dur
                            if tie { stillOpen[p] = idx }
                        } else {
                            raw.append(RawNote(pitch: p, startBeat: pos, durationBeats: dur, velocity: 80, track: trackNo))
                            hasNotes = true
                            if tie { stillOpen[p] = raw.count - 1 }
                        }
                    }
                    openTies = stillOpen
                    pos += dur
                case let .rest(d):
                    openTies = [:]
                    pos += d
                case let .tempo(bpm):
                    tempoEvents.append(.init(beat: pos, bpm: bpm))
                default:
                    break
                }
            }
            if hasNotes {
                names[trackNo] = voiceNames[vi] ?? (voices.count > 1 ? "Stämma \(voice.id)" : "Melodi")
                if voice.bassClef { bass.insert(trackNo) }
                trackNo += 1
            }
        }

        guard !raw.isEmpty else { throw SongImportError.noNotes }
        let (bpb, beatLen) = SongBuilder.beatGrid(numerator: meter.num, denominator: meter.den)
        return SongBuilder.build(
            title: title,
            raw: raw,
            trackNames: names,
            bassClefTracks: bass,
            tempoMap: TempoMap(events: tempoEvents),
            beatsPerBar: bpb,
            beatLength: beatLen
        )
    }

    /// Spelar ut repriser: |: … :| och 1:a/2:a slut.
    private static func expandRepeats(_ items: [Item]) -> [Item] {
        var out: [Item] = []
        var pos = 0
        var startIdx = 0
        var secondPass = false
        var handled = Set<Int>()
        var guardCounter = 0
        while pos < items.count && guardCounter < 100_000 {
            guardCounter += 1
            switch items[pos] {
            case .repeatStart:
                startIdx = pos + 1
                secondPass = false
            case .repeatEnd:
                if !handled.contains(pos) {
                    handled.insert(pos)
                    secondPass = true
                    pos = startIdx
                    continue
                } else {
                    secondPass = false
                    startIdx = pos + 1
                }
            case .ending(let n):
                if secondPass && n == 1 {
                    // Hoppa över 1:a slut till och med dess reprisslut.
                    var j = pos + 1
                    while j < items.count {
                        if case .repeatEnd = items[j] { break }
                        j += 1
                    }
                    handled.insert(j)
                    secondPass = false
                    startIdx = j + 1
                    pos = j + 1
                    continue
                }
            default:
                out.append(items[pos])
            }
            pos += 1
        }
        return out
    }
}

private struct Scanner {
    let chars: [Character]
    var i = 0
    init(_ chars: [Character]) { self.chars = chars }

    var peek: Character? { i < chars.count ? chars[i] : nil }
    func peek(_ offset: Int) -> Character? { i + offset < chars.count ? chars[i + offset] : nil }
    mutating func advance() { i += 1 }

    mutating func skip(until c: Character) {
        while let ch = peek {
            advance()
            if ch == c { return }
        }
    }

    mutating func readInt() -> Int? {
        var s = ""
        while let c = peek, c.isASCII, c.isNumber { s.append(c); advance() }
        return Int(s)
    }

    /// Hoppar över ",3" eller "-3" i t.ex. [1,3
    mutating func skipEndingList() {
        while let c = peek, c == "," || c == "-" || (c.isASCII && c.isNumber) { advance() }
    }
}
