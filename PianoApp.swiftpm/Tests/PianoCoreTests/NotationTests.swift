import XCTest
@testable import PianoCore

final class NotationTests: XCTestCase {

    private func notation(_ body: String, meter: String = "4/4", key: String = "C") throws -> Notation {
        Notation(song: try ABCParser.parse("""
        X:1
        T:Test
        M:\(meter)
        L:1/4
        Q:1/4=60
        K:\(key)
        \(body)
        """))
    }

    // MARK: - Tonart och stavning

    func testKeyIsEstimatedFromTheNotes() {
        XCTAssertEqual(KeySignature.estimate(pitches: [60, 62, 64, 65, 67, 69, 71]).fifths, 0)
        XCTAssertEqual(KeySignature.estimate(pitches: [67, 69, 71, 72, 74, 76, 78]).fifths, 1)
        XCTAssertEqual(KeySignature.estimate(pitches: [65, 67, 69, 70, 72, 74, 76]).fifths, -1)
        XCTAssertEqual(KeySignature.estimate(pitches: []).fifths, 0)
    }

    func testSpellingFollowsTheKey() {
        let f = KeySignature(fifths: -1)
        XCTAssertEqual(f.spell(70), SpelledPitch(letter: 6, alter: -1, octave: 4)) // Bb4
        XCTAssertEqual(f.spell(71), SpelledPitch(letter: 6, alter: 0, octave: 4))  // B4
        XCTAssertEqual(f.spell(61), SpelledPitch(letter: 1, alter: -1, octave: 4)) // Db4
        let g = KeySignature(fifths: 1)
        XCTAssertEqual(g.spell(66), SpelledPitch(letter: 3, alter: 1, octave: 4))  // F#4
        XCTAssertEqual(g.spell(61), SpelledPitch(letter: 0, alter: 1, octave: 4))  // C#4
    }

    func testFlatCStaysInTheOctaveAbove() {
        let spelled = KeySignature(fifths: -7).spell(71)
        XCTAssertEqual(spelled, SpelledPitch(letter: 0, alter: -1, octave: 5))
    }

    func testSignaturePositionsInBothClefs() {
        let g = KeySignature(fifths: 1)
        XCTAssertEqual(g.signaturePositions(clef: .treble).map(\.position), [8]) // F5, översta linjen
        XCTAssertEqual(g.signaturePositions(clef: .bass).map(\.position), [6])   // F3
    }

    func testNoteNames() {
        XCTAssertEqual(NoteNaming.swedish.name(for: SpelledPitch(letter: 6, alter: 0, octave: 4)), "H")
        XCTAssertEqual(NoteNaming.swedish.name(for: SpelledPitch(letter: 6, alter: -1, octave: 4)), "B")
        XCTAssertEqual(NoteNaming.english.name(for: SpelledPitch(letter: 6, alter: 0, octave: 4)), "B")
        XCTAssertEqual(NoteNaming.english.name(for: SpelledPitch(letter: 6, alter: -1, octave: 4)), "B♭")
        XCTAssertEqual(NoteNaming.swedish.name(for: SpelledPitch(letter: 3, alter: 1, octave: 4)), "F♯")
    }

    // MARK: - Plats i systemet

    func testPositionsOnTheStaff() throws {
        let n = try notation("C E G c |]")
        XCTAssertEqual(n.clefs, [.treble])
        // Mitt-C på hjälplinjen, E på nedersta linjen.
        XCTAssertEqual(n.chords.map { $0.heads[0].position }, [-2, 0, 2, 5])
    }

    func testEachHandGetsItsOwnStaff() throws {
        var song = try ABCParser.parse("""
        X:1
        T:Test
        M:4/4
        L:1/4
        Q:1/4=60
        K:C
        C4 |]
        """)
        song.notes.append(Note(pitch: 48, start: 0, duration: 4, part: .left))
        let n = Notation(song: song)
        XCTAssertEqual(n.clefs, [.treble, .bass])
        XCTAssertEqual(n.chords.first { $0.clef == .bass }?.heads[0].position, 3) // C3 i basklav
    }

    func testPlacementOfPressedKeys() throws {
        let n = try notation("C E G c |]")
        // Bara diskantsystem: även låga tangenter visas där.
        XCTAssertEqual(n.placement(ofPitch: 48).clef, .treble)
        XCTAssertEqual(n.placement(ofPitch: 60).position, -2)
    }

    // MARK: - Rytm

    func testNoteValues() throws {
        let n = try notation("C2 D E/2 F/2 | G/4 A/4 B/2 c3/2 d/2 e |]")
        XCTAssertEqual(n.chords.map(\.value), [
            .half, .quarter, .eighth, .eighth,
            .sixteenth, .sixteenth, .eighth, .quarter, .eighth, .quarter
        ])
        XCTAssertEqual(n.chords.map(\.dotted), [
            false, false, false, false,
            false, false, false, true, false, false
        ])
    }

    func testNoteAcrossABarlineIsTied() throws {
        let n = try notation("C3 D2 E F G |]")
        let ds = n.chords.filter { $0.heads[0].pitch == 62 }
        XCTAssertEqual(ds.map(\.ticks), [12, 12])
        XCTAssertEqual(ds.map(\.tiesToNext), [true, false])
        XCTAssertEqual(ds[1].start, 48)
    }

    func testRestsFillTheGaps() throws {
        let n = try notation("C z D z | z4 | E2 z2 |]")
        XCTAssertEqual(n.rests.map(\.start), [12, 36, 48, 120])
        XCTAssertEqual(n.rests.map(\.value), [.quarter, .quarter, .whole, .half])
        XCTAssertEqual(n.rests.map(\.fillsBar), [false, false, true, false])
    }

    func testTripletsAreRecognised() throws {
        let n = try notation("(3C/2D/2E/2 F G A |]")
        XCTAssertEqual(n.chords.prefix(3).map(\.triplet), [true, true, true])
        XCTAssertEqual(n.chords.prefix(3).map(\.start), [0, 4, 8])
        XCTAssertEqual(n.beamGroups.first, [0, 1, 2])
    }

    func testPlayedLegatoSnapsToTheNextNote() {
        // Lite korta, mänskligt spelade fjärdedelar ska inte ge pauser.
        let notes = (0..<4).map { Note(pitch: 60 + $0, start: Double($0), duration: 0.85) }
        let song = Song(title: "T", notes: notes, tracks: [], tempoMap: TempoMap(bpm: 60),
                        beatsPerBar: 4, beatTimes: [0, 1, 2, 3])
        let n = Notation(song: song)
        XCTAssertEqual(n.chords.map(\.value), [.quarter, .quarter, .quarter, .quarter])
        XCTAssertTrue(n.rests.isEmpty)
    }

    func testOverlappingNotesAreCutAtTheNextNote() {
        let notes = [
            Note(pitch: 60, start: 0, duration: 4),
            Note(pitch: 64, start: 1, duration: 3)
        ]
        let song = Song(title: "T", notes: notes, tracks: [], tempoMap: TempoMap(bpm: 60),
                        beatsPerBar: 4, beatTimes: [0, 1, 2, 3])
        let n = Notation(song: song)
        XCTAssertEqual(n.chords.map(\.ticks), [12, 36])
        XCTAssertEqual(n.chords.map(\.dotted), [false, true])
    }

    func testChordSharesAStem() throws {
        let n = try notation("[CEG]4 |]")
        XCTAssertEqual(n.chords.count, 1)
        XCTAssertEqual(n.chords[0].heads.map(\.position), [-2, 0, 2])
        XCTAssertEqual(n.chords[0].value, .whole)
    }

    // MARK: - Förtecken

    func testAccidentalLastsTheBar() throws {
        let n = try notation("^F ^F =F ^F | ^F G A B |]")
        let shown = n.chords.map { $0.heads[0].accidental }
        // Tonen F# dominerar men tonarten gissas ändå: här G-dur, så F# kräver inget
        // förtecken, och F natural kräver återställning samt nytt # efteråt.
        XCTAssertEqual(n.key.fifths, 1)
        XCTAssertEqual(shown, [nil, nil, .natural, .sharp, nil, nil, nil, nil])
    }

    func testAccidentalInCMajorIsShownOncePerBar() throws {
        let n = try notation("C D E ^C | ^C D E F | G A B c |]")
        XCTAssertEqual(n.key.fifths, 0)
        let shown = n.chords.prefix(5).map { $0.heads[0].accidental }
        XCTAssertEqual(shown, [nil, nil, nil, .sharp, .sharp])
    }

    func testTiedContinuationHasNoNewAccidental() throws {
        let n = try notation("C D E ^F2 G A B | c4 | d4 | e4 |]")
        let fs = n.chords.filter { $0.heads[0].pitch == 66 }
        XCTAssertEqual(fs.count, 2)
        XCTAssertNil(fs[1].heads[0].accidental)
    }

    // MARK: - Balkar och taktart

    func testEighthsAreBeamedWithinTheBeat() throws {
        let n = try notation("C/2 D/2 E/2 F/2 G A |]")
        XCTAssertEqual(n.beamGroups, [[0, 1], [2, 3]])
    }

    func testRestBreaksABeam() throws {
        let n = try notation("C/2 z/2 D/2 E/2 F G |]")
        XCTAssertEqual(n.beamGroups.count, 1)
        XCTAssertEqual(n.beamGroups[0].map { n.chords[$0].heads[0].pitch }, [62, 64])
    }

    func testCompoundMeter() throws {
        let n = try notation("C/2 D/2 E/2 F/2 G/2 A/2 |]", meter: "6/8")
        XCTAssertEqual(n.timeSignature.numerator, 6)
        XCTAssertEqual(n.timeSignature.denominator, 8)
        XCTAssertEqual(n.barTicks, 36)
        XCTAssertEqual(n.beamGroups, [[0, 1, 2], [3, 4, 5]])
    }

    // MARK: - Tid

    func testTempoMapInverse() {
        let map = TempoMap(events: [.init(beat: 0, bpm: 60), .init(beat: 4, bpm: 120)])
        for beat in [0.0, 1.5, 4, 7.25] {
            XCTAssertEqual(map.beat(atSeconds: map.seconds(atBeat: beat)), beat, accuracy: 1e-9)
        }
        XCTAssertEqual(map.beat(atSeconds: -1), -1, accuracy: 1e-9)
    }

    // MARK: - Hela låtar

    func testEveryExampleSongIsFullyWritten() throws {
        for example in ExampleSongs.all {
            let song = try ABCParser.parse(example.abc)
            let n = Notation(song: song)
            let shown = Set(n.chords.flatMap { $0.heads.map(\.noteIndex) })
            let unique = Set(song.notes.indices.filter { i in
                !song.notes.indices.contains { j in
                    j < i && song.notes[j].pitch == song.notes[i].pitch && abs(song.notes[j].start - song.notes[i].start) < 0.02
                }
            })
            XCTAssertTrue(unique.isSubset(of: shown), example.id)
            XCTAssertTrue(n.chords.allSatisfy { $0.ticks > 0 && $0.end <= n.endTick }, example.id)

            // Varje takt i varje system är helt fylld av noter och pauser.
            for clef in n.clefs {
                let filled = n.chords.filter { $0.clef == clef }.map(\.ticks).reduce(0, +)
                    + n.rests.filter { $0.clef == clef }.map(\.ticks).reduce(0, +)
                XCTAssertEqual(filled, n.endTick, example.id)
            }
        }
    }
}
