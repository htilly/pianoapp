import Foundation
#if canImport(Accelerate)
import Accelerate
#endif

/// Lyssnar efter pianotoner i ljud (mikrofon) – utan MIDI.
///
/// Metod: ett Hann-fönster på `size` ljudprov analyseras med en enkel DFT exakt på
/// de frekvenser som pianots toner (C3–C7) har. Toner som är lokala toppar i spektrumet
/// räknas som spelade. Toner som bara är övertoner av en lägre ton som redan hittats
/// (oktav, kvint+oktav …) filtreras bort. Ren Swift utan Apple-ramverk (förutom
/// Accelerate som snabbar upp, om det finns) så att logiken kan testas på Linux.
public final class PitchDetector {

    public static let lowestPitch = 48    // C3
    public static let highestPitch = 96   // C7

    public let sampleRate: Double
    public let size: Int

    /// Tonerna vi mäter: lowest-1 ... highest+1 (grannarna behövs för toppdetektering).
    private let firstMeasured = PitchDetector.lowestPitch - 1
    private let lastMeasured = PitchDetector.highestPitch + 1
    private var cosTable: [Float] = []
    private var sinTable: [Float] = []

    /// En ton måste vara minst så här stark jämfört med den starkaste.
    private let relativeThreshold: Float = 0.2
    /// Absolut golv (relativt fönsterstorleken) så att brus inte ger toner.
    private let absoluteFloor: Float
    /// Under den här ljudnivån (RMS) lyssnar vi inte alls.
    private let silenceRMS: Float = 0.003

    /// (halvtonssteg ner, högsta tillåtna styrka relativt den lägre tonen för att räknas som överton)
    private let harmonicRules: [(Int, Float)] = [(12, 0.85), (19, 0.7), (24, 0.6), (28, 0.5)]

    public init(sampleRate: Double, size: Int = 8192) {
        self.sampleRate = sampleRate
        self.size = size
        self.absoluteFloor = Float(size) * 0.0005
        buildTables()
    }

    private var measuredCount: Int { lastMeasured - firstMeasured + 1 }

    private func buildTables() {
        let n = size
        cosTable = [Float](repeating: 0, count: measuredCount * n)
        sinTable = [Float](repeating: 0, count: measuredCount * n)
        let window: [Double] = (0..<n).map { 0.5 - 0.5 * cos(2.0 * Double.pi * Double($0) / Double(n)) }
        for k in 0..<measuredCount {
            let pitch = firstMeasured + k
            let freq = 440.0 * pow(2.0, Double(pitch - 69) / 12.0)
            let w = 2.0 * Double.pi * freq / sampleRate
            let base = k * n
            for i in 0..<n {
                let phase = w * Double(i)
                cosTable[base + i] = Float(cos(phase) * window[i])
                sinTable[base + i] = Float(sin(phase) * window[i])
            }
        }
    }

    /// Styrkan (magnitud) för varje mätt ton; index 0 = lowestPitch-1.
    public func magnitudes(of samples: [Float]) -> [Float] {
        precondition(samples.count >= size, "Fönstret är för kort")
        var out = [Float](repeating: 0, count: measuredCount)
        let n = size
        samples.withUnsafeBufferPointer { x in
            cosTable.withUnsafeBufferPointer { ct in
                sinTable.withUnsafeBufferPointer { st in
                    // Använd de sista `size` proven om fler getts.
                    let xs = x.baseAddress! + (x.count - n)
                    for k in 0..<measuredCount {
                        let c = ct.baseAddress! + k * n
                        let s = st.baseAddress! + k * n
                        var re: Float = 0
                        var im: Float = 0
                        #if canImport(Accelerate)
                        vDSP_dotpr(xs, 1, c, 1, &re, vDSP_Length(n))
                        vDSP_dotpr(xs, 1, s, 1, &im, vDSP_Length(n))
                        #else
                        for i in 0..<n {
                            re += xs[i] * c[i]
                            im += xs[i] * s[i]
                        }
                        #endif
                        out[k] = (re * re + im * im).squareRoot()
                    }
                }
            }
        }
        return out
    }

    /// Ljudnivå (RMS) för de sista `size` proven.
    public func level(of samples: [Float]) -> Float {
        let n = min(size, samples.count)
        guard n > 0 else { return 0 }
        var sum: Float = 0
        for i in (samples.count - n)..<samples.count { sum += samples[i] * samples[i] }
        return (sum / Float(n)).squareRoot()
    }

    /// Vilka toner låter just nu? Returnerar även styrkorna (för omslag/återslag).
    public func analyze(_ samples: [Float]) -> (pitches: Set<Int>, magnitudes: [Float], level: Float) {
        let lvl = level(of: samples)
        let mags = magnitudes(of: samples)
        guard lvl >= silenceRMS else { return ([], mags, lvl) }
        return (activePitches(from: mags), mags, lvl)
    }

    func mag(_ mags: [Float], _ pitch: Int) -> Float { mags[pitch - firstMeasured] }

    func activePitches(from mags: [Float]) -> Set<Int> {
        let lo = PitchDetector.lowestPitch
        let hi = PitchDetector.highestPitch
        var strongest: Float = 0
        for p in lo...hi { strongest = max(strongest, mag(mags, p)) }
        guard strongest > absoluteFloor else { return [] }

        var found: [Int] = []
        for p in lo...hi {
            let m = mag(mags, p)
            guard m >= mag(mags, p - 1), m >= mag(mags, p + 1) else { continue }
            guard m > relativeThreshold * strongest, m > absoluteFloor else { continue }
            var isHarmonic = false
            for (down, ratio) in harmonicRules {
                let q = p - down
                if found.contains(q) && m < ratio * mag(mags, q) { isHarmonic = true; break }
            }
            if !isHarmonic { found.append(p) }
        }
        return Set(found)
    }
}

/// Gör om "vilka toner låter nu?" (en gång per ljudfönster) till tangent ned/upp-händelser
/// med lite tröghet, så att enstaka felträffar inte blir felspelade toner.
public final class NoteTracker {

    public struct Change: Equatable, Sendable {
        public let pitch: Int
        public let down: Bool
        public init(pitch: Int, down: Bool) { self.pitch = pitch; self.down = down }
    }

    /// Antal analyser i rad som krävs för att en ton ska räknas som nedtryckt.
    public var hopsToConfirm = 2
    /// Antal analyser i rad utan ton innan den räknas som släppt.
    public var hopsToRelease = 3
    /// Så mycket starkare än förra analysen (och minsta avstånd) krävs för att tolka som ett omslag av samma ton.
    public var retriggerRatio: Float = 1.8
    public var retriggerMinHops = 5

    private var seenCount: [Int: Int] = [:]
    private var missCount: [Int: Int] = [:]
    private var down: Set<Int> = []
    private var hopsSinceDown: [Int: Int] = [:]
    private var previous: [Int: Float] = [:]

    public init() {}

    public var heldPitches: Set<Int> { down }

    /// `magnitude(p)` ger tonens aktuella styrka (för omslagsdetektering).
    public func update(active: Set<Int>, magnitude: (Int) -> Float) -> [Change] {
        var changes: [Change] = []

        for p in active {
            seenCount[p, default: 0] += 1
            missCount[p] = 0
            if down.contains(p) {
                hopsSinceDown[p, default: 0] += 1
                let now = magnitude(p)
                if let before = previous[p], before > 0,
                   now > retriggerRatio * before, hopsSinceDown[p, default: 0] >= retriggerMinHops {
                    changes.append(Change(pitch: p, down: false))
                    changes.append(Change(pitch: p, down: true))
                    hopsSinceDown[p] = 0
                }
            } else if seenCount[p, default: 0] >= hopsToConfirm {
                down.insert(p)
                hopsSinceDown[p] = 0
                changes.append(Change(pitch: p, down: true))
            }
            previous[p] = magnitude(p)
        }

        for p in Set(seenCount.keys).subtracting(active) {
            seenCount[p] = 0
            previous[p] = nil
            guard down.contains(p) else { continue }
            missCount[p, default: 0] += 1
            if missCount[p, default: 0] >= hopsToRelease {
                down.remove(p)
                missCount[p] = 0
                hopsSinceDown[p] = nil
                changes.append(Change(pitch: p, down: false))
            }
        }
        return changes.sorted { ($0.pitch, $0.down ? 1 : 0) < ($1.pitch, $1.down ? 1 : 0) }
    }

    /// Släpp allt (när mikrofonen stängs av).
    public func reset() -> [Change] {
        let out = down.sorted().map { Change(pitch: $0, down: false) }
        seenCount = [:]; missCount = [:]; down = []; hopsSinceDown = [:]; previous = [:]
        return out
    }
}
