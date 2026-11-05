import XCTest
@testable import PianoCore

final class PracticeEngineTests: XCTestCase {

    /// Kör motorn i små steg (som bildrutor) fram till `to`.
    @discardableResult
    func run(_ e: PracticeEngine, _ clock: inout Double, to: Double) -> [EngineEvent] {
        var out: [EngineEvent] = []
        while clock < to - 1e-9 {
            clock = min(to, clock + 1.0 / 60.0)
            out += e.update(now: clock)
        }
        return out
    }

    /// Höger hand C D E (en sekund var), vänster hand C3 under första tonen.
    func makeSong() throws -> Song {
        let s = try ABCParser.parse("""
        L:1/4
        Q:1/4=60
        K:C
        V:1
        V:2 clef=bass
        [V:1] [CE] D E
        [V:2] C,3
        """)
        return HandAssigner.apply(HandAssigner.automatic(for: s), to: s)
    }

    func config(_ mode: PracticeMode, hands: Set<Part> = [.right], accompaniment: Bool = true) -> PracticeConfig {
        var c = PracticeConfig()
        c.mode = mode
        c.hands = hands
        c.accompaniment = accompaniment
        c.countIn = false
        return c
    }

    func testWaitModeWaitsForCompleteChord() throws {
        let engine = PracticeEngine(song: try makeSong(), config: config(.wait))
        var clock = 0.0
        engine.start(now: clock)
        let ev = run(engine, &clock, to: 0.5)
        // Vänster hand (C3) spelas av appen.
        XCTAssertTrue(ev.contains(.noteOn(pitch: 48, velocity: 80)))
        XCTAssertTrue(engine.isWaiting)
        XCTAssertEqual(engine.time, 0)

        // Bara halva ackordet: står kvar.
        engine.keyDown(60)
        _ = run(engine, &clock, to: 1.0)
        XCTAssertTrue(engine.isWaiting)
        XCTAssertEqual(engine.time, 0)

        // Andra tonen: går vidare.
        engine.keyDown(64)
        XCTAssertEqual(engine.heldKeys[64], true)
        _ = run(engine, &clock, to: 1.5)
        XCTAssertEqual(engine.time, 0.5, accuracy: 1e-9)

        // Väntar på D vid t = 1.
        _ = run(engine, &clock, to: 3.0)
        XCTAssertEqual(engine.time, 1, accuracy: 1e-9)
        XCTAssertTrue(engine.isWaiting)

        // Fel tangent räknas men låten väntar.
        engine.keyDown(65)
        XCTAssertEqual(engine.heldKeys[65], false)
        XCTAssertEqual(engine.score.wrong, 1)
        engine.keyUp(65)

        engine.keyDown(62)
        _ = run(engine, &clock, to: 3.5)
        _ = run(engine, &clock, to: 6.0)
        engine.keyDown(64)
        var finished = false
        for i in 1...20 {
            if run(engine, &clock, to: 6.0 + Double(i) * 0.2).contains(.finished) { finished = true }
        }
        XCTAssertTrue(finished)
        XCTAssertTrue(engine.isFinished)
        XCTAssertEqual(engine.score.hits, 4)
        XCTAssertEqual(engine.score.stars, 2) // 4 av 5 = 80 %
    }

    func testWaitModeAcceptsSlightlyEarlyPress() throws {
        let engine = PracticeEngine(song: try makeSong(), config: config(.wait))
        var clock = 0.0
        engine.start(now: clock)
        engine.keyDown(60); engine.keyDown(64)
        _ = run(engine, &clock, to: 0.8)
        // D vid t=1 trycks 0,2 s för tidigt.
        engine.keyDown(62)
        XCTAssertEqual(engine.heldKeys[62], true)
        _ = run(engine, &clock, to: 1.5)
        XCTAssertGreaterThan(engine.time, 1.0)
        XCTAssertEqual(engine.score.wrong, 0)
    }

    func testBothHandsInWaitModeRequiresLeftHandToo() throws {
        let engine = PracticeEngine(song: try makeSong(), config: config(.wait, hands: [.right, .left]))
        var clock = 0.0
        engine.start(now: clock)
        let ev = run(engine, &clock, to: 0.1)
        XCTAssertFalse(ev.contains(.noteOn(pitch: 48, velocity: 80)))
        engine.keyDown(60); engine.keyDown(64)
        _ = run(engine, &clock, to: 0.5)
        XCTAssertTrue(engine.isWaiting)
        engine.keyDown(48)
        _ = run(engine, &clock, to: 1.0)
        XCTAssertFalse(engine.isWaiting)
        XCTAssertGreaterThan(engine.time, 0)
    }

    func testPlayAlongHitsAndMisses() throws {
        var c = config(.playAlong, accompaniment: false)
        c.hitWindow = 0.2
        let engine = PracticeEngine(song: try makeSong(), config: c)
        var clock = 0.0
        engine.start(now: clock)
        _ = run(engine, &clock, to: 0.05)
        engine.keyDown(60)       // träff
        engine.keyDown(64)       // träff
        XCTAssertEqual(engine.score.hits, 2)
        _ = run(engine, &clock, to: 1.1)
        engine.keyDown(62)       // träff (0,1 s sent)
        _ = run(engine, &clock, to: 2.5) // E vid 2.0 missas
        XCTAssertEqual(engine.score.misses, 1)
        engine.keyDown(70)       // fel
        XCTAssertEqual(engine.score.wrong, 1)
        XCTAssertEqual(engine.score.streak, 0)
        XCTAssertEqual(engine.score.bestStreak, 3)
    }

    func testPlayAlongSpeedScalesTime() throws {
        var c = config(.playAlong)
        c.speed = 0.5
        let engine = PracticeEngine(song: try makeSong(), config: c)
        var clock = 0.0
        engine.start(now: clock)
        _ = run(engine, &clock, to: 1.0)
        XCTAssertEqual(engine.time, 0.5, accuracy: 1e-9)
    }

    func testListenModePlaysEverything() throws {
        let engine = PracticeEngine(song: try makeSong(), config: config(.listen))
        var clock = 0.0
        engine.start(now: clock)
        var ons: [Int] = []
        var offs: [Int] = []
        for i in 0...40 {
            for e in run(engine, &clock, to: Double(i) * 0.1) {
                if case let .noteOn(p, _) = e { ons.append(p) }
                if case let .noteOff(p) = e { offs.append(p) }
            }
        }
        XCTAssertEqual(ons.sorted(), [48, 60, 62, 64, 64])
        XCTAssertEqual(offs.sorted(), [48, 60, 62, 64, 64])
        XCTAssertTrue(engine.isFinished)
    }

    func testCountInTicksBeforeStart() throws {
        var c = config(.playAlong)
        c.countIn = true
        let engine = PracticeEngine(song: try makeSong(), config: c)
        var clock = 0.0
        engine.start(now: clock)
        XCTAssertLessThan(engine.time, 0)
        var ticks: [Bool] = []
        for i in 0...40 {
            for e in run(engine, &clock, to: Double(i) * 0.1) {
                if case let .tick(accent) = e { ticks.append(accent) }
            }
            if engine.time >= 0 { break }
        }
        // 3/4? Nej: ingen M: => 4/4, alltså fyra inräkningsslag med betoning på första.
        XCTAssertEqual(ticks.count, 4)
        XCTAssertEqual(ticks.first, true)
    }

    func testLoopRepeatsSection() throws {
        var c = config(.playAlong, accompaniment: false)
        c.loop = 1.0...2.0
        let engine = PracticeEngine(song: try makeSong(), config: c)
        XCTAssertEqual(engine.time, 1.0)
        var clock = 0.0
        engine.start(now: clock)
        _ = run(engine, &clock, to: 0.9)
        XCTAssertEqual(engine.time, 1.9, accuracy: 1e-9)
        _ = run(engine, &clock, to: 1.2)
        // Har hoppat tillbaka till loopens början och fortsatt därifrån.
        XCTAssertGreaterThanOrEqual(engine.time, 1.0)
        XCTAssertLessThan(engine.time, 1.5)
        XCTAssertFalse(engine.isFinished)
    }

    func testSeekBackLetsNotesBePlayedAgainWithoutDoubleCounting() throws {
        let e = PracticeEngine(song: try makeSong(), config: config(.playAlong))
        var clock = 0.0
        e.start(now: clock)
        e.keyDown(60)
        e.keyUp(60)
        e.keyDown(64)
        e.keyUp(64)
        XCTAssertEqual(e.score.hits, 2)
        run(e, &clock, to: 1.5) // D (sekund 1) missas
        XCTAssertEqual(e.score.misses, 1)

        e.seek(to: 0)
        XCTAssertEqual(e.score.hits, 0)
        XCTAssertEqual(e.score.misses, 0)
        XCTAssertEqual(e.score.streak, 0)
        XCTAssertTrue(e.results.allSatisfy { $0 == .pending })

        e.keyDown(60)
        XCTAssertEqual(e.score.hits, 1)
    }

    func testSeekBackKeepsResultsBeforeTarget() throws {
        let e = PracticeEngine(song: try makeSong(), config: config(.wait))
        var clock = 0.0
        e.start(now: clock)
        e.keyDown(60)
        e.keyDown(64)
        run(e, &clock, to: 1.5) // väntar vid D
        e.keyDown(62)
        XCTAssertEqual(e.score.hits, 3)

        e.seek(to: 0.5) // tillbaka till före D
        XCTAssertEqual(e.score.hits, 2)
        run(e, &clock, to: 2.5)
        XCTAssertTrue(e.isWaiting)
        XCTAssertEqual(e.time, 1, accuracy: 0.001)
    }

    func testRestartResetsScore() throws {
        let engine = PracticeEngine(song: try makeSong(), config: config(.playAlong))
        var clock = 0.0
        engine.start(now: clock)
        _ = run(engine, &clock, to: 0.05)
        engine.keyDown(60)
        XCTAssertEqual(engine.score.hits, 1)
        engine.restart()
        XCTAssertEqual(engine.score.hits, 0)
        XCTAssertEqual(engine.time, 0)
        XCTAssertFalse(engine.isRunning)
    }
}

final class KeyboardRangeTests: XCTestCase {

    func testWideScreenKeepsWholeSong() {
        let (lo, hi) = KeyboardRange.fit(lowest: 45, highest: 79)
        XCTAssertLessThanOrEqual(lo, 45)
        XCTAssertGreaterThanOrEqual(hi, 79)
        XCTAssertEqual(lo % 12, 0)
        XCTAssertGreaterThanOrEqual(hi - lo, 24)
    }

    func testNarrowScreenClipsAroundFocus() {
        let (lo, hi) = KeyboardRange.fit(lowest: 36, highest: 96, focus: 72, maxWhiteKeys: 15)
        XCTAssertLessThanOrEqual(KeyboardRange.whiteKeyCount(lo, hi), 15)
        XCTAssertTrue((lo...hi).contains(72))
        XCTAssertFalse(lo.isBlackKey)
        XCTAssertFalse(hi.isBlackKey)
    }

    func testExtremeRangesNeverInvert() {
        for (a, b) in [(0, 5), (120, 127), (21, 108), (60, 60)] {
            let (lo, hi) = KeyboardRange.fit(lowest: a, highest: b, maxWhiteKeys: 10)
            XCTAssertLessThan(lo, hi)
            XCTAssertGreaterThanOrEqual(lo, 21)
            XCTAssertLessThanOrEqual(hi, 108)
        }
    }
}
