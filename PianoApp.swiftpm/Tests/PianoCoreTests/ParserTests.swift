import XCTest
@testable import PianoCore

final class ABCParserTests: XCTestCase {

    func testSimpleMelodyPitchesAndTiming() throws {
        let song = try ABCParser.parse("""
        X:1
        T:Test
        M:4/4
        L:1/4
        Q:1/4=60
        K:C
        C D E F | G2 c2 |]
        """)
        XCTAssertEqual(song.title, "Test")
        XCTAssertEqual(song.notes.map(\.pitch), [60, 62, 64, 65, 67, 72])
        XCTAssertEqual(song.notes.map(\.start), [0, 1, 2, 3, 4, 6])
        XCTAssertEqual(song.notes[4].duration, 2, accuracy: 1e-9)
        XCTAssertEqual(song.beatsPerBar, 4)
    }

    func testKeySignatureAndBarAccidentals() throws {
        // G-dur: F blir F#. =F tar bort förtecknet resten av takten.
        let song = try ABCParser.parse("""
        L:1/4
        K:G
        F =F F | F ^c c | c
        """)
        XCTAssertEqual(song.notes.map(\.pitch), [66, 65, 65, 66, 73, 73, 72])
    }

    func testFlatKeysAndModes() throws {
        let bb = try ABCParser.parse("L:1/4\nK:Bb\nB E A")
        XCTAssertEqual(bb.notes.map(\.pitch), [70, 63, 69])
        let dm = try ABCParser.parse("L:1/4\nK:Dm\nB")
        XCTAssertEqual(dm.notes.map(\.pitch), [70])
        let ddor = try ABCParser.parse("L:1/4\nK:D dor\nF c B")
        XCTAssertEqual(ddor.notes.map(\.pitch), [65, 72, 71])
    }

    func testOctavesAndLengths() throws {
        let song = try ABCParser.parse("""
        M:4/4
        L:1/8
        Q:1/4=60
        K:C
        C, c' C3/2 C/ C// C2
        """)
        XCTAssertEqual(song.notes.map(\.pitch), [48, 84, 60, 60, 60, 60])
        // Åttondel = 0,5 s vid 60 bpm.
        XCTAssertEqual(song.notes.map(\.duration), [0.5, 0.5, 0.75, 0.25, 0.125, 1.0])
    }

    func testChordsTiesAndRests() throws {
        let song = try ABCParser.parse("""
        L:1/4
        Q:1/4=60
        K:C
        [CEG]2 z C- | C D
        """)
        let chord = song.notes.filter { $0.start == 0 }
        XCTAssertEqual(chord.map(\.pitch), [60, 64, 67])
        XCTAssertTrue(chord.allSatisfy { $0.duration == 2 })
        // C- | C blir en lång ton från slag 3.
        let tied = song.notes.first { $0.start == 3 }
        XCTAssertEqual(tied?.duration ?? 0, 2, accuracy: 1e-9)
        XCTAssertEqual(song.notes.last?.pitch, 62)
        XCTAssertEqual(song.notes.last?.start ?? 0, 5, accuracy: 1e-9)
    }

    func testBrokenRhythmAndTriplets() throws {
        let song = try ABCParser.parse("""
        L:1/8
        Q:1/4=60
        K:C
        C>D (3EFG A
        """)
        let d = song.notes.map(\.duration)
        XCTAssertEqual(d[0], 0.75, accuracy: 1e-9)
        XCTAssertEqual(d[1], 0.25, accuracy: 1e-9)
        XCTAssertEqual(d[2], 1.0 / 3.0, accuracy: 1e-9)
        XCTAssertEqual(d[4], 1.0 / 3.0, accuracy: 1e-9)
        XCTAssertEqual(song.notes[5].start, 2, accuracy: 1e-9)
    }

    func testRepeatsWithEndings() throws {
        let song = try ABCParser.parse("""
        L:1/4
        K:C
        |: C D |1 E :|2 F |] G
        """)
        XCTAssertEqual(song.notes.map(\.pitch), [60, 62, 64, 60, 62, 65, 67])
    }

    func testSimpleRepeat() throws {
        let song = try ABCParser.parse("L:1/4\nK:C\nC |: D E :| F")
        XCTAssertEqual(song.notes.map(\.pitch), [60, 62, 64, 62, 64, 65])
    }

    func testTwoVoicesAndBassClef() throws {
        let song = try ABCParser.parse("""
        X:1
        T:Två händer
        L:1/4
        K:C
        V:1
        V:2 clef=bass
        [V:1] E F G
        [V:2] C,3
        """)
        XCTAssertEqual(song.tracks.count, 2)
        XCTAssertTrue(song.tracks[1].isBassClef)
        let assigned = HandAssigner.apply(HandAssigner.automatic(for: song), to: song)
        XCTAssertEqual(assigned.notes.filter { $0.part == .left }.map(\.pitch), [48])
        XCTAssertEqual(assigned.notes.filter { $0.part == .right }.map(\.pitch), [64, 65, 67])
    }

    func testIgnoresDecorationsChordSymbolsAndGraceNotes() throws {
        let song = try ABCParser.parse("""
        L:1/4
        K:C
        "C"!p!C {g}D .E ~F | "Am"A % kommentar
        w: text text
        """)
        XCTAssertEqual(song.notes.map(\.pitch), [60, 62, 64, 65, 69])
    }

    func testTempoAndMeterDefaults() throws {
        let song = try ABCParser.parse("""
        M:6/8
        Q:3/8=60
        K:C
        CDE FGA
        """)
        // L blir 1/8, punkterad fjärdedel = 60 => åttondel = 1/3 s.
        XCTAssertEqual(song.notes[1].start, 1.0 / 3.0, accuracy: 1e-9)
        XCTAssertEqual(song.beatsPerBar, 2)
    }

    func testSplitTunes() {
        let tunes = ABCParser.splitTunes("""
        X:1
        T:A
        K:C
        CDE

        X:2
        T:B
        K:C
        EDC
        """)
        XCTAssertEqual(tunes.count, 2)
    }

    func testAllExampleSongsParse() throws {
        for ex in ExampleSongs.all {
            let song = try ABCParser.parse(ex.abc)
            XCTAssertFalse(song.notes.isEmpty, ex.id)
            XCTAssertGreaterThan(song.duration, 3, ex.id)
        }
        let elise = try ABCParser.parse(ExampleSongs.all.first { $0.id == "example.elise" }!.abc)
        XCTAssertEqual(Array(elise.notes.filter { $0.track == 0 }.prefix(9).map(\.pitch)), [76, 75, 76, 75, 76, 71, 74, 72, 69])
        XCTAssertEqual(elise.tracks.count, 2)
        let twinkle = try ABCParser.parse(ExampleSongs.all.first { $0.id == "example.twinkle" }!.abc)
        let rh = twinkle.notes.filter { $0.track == 0 }.map(\.pitch)
        XCTAssertEqual(Array(rh.prefix(7)), [60, 60, 67, 67, 69, 69, 67])
    }
}

final class MIDIParserTests: XCTestCase {

    /// Bygger en liten MIDI-fil (typ 1): dirigentspår + två notspår.
    static func makeMIDI(runningStatus: Bool = true) -> Data {
        func vlq(_ v: Int) -> [UInt8] {
            var v = v
            var out = [UInt8(v & 0x7F)]
            v >>= 7
            while v > 0 { out.insert(UInt8(v & 0x7F) | 0x80, at: 0); v >>= 7 }
            return out
        }
        func chunk(_ id: String, _ body: [UInt8]) -> [UInt8] {
            let n = body.count
            return Array(id.utf8) + [UInt8(n >> 24 & 0xFF), UInt8(n >> 16 & 0xFF), UInt8(n >> 8 & 0xFF), UInt8(n & 0xFF)] + body
        }
        let ppq = 480
        // Spår 0: namn, tempo 60 bpm (1 000 000 µs), 3/4-takt.
        var t0: [UInt8] = [0x00, 0xFF, 0x03, UInt8(Array("Test".utf8).count)] + Array("Test".utf8)
        t0 += [0x00, 0xFF, 0x51, 0x03, 0x0F, 0x42, 0x40]
        t0 += [0x00, 0xFF, 0x58, 0x04, 0x03, 0x02, 0x18, 0x08]
        // Efter ett slag: 120 bpm.
        t0 += vlq(ppq) + [0xFF, 0x51, 0x03, 0x07, 0xA1, 0x20]
        t0 += [0x00, 0xFF, 0x2F, 0x00]

        // Spår 1: höger hand, C5 E5 (med running status och note-on vel 0 som note-off).
        var t1: [UInt8] = [0x00, 0xFF, 0x03, 0x05] + Array("Right".utf8)
        t1 += [0x00, 0x90, 72, 100]
        if runningStatus {
            t1 += vlq(ppq) + [72, 0]          // running status, vel 0
            t1 += [0x00, 76, 90]
            t1 += vlq(ppq) + [76, 0]
        } else {
            t1 += vlq(ppq) + [0x80, 72, 0]
            t1 += [0x00, 0x90, 76, 90]
            t1 += vlq(ppq) + [0x80, 76, 0]
        }
        t1 += [0x00, 0xFF, 0x2F, 0x00]

        // Spår 2: vänster hand C3 i två slag, plus en trumton på kanal 10.
        var t2: [UInt8] = [0x00, 0xFF, 0x03, 0x04] + Array("Left".utf8)
        t2 += [0x00, 0x91, 48, 80]
        t2 += [0x00, 0x99, 36, 100]
        t2 += vlq(ppq) + [0x89, 36, 0]
        t2 += vlq(ppq) + [0x81, 48, 0]
        t2 += [0x00, 0xFF, 0x2F, 0x00]

        let header = chunk("MThd", [0x00, 0x01, 0x00, 0x03, UInt8(ppq >> 8), UInt8(ppq & 0xFF)])
        return Data(header + chunk("MTrk", t0) + chunk("MTrk", t1) + chunk("MTrk", t2))
    }

    func testParsesTracksTempoAndNotes() throws {
        let song = try MIDIFileParser.parse(Self.makeMIDI())
        XCTAssertEqual(song.title, "Test")
        XCTAssertEqual(song.beatsPerBar, 3)
        XCTAssertEqual(song.tracks.map(\.name), ["Right", "Left"])
        XCTAssertEqual(song.notes.count, 3) // trumman ignoreras

        let c5 = song.notes.first { $0.pitch == 72 }!
        XCTAssertEqual(c5.start, 0, accuracy: 1e-9)
        XCTAssertEqual(c5.duration, 1.0, accuracy: 1e-9)   // 60 bpm
        let e5 = song.notes.first { $0.pitch == 76 }!
        XCTAssertEqual(e5.start, 1.0, accuracy: 1e-9)
        XCTAssertEqual(e5.duration, 0.5, accuracy: 1e-9)   // 120 bpm
        XCTAssertEqual(e5.velocity, 90)
        let c3 = song.notes.first { $0.pitch == 48 }!
        XCTAssertEqual(c3.duration, 1.5, accuracy: 1e-9)
    }

    func testWithoutRunningStatusGivesSameResult() throws {
        let a = try MIDIFileParser.parse(Self.makeMIDI(runningStatus: true))
        let b = try MIDIFileParser.parse(Self.makeMIDI(runningStatus: false))
        XCTAssertEqual(a.notes, b.notes)
    }

    func testAutomaticHandsFromTrackNames() throws {
        let song = try MIDIFileParser.parse(Self.makeMIDI())
        let a = HandAssigner.automatic(for: song)
        let applied = HandAssigner.apply(a, to: song)
        XCTAssertEqual(applied.notes.first { $0.pitch == 72 }?.part, .right)
        XCTAssertEqual(applied.notes.first { $0.pitch == 48 }?.part, .left)
    }

    func testRejectsGarbage() {
        XCTAssertThrowsError(try MIDIFileParser.parse(Data("hej".utf8)))
        var truncated = Self.makeMIDI()
        truncated.removeLast(10)
        XCTAssertThrowsError(try MIDIFileParser.parse(truncated))
    }

    func testImporterDetectsBase64AndHexMIDI() throws {
        let data = Self.makeMIDI()
        let b64 = data.base64EncodedString()
        let wrapped = stride(from: 0, to: b64.count, by: 40).map { i -> String in
            let s = b64.index(b64.startIndex, offsetBy: i)
            let e = b64.index(s, offsetBy: min(40, b64.count - i))
            return String(b64[s..<e])
        }.joined(separator: "\n")
        let fromB64 = try SongImporter.importText(wrapped)
        XCTAssertEqual(fromB64.first?.format, .midi)
        XCTAssertEqual(fromB64.first?.song.notes.count, 3)

        let hex = data.map { String(format: "%02X", $0) }.joined(separator: " ")
        let fromHex = try SongImporter.importText(hex)
        XCTAssertEqual(fromHex.first?.song.notes.count, 3)

        // Sparad källa går att läsa igen.
        let again = try SongImporter.parse(format: .midi, source: fromB64[0].source, title: "x")
        XCTAssertEqual(again.notes, fromB64[0].song.notes)
    }

    func testImporterDetectsABC() throws {
        let r = try SongImporter.importText("X:1\nT:Hej\nK:C\nCDEF|")
        XCTAssertEqual(r.first?.format, .abc)
        XCTAssertEqual(r.first?.song.title, "Hej")
        let bare = try SongImporter.importText("CDEF|GABc|")
        XCTAssertEqual(bare.first?.song.notes.count, 8)
        XCTAssertThrowsError(try SongImporter.importText("Hej på dig, det här är ingen musik!"))
    }
}

final class HandAssignerTests: XCTestCase {

    func testSingleMelodyGoesToRightHand() throws {
        let song = try ABCParser.parse("L:1/4\nK:C\nG, C D E")
        let applied = HandAssigner.apply(HandAssigner.automatic(for: song), to: song)
        XCTAssertTrue(applied.notes.allSatisfy { $0.part == .right })
    }

    func testSingleTrackWithBothHandsIsSplit() throws {
        let song = try ABCParser.parse("L:1/4\nK:C\n[C,E] [G,c] D")
        let applied = HandAssigner.apply(HandAssigner.automatic(for: song), to: song)
        XCTAssertEqual(applied.notes.filter { $0.part == .left }.map(\.pitch).sorted(), [48, 55])
    }

    func testMuteRemovesNotes() throws {
        let song = try ABCParser.parse("L:1/4\nK:C\nC D E")
        let applied = HandAssigner.apply(HandAssignment(roles: [0: .mute]), to: song)
        XCTAssertTrue(applied.notes.isEmpty)
    }
}
