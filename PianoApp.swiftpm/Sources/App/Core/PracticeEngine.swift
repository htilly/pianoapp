import Foundation

public enum PracticeMode: String, CaseIterable, Codable, Sendable {
    case listen     // appen spelar, barnet lyssnar och tittar
    case wait       // låten väntar tills rätt tangenter trycks
    case playAlong  // låten går i tempo, träffar räknas

    public var label: String {
        switch self {
        case .listen: return "Lyssna"
        case .wait: return "Vänta på mig"
        case .playAlong: return "Spela med"
        }
    }
}

public struct PracticeConfig: Equatable, Sendable {
    public var mode: PracticeMode = .wait
    /// Händer som barnet spelar.
    public var hands: Set<Part> = [.right, .left]
    /// 1.0 = originaltempo.
    public var speed: Double = 1.0
    /// Appen spelar de toner barnet inte övar på (andra handen, komp).
    public var accompaniment: Bool = true
    public var metronome: Bool = false
    /// En takts inräkning innan låten börjar (Spela med / Lyssna).
    public var countIn: Bool = true
    /// Tillåten tidsavvikelse i Spela med-läget (sekunder i verklig tid).
    public var hitWindow: Double = 0.18
    /// Övar bara en del av låten (sekunder i låten).
    public var loop: ClosedRange<Double>? = nil

    public init() {}
}

public enum EngineEvent: Equatable, Sendable {
    case noteOn(pitch: Int, velocity: Int)
    case noteOff(pitch: Int)
    case tick(accent: Bool)
    case finished
}

public enum NoteResult: Equatable, Sendable {
    case pending
    case hit
    case missed
    case auto  // spelad av appen
}

public struct Score: Equatable, Sendable {
    public var hits = 0
    public var misses = 0
    public var wrong = 0
    public var streak = 0
    public var bestStreak = 0
    public var mode: PracticeMode = .wait

    public var accuracy: Double {
        switch mode {
        case .listen: return 1
        case .wait:
            let total = hits + wrong
            return total == 0 ? 0 : Double(hits) / Double(total)
        case .playAlong:
            let total = hits + misses + wrong / 2
            return total == 0 ? 0 : Double(hits) / Double(total)
        }
    }

    public var stars: Int {
        guard hits > 0 else { return 0 }
        switch accuracy {
        case 0.9...: return 3
        case 0.7..<0.9: return 2
        case 0.4..<0.7: return 1
        default: return 0
        }
    }
}

/// Plattformsoberoende övningslogik. Appen anropar `update(now:)` varje bildruta
/// och `keyDown`/`keyUp` vid tangenttryck, och spelar upp händelserna som returneras.
public final class PracticeEngine {

    public let song: Song
    public private(set) var config: PracticeConfig

    /// Position i låten (sekunder vid 100 % tempo). Negativ under inräkning.
    public private(set) var time: Double = 0
    public private(set) var isRunning = false
    public private(set) var isFinished = false
    /// Sant när Vänta-läget står still och väntar på barnet.
    public private(set) var isWaiting = false
    public private(set) var results: [NoteResult]
    public private(set) var score = Score()
    /// Nedtryckta tangenter -> om de var rätt.
    public private(set) var heldKeys: [Int: Bool] = [:]

    private var groups: [[Int]] = []          // målnoter grupperade per anslag
    private var groupTimes: [Double] = []
    private var groupCursor = 0
    private var satisfied = Set<Int>()
    private var targetIndices: [Int] = []     // målnoter sorterade på start
    private var targetSet = Set<Int>()
    private var missCursor = 0
    private var autoCursor = 0
    private var activeAuto: [(end: Double, pitch: Int)] = []
    private var beats: [(time: Double, accent: Bool)] = []
    private var beatCursor = 0
    private var lastWall: Double?

    /// Hur långt innan en notgrupp man får trycka i Vänta-läget (verkliga sekunder).
    public var earlyWindow = 0.35

    public init(song: Song, config: PracticeConfig = PracticeConfig()) {
        self.song = song
        self.config = config
        self.results = Array(repeating: .pending, count: song.notes.count)
        rebuildTargets()
        rebuildBeats()
        seekInternal(to: config.loop?.lowerBound ?? 0)
    }

    // MARK: - Styrning

    public func setConfig(_ newConfig: PracticeConfig) {
        let old = config
        config = newConfig
        if old.mode != newConfig.mode || old.hands != newConfig.hands {
            rebuildTargets()
            seekInternal(to: time < 0 ? 0 : time)
        }
        if old.countIn != newConfig.countIn || old.loop != newConfig.loop {
            rebuildBeats()
            beatCursor = beats.firstIndex { $0.time >= time - 1e-6 } ?? beats.count
        }
        if old.mode != newConfig.mode {
            score.mode = newConfig.mode
        }
    }

    /// Startar (eller fortsätter) uppspelningen.
    @discardableResult
    public func start(now: Double) -> [EngineEvent] {
        if isFinished { _ = restart() }
        lastWall = now
        isRunning = true
        let loopStart = config.loop?.lowerBound ?? 0
        if config.countIn && config.mode != .wait && abs(time - loopStart) < 0.001 {
            let bpb = Double(song.beatsPerBar)
            time = loopStart - bpb * song.firstBeatInterval
            beatCursor = beats.firstIndex { $0.time >= time - 1e-6 } ?? beats.count
        }
        return []
    }

    @discardableResult
    public func pause() -> [EngineEvent] {
        isRunning = false
        isWaiting = false
        if time < (config.loop?.lowerBound ?? 0) { seekInternal(to: config.loop?.lowerBound ?? 0) }
        return releaseAll()
    }

    /// Börjar om från början (eller loopens början) och nollställer poängen.
    @discardableResult
    public func restart() -> [EngineEvent] {
        let ev = releaseAll()
        isRunning = false
        isFinished = false
        score = Score(mode: config.mode)
        results = Array(repeating: .pending, count: song.notes.count)
        seekInternal(to: config.loop?.lowerBound ?? 0)
        return ev
    }

    @discardableResult
    public func seek(to t: Double) -> [EngineEvent] {
        let ev = releaseAll()
        seekInternal(to: max(0, t))
        lastWall = nil
        return ev
    }

    // MARK: - Tid

    public func update(now: Double) -> [EngineEvent] {
        guard isRunning else { lastWall = now; return [] }
        let dt = max(0, min(0.25, now - (lastWall ?? now)))
        lastWall = now
        var events: [EngineEvent] = []
        var newTime = time + dt * config.speed

        // Vänta-läget: stanna vid nästa ospelade grupp.
        if config.mode == .wait, groupCursor < groups.count {
            let gt = groupTimes[groupCursor]
            if newTime >= gt {
                newTime = gt
                isWaiting = true
            } else {
                isWaiting = false
            }
        } else {
            isWaiting = false
        }

        // Missade toner i Spela med.
        if config.mode == .playAlong {
            let window = config.hitWindow * config.speed
            while missCursor < targetIndices.count {
                let idx = targetIndices[missCursor]
                if song.notes[idx].start < newTime - window {
                    if results[idx] == .pending {
                        results[idx] = .missed
                        score.misses += 1
                        score.streak = 0
                    }
                    missCursor += 1
                } else {
                    break
                }
            }
        }

        // Metronom och inräkning.
        while beatCursor < beats.count && beats[beatCursor].time <= newTime {
            let b = beats[beatCursor]
            if b.time < 0 || b.time < (config.loop?.lowerBound ?? 0) - 1e-6 || config.metronome {
                if b.time > time - 1e-6 || time < 0 { events.append(.tick(accent: b.accent)) }
            }
            beatCursor += 1
        }

        // Släpp automatiska toner som är klara.
        activeAuto.removeAll { a in
            if a.end <= newTime { events.append(.noteOff(pitch: a.pitch)); return true }
            return false
        }

        // Starta automatiska toner.
        while autoCursor < song.notes.count && song.notes[autoCursor].start <= newTime {
            let idx = autoCursor
            let n = song.notes[idx]
            autoCursor += 1
            guard n.start >= time - 1e-6 || time < 0 else { continue }
            if shouldAutoPlay(idx) {
                results[idx] = .auto
                events.append(.noteOn(pitch: n.pitch, velocity: n.velocity))
                activeAuto.append((n.end, n.pitch))
            }
        }

        time = newTime

        // Loop.
        if let loop = config.loop, time >= loop.upperBound {
            events += releaseAll()
            for i in song.notes.indices where song.notes[i].start >= loop.lowerBound - 1e-6 && song.notes[i].start < loop.upperBound {
                results[i] = .pending
            }
            seekInternal(to: loop.lowerBound)
            lastWall = now
            return events
        }

        // Slut.
        let doneWaiting = config.mode != .wait || groupCursor >= groups.count
        if config.loop == nil && doneWaiting && time >= song.duration + 0.3 {
            events += releaseAll()
            isRunning = false
            isFinished = true
            events.append(.finished)
        }
        return events
    }

    // MARK: - Tangenter

    public func keyDown(_ pitch: Int) {
        var correct = false
        switch config.mode {
        case .listen:
            correct = true
        case .wait:
            if isRunning, groupCursor < groups.count {
                let gt = groupTimes[groupCursor]
                let group = groups[groupCursor]
                if (gt - time) / max(0.05, config.speed) <= earlyWindow {
                    if let idx = group.first(where: { song.notes[$0].pitch == pitch && !satisfied.contains($0) }) {
                        satisfied.insert(idx)
                        results[idx] = .hit
                        registerHit()
                        correct = true
                        if satisfied.count == group.count {
                            groupCursor += 1
                            satisfied = []
                            isWaiting = false
                        }
                    } else if group.contains(where: { song.notes[$0].pitch == pitch }) {
                        correct = true // samma tangent igen – inte fel
                    }
                }
                if !correct, groupCursor > 0,
                   groups[groupCursor - 1].contains(where: { song.notes[$0].pitch == pitch }),
                   time - groupTimes[groupCursor - 1] < 0.3 {
                    correct = true // efterslängande ton i ett nyss klart ackord
                }
            } else {
                correct = true
            }
            if !correct { registerWrong() }
        case .playAlong:
            guard isRunning else { correct = true; break }
            let window = config.hitWindow * config.speed
            var best: Int?
            var bestDist = Double.infinity
            for idx in targetIndices where song.notes[idx].pitch == pitch && results[idx] == .pending {
                let d = abs(song.notes[idx].start - time)
                if d <= window && d < bestDist { best = idx; bestDist = d }
                if song.notes[idx].start > time + window { break }
            }
            if let b = best {
                results[b] = .hit
                registerHit()
                correct = true
            } else {
                registerWrong()
            }
        }
        heldKeys[pitch] = correct
    }

    public func keyUp(_ pitch: Int) {
        heldKeys[pitch] = nil
    }

    // MARK: - För visning

    /// Toner som ska lysa på klaviaturen just nu.
    public var highlightedNotes: [Int] {
        var out: [Int] = []
        if config.mode == .wait, groupCursor < groups.count {
            let gt = groupTimes[groupCursor]
            if gt - time < 1.5 {
                out += groups[groupCursor].filter { !satisfied.contains($0) }
            }
            // Auto-toner som klingar.
            for (i, n) in song.notes.enumerated() where !targetSet.contains(i) && n.start <= time && n.end > time {
                out.append(i)
            }
            return out
        }
        for (i, n) in song.notes.enumerated() where n.start <= time + 0.02 && n.end > time {
            out.append(i)
        }
        return out
    }

    /// Är noten något barnet ska spela?
    public func isTarget(_ index: Int) -> Bool { targetSet.contains(index) }

    public var targetCount: Int { targetIndices.count }

    /// Andel av låten (0–1).
    public var progress: Double {
        guard song.duration > 0 else { return 0 }
        return min(1, max(0, time / song.duration))
    }

    // MARK: - Internt

    private func shouldAutoPlay(_ idx: Int) -> Bool {
        if config.mode == .listen { return true }
        if targetSet.contains(idx) { return false }
        return config.accompaniment
    }

    private func registerHit() {
        score.hits += 1
        score.streak += 1
        score.bestStreak = max(score.bestStreak, score.streak)
    }

    private func registerWrong() {
        score.wrong += 1
        score.streak = 0
    }

    private func releaseAll() -> [EngineEvent] {
        let ev = activeAuto.map { EngineEvent.noteOff(pitch: $0.pitch) }
        activeAuto = []
        return ev
    }

    private func rebuildTargets() {
        targetIndices = []
        if config.mode != .listen {
            for (i, n) in song.notes.enumerated() where n.part != .accompaniment && config.hands.contains(n.part) {
                targetIndices.append(i)
            }
        }
        targetSet = Set(targetIndices)
        groups = []
        groupTimes = []
        for idx in targetIndices {
            let t = song.notes[idx].start
            if let last = groupTimes.last, t - last < 0.03 {
                if !groups[groups.count - 1].contains(where: { song.notes[$0].pitch == song.notes[idx].pitch }) {
                    groups[groups.count - 1].append(idx)
                }
            } else {
                groups.append([idx])
                groupTimes.append(t)
            }
        }
        score.mode = config.mode
    }

    private func rebuildBeats() {
        let bpb = song.beatsPerBar
        let interval = song.firstBeatInterval
        var b: [(Double, Bool)] = []
        let loopStart = config.loop?.lowerBound ?? 0
        // Inräkning före start (och före loopens början).
        for k in stride(from: bpb, to: 0, by: -1) {
            b.append((loopStart - Double(k) * interval, k == bpb))
        }
        let countInStart = loopStart - Double(bpb) * interval
        for (i, t) in song.beatTimes.enumerated() {
            // Hoppa över låtens egna slag där inräkningen redan tickar.
            if t > countInStart - 1e-3 && t < loopStart - 1e-3 { continue }
            b.append((t, i % bpb == 0))
        }
        beats = b.sorted { $0.0 < $1.0 }.map { (time: $0.0, accent: $0.1) }
    }

    private func seekInternal(to t: Double) {
        time = t
        isWaiting = false
        satisfied = []
        autoCursor = song.notes.firstIndex { $0.start >= t - 1e-6 } ?? song.notes.count
        groupCursor = groupTimes.firstIndex { $0 >= t - 1e-6 } ?? groups.count
        missCursor = targetIndices.firstIndex { song.notes[$0].start >= t - 1e-6 } ?? targetIndices.count
        beatCursor = beats.firstIndex { $0.time >= t - 1e-6 } ?? beats.count
    }
}
