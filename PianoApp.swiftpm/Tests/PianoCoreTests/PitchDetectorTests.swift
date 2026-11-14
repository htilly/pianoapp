import XCTest
@testable import PianoCore

final class PitchDetectorTests: XCTestCase {

    let sampleRate = 44_100.0
    let size = 8192

    /// Pianoliknande ton: grundton + övertoner.
    func tone(_ pitch: Int, amplitude: Double = 0.1) -> [Double] {
        let f = 440.0 * pow(2.0, Double(pitch - 69) / 12.0)
        let partials: [Double] = [1, 0.5, 0.3, 0.2, 0.1, 0.05]
        return (0..<size).map { i in
            var s = 0.0
            for (k, a) in partials.enumerated() {
                let h = Double(k + 1)
                if f * h < sampleRate / 2 {
                    s += a * sin(2 * Double.pi * f * h * Double(i) / sampleRate + h)
                }
            }
            return amplitude * s
        }
    }

    func mix(_ pitches: [Int]) -> [Float] {
        var out = [Double](repeating: 0, count: size)
        for p in pitches {
            let t = tone(p)
            for i in 0..<size { out[i] += t[i] }
        }
        return out.map { Float($0) }
    }

    func detect(_ pitches: [Int]) -> Set<Int> {
        PitchDetector(sampleRate: sampleRate, size: size).analyze(mix(pitches)).pitches
    }

    func testSingleNotes() {
        for p in [48, 55, 60, 64, 72, 84, 90] {
            XCTAssertEqual(detect([p]), [p], "ton \(p)")
        }
    }

    func testChordsAndOctaves() {
        XCTAssertEqual(detect([60, 64, 67]), [60, 64, 67])
        XCTAssertEqual(detect([60, 72]), [60, 72])
        XCTAssertEqual(detect([53, 57, 60]), [53, 57, 60])
    }

    func testSilenceGivesNothing() {
        let d = PitchDetector(sampleRate: sampleRate, size: size)
        XCTAssertTrue(d.analyze([Float](repeating: 0, count: size)).pitches.isEmpty)
    }

    func testTrackerDebouncesAndReleases() {
        let t = NoteTracker()
        let strength: (Int) -> Float = { _ in 1 }
        // Första träffen räcker inte.
        XCTAssertTrue(t.update(active: [60], magnitude: strength).isEmpty)
        XCTAssertEqual(t.update(active: [60], magnitude: strength), [.init(pitch: 60, down: true)])
        XCTAssertTrue(t.update(active: [60], magnitude: strength).isEmpty)
        // Släpps först efter flera tysta analyser.
        XCTAssertTrue(t.update(active: [], magnitude: strength).isEmpty)
        XCTAssertTrue(t.update(active: [], magnitude: strength).isEmpty)
        XCTAssertEqual(t.update(active: [], magnitude: strength), [.init(pitch: 60, down: false)])
    }

    func testTrackerIgnoresSingleFalseHit() {
        let t = NoteTracker()
        let strength: (Int) -> Float = { _ in 1 }
        XCTAssertTrue(t.update(active: [61], magnitude: strength).isEmpty)
        XCTAssertTrue(t.update(active: [], magnitude: strength).isEmpty)
        XCTAssertTrue(t.update(active: [61], magnitude: strength).isEmpty)
        XCTAssertTrue(t.heldPitches.isEmpty)
    }
}
