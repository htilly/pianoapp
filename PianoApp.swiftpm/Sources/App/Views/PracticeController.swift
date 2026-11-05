import Foundation
import Observation
import QuartzCore
import UIKit

/// Driver övningen: kör motorn varje bildruta, tar emot tangenter från pianot
/// eller skärmen och spelar upp appens toner.
@MainActor
@Observable
final class PracticeController {

    let stored: StoredSong
    let song: Song
    private(set) var config: PracticeConfig

    // Speglat från motorn för visning.
    private(set) var time: Double = 0
    private(set) var isRunning = false
    private(set) var isFinished = false
    private(set) var isWaiting = false
    private(set) var score = Score()
    private(set) var heldKeys: [Int: Bool] = [:]
    private(set) var highlighted: [Int] = []
    private(set) var results: [NoteResult] = []
    /// Tangenter som trycks på skärmen.
    private(set) var touchedKeys: Set<Int> = []
    /// A–B-loop som håller på att väljas.
    private(set) var loopStartCandidate: Double?
    private(set) var isScrubbing = false
    var showResult = false

    @ObservationIgnored private let engine: PracticeEngine
    @ObservationIgnored private let midi: MIDIManager
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let sound = SoundEngine.shared
    @ObservationIgnored private var link: CADisplayLink?
    @ObservationIgnored private var linkTarget: DisplayLinkTarget?
    @ObservationIgnored private var resumeAfterScrub = false
    @ObservationIgnored private var scrubAnchor: Double = 0
    @ObservationIgnored var onFinished: ((Score) -> Void)?

    init(stored: StoredSong, song: Song, midi: MIDIManager, settings: AppSettings) {
        self.stored = stored
        self.song = song
        self.midi = midi
        self.settings = settings

        var c = PracticeConfig()
        let d = UserDefaults.standard
        c.mode = PracticeMode(rawValue: d.string(forKey: "practice.mode") ?? "") ?? .wait
        let hands = d.string(forKey: "practice.hands") ?? "both"
        c.hands = hands == "right" ? [.right] : hands == "left" ? [.left] : [.right, .left]
        c.speed = d.object(forKey: "practice.speed") as? Double ?? 1.0
        c.metronome = d.bool(forKey: "practice.metronome")
        c.accompaniment = d.object(forKey: "practice.accompaniment") as? Bool ?? true
        c.hitWindow = settings.hitWindow
        // Låten har bara en hand: öva på den.
        let parts = Set(song.notes.map(\.part)).subtracting([.accompaniment])
        if !parts.isEmpty && c.hands.isDisjoint(with: parts) { c.hands = parts }
        self.config = c
        self.engine = PracticeEngine(song: song, config: c)
        updateTargets()
        sync()
    }

    /// targets[i] = ska barnet spela not i?
    private(set) var targets: [Bool] = []

    var availableParts: Set<Part> { Set(song.notes.map(\.part)).subtracting([.accompaniment]) }

    // MARK: - Livscykel

    func attach() {
        guard link == nil else { return }
        midi.onNote = { [weak self] pitch, down, velocity in
            guard let self else { return }
            if down { self.keyDown(pitch, velocity: velocity, fromTouch: false) } else { self.keyUp(pitch, fromTouch: false) }
        }
        let target = DisplayLinkTarget { [weak self] in self?.tick() }
        let l = CADisplayLink(target: target, selector: #selector(DisplayLinkTarget.step))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 60)
        l.add(to: .main, forMode: .common)
        link = l
        linkTarget = target
        UIApplication.shared.isIdleTimerDisabled = true
    }

    func detach() {
        isScrubbing = false
        resumeAfterScrub = false
        play(engine.pause())
        link?.invalidate()
        link = nil
        linkTarget = nil
        midi.onNote = nil
        stopAllSound()
        UIApplication.shared.isIdleTimerDisabled = false
        sync()
    }

    private func tick() {
        let events = engine.update(now: CACurrentMediaTime())
        play(events)
        sync()
    }

    private func updateTargets() {
        targets = song.notes.indices.map { engine.isTarget($0) }
    }

    private func sync() {
        time = engine.time
        isRunning = engine.isRunning
        isFinished = engine.isFinished
        isWaiting = engine.isWaiting
        score = engine.score
        heldKeys = engine.heldKeys
        highlighted = engine.highlightedNotes
        results = engine.results
    }

    // MARK: - Kontroller

    func togglePlay() {
        if engine.isRunning {
            play(engine.pause())
        } else {
            play(engine.start(now: CACurrentMediaTime()))
        }
        sync()
    }

    func restart() {
        play(engine.restart())
        stopAllSound()
        showResult = false
        sync()
    }

    func seek(to t: Double) {
        play(engine.seek(to: clampedToSong(t)))
        sync()
    }

    // MARK: - Spola

    /// Låten står still medan man spolar och fortsätter när man släpper.
    func beginScrub() {
        guard !isScrubbing else { return }
        isScrubbing = true
        resumeAfterScrub = engine.isRunning
        if engine.isRunning { play(engine.pause()) }
        scrubAnchor = engine.time
        sync()
    }

    func scrub(to t: Double) {
        beginScrub()
        seek(to: t)
    }

    /// Flyttar relativt positionen där spolningen började.
    func scrub(by offset: Double) {
        beginScrub()
        seek(to: scrubAnchor + offset)
    }

    func endScrub() {
        guard isScrubbing else { return }
        isScrubbing = false
        if resumeAfterScrub { play(engine.start(now: CACurrentMediaTime())) }
        resumeAfterScrub = false
        sync()
    }

    private func clampedToSong(_ t: Double) -> Double {
        let range = config.loop ?? 0...max(0, song.duration)
        return min(range.upperBound, max(range.lowerBound, t))
    }

    func updateConfig(_ change: (inout PracticeConfig) -> Void) {
        var c = config
        change(&c)
        guard c != config else { return }
        let modeChanged = c.mode != config.mode
        config = c
        engine.setConfig(c)
        if modeChanged { play(engine.restart()) }
        updateTargets()
        let d = UserDefaults.standard
        d.set(c.mode.rawValue, forKey: "practice.mode")
        d.set(c.hands == [.right] ? "right" : c.hands == [.left] ? "left" : "both", forKey: "practice.hands")
        d.set(c.speed, forKey: "practice.speed")
        d.set(c.metronome, forKey: "practice.metronome")
        d.set(c.accompaniment, forKey: "practice.accompaniment")
        sync()
    }

    /// Första tryck sätter loopens början (vid taktstreck), andra trycket slutet, tredje tar bort loopen.
    func loopButtonTapped() {
        if config.loop != nil {
            updateConfig { $0.loop = nil }
            loopStartCandidate = nil
            return
        }
        let bar = barStart(atOrBefore: max(0, time))
        if let a = loopStartCandidate {
            var b = barStart(after: max(time, a + 0.01))
            if b <= a { b = a + max(1, song.firstBeatInterval * Double(song.beatsPerBar)) }
            loopStartCandidate = nil
            updateConfig { $0.loop = a...b }
            play(engine.seek(to: a))
            sync()
        } else {
            loopStartCandidate = bar
        }
    }

    private func barStart(atOrBefore t: Double) -> Double {
        song.barTimes.last { $0 <= t + 0.05 } ?? 0
    }

    private func barStart(after t: Double) -> Double {
        song.barTimes.first { $0 > t + 0.05 } ?? song.duration
    }

    // MARK: - Tangenter

    func keyDown(_ pitch: Int, velocity: Int = 90, fromTouch: Bool) {
        if fromTouch {
            touchedKeys.insert(pitch)
            playUserNote(pitch, velocity: velocity)
        }
        // Vänta-läget: första tangenttrycket startar låten.
        if config.mode == .wait && !engine.isRunning && !engine.isFinished && !showResult && !isScrubbing {
            play(engine.start(now: CACurrentMediaTime()))
        }
        engine.keyDown(pitch)
        sync()
    }

    func keyUp(_ pitch: Int, fromTouch: Bool) {
        if fromTouch {
            touchedKeys.remove(pitch)
            stopUserNote(pitch)
        }
        engine.keyUp(pitch)
        sync()
    }

    // MARK: - Ljud

    private var pianoOut: Bool {
        guard midi.canSend else { return false }
        switch settings.soundOutput {
        case .automatic, .piano, .both: return true
        case .device: return false
        }
    }

    private var deviceOut: Bool {
        switch settings.soundOutput {
        case .automatic, .piano: return !midi.canSend
        case .device, .both: return true
        }
    }

    private func play(_ events: [EngineEvent]) {
        for e in events {
            switch e {
            case let .noteOn(p, v):
                if pianoOut { midi.sendNoteOn(p, velocity: v) }
                if deviceOut { sound.noteOn(p, velocity: v) }
            case let .noteOff(p):
                if pianoOut { midi.sendNoteOff(p) }
                sound.noteOff(p)
            case let .tick(accent):
                sound.click(accent: accent)
            case .finished:
                showResult = true
                onFinished?(engine.score)
            }
        }
    }

    /// Skärmtangenter låter på pianot när ett är anslutet, annars i iPaden.
    /// Med Båda valt låter de på båda ställena.
    private func playUserNote(_ pitch: Int, velocity: Int) {
        if pianoOut { midi.sendNoteOn(pitch, velocity: velocity) }
        if !pianoOut || settings.soundOutput == .both {
            sound.noteOn(pitch, velocity: velocity)
        }
    }

    private func stopUserNote(_ pitch: Int) {
        if pianoOut { midi.sendNoteOff(pitch) }
        sound.noteOff(pitch)
    }

    private func stopAllSound() {
        sound.allNotesOff()
        if midi.canSend { midi.allNotesOff() }
    }
}

/// CADisplayLink kräver ett Objective-C-mål.
@MainActor
final class DisplayLinkTarget: NSObject {
    private let callback: @MainActor () -> Void
    init(_ callback: @escaping @MainActor () -> Void) { self.callback = callback }
    @objc func step() { callback() }
}
