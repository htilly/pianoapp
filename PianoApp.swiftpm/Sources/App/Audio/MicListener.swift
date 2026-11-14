import AVFoundation
import Foundation
import Observation

/// Lyssnar på ett vanligt (akustiskt) piano via mikrofonen och översätter det
/// man spelar till tangenttryck – för den som inte har ett MIDI-piano.
@MainActor
@Observable
final class MicListener {

    enum State: Equatable {
        case off
        case starting
        case listening
        case denied
        case failed(String)
    }

    private(set) var state: State = .off
    /// Ljudnivå 0...1 för en liten nivåmätare.
    private(set) var level: Double = 0
    /// Toner som just nu hörs.
    private(set) var heard: Set<Int> = []

    /// Anropas på huvudtråden: (tonhöjd, nedtryckt?)
    @ObservationIgnored var onNote: (@MainActor (Int, Bool) -> Void)?

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var processor: MicProcessor?

    var isOn: Bool { state == .starting || state == .listening }

    // MARK: - Start / stopp

    func start() async {
        guard !isOn else { return }
        state = .starting

        let granted = await AVAudioApplication.requestRecordPermission()
        guard granted else {
            state = .denied
            return
        }
        // Användaren kan ha hunnit stänga av igen medan frågan visades.
        guard state == .starting else { return }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.mixWithOthers, .defaultToSpeaker])
            try session.setActive(true)

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                throw MicError.noInput
            }

            let processor = MicProcessor(sampleRate: format.sampleRate) { [weak self] changes, level, heard in
                Task { @MainActor in self?.deliver(changes: changes, level: level, heard: heard) }
            }
            self.processor = processor

            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, _ in
                processor.process(buffer)
            }
            engine.prepare()
            try engine.start()
            state = .listening
        } catch {
            teardown()
            state = .failed(error.localizedDescription)
        }
    }

    func stop() {
        let released = processor?.reset() ?? []
        teardown()
        for c in released { onNote?(c.pitch, false) }
        heard = []
        level = 0
        state = .off
    }

    private func teardown() {
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }
        processor = nil
        // Tillbaka till ren uppspelning, och se till att ljudmotorn går igen.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
        SoundEngine.shared.start()
    }

    private func deliver(changes: [NoteTracker.Change], level: Float, heard: Set<Int>) {
        guard state == .listening else { return }
        self.level = Double(min(1, level * 12))
        self.heard = heard
        for c in changes { onNote?(c.pitch, c.down) }
    }

    private enum MicError: LocalizedError {
        case noInput
        var errorDescription: String? { "Ingen mikrofon hittades." }
    }
}

/// Samlar ljud från mikrofonens tråd, kör tonigenkänningen och rapporterar tillbaka.
/// Allt här körs på ljudtråden – därför `@unchecked Sendable` med ett lås.
private final class MicProcessor: @unchecked Sendable {

    private let detector: PitchDetector
    private let tracker = NoteTracker()
    private let handler: @Sendable ([NoteTracker.Change], Float, Set<Int>) -> Void
    private let lock = NSLock()

    private var ring: [Float]
    private var filled = 0
    private var sinceLastAnalysis = 0
    /// Analysera ungefär var 2048:e prov (~46 ms).
    private let hop = 2048

    init(sampleRate: Double, handler: @escaping @Sendable ([NoteTracker.Change], Float, Set<Int>) -> Void) {
        self.detector = PitchDetector(sampleRate: sampleRate)
        self.handler = handler
        self.ring = [Float](repeating: 0, count: detector.size)
    }

    func process(_ buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return }

        lock.lock()
        defer { lock.unlock() }

        let n = ring.count
        if frames >= n {
            for i in 0..<n { ring[i] = channel[frames - n + i] }
        } else {
            ring.withUnsafeMutableBufferPointer { r in
                // Skjut ner gamla prov och lägg de nya sist.
                for i in 0..<(n - frames) { r[i] = r[i + frames] }
                for i in 0..<frames { r[n - frames + i] = channel[i] }
            }
        }
        filled = min(n, filled + frames)
        sinceLastAnalysis += frames

        guard filled >= n, sinceLastAnalysis >= hop else { return }
        sinceLastAnalysis = 0

        let result = detector.analyze(ring)
        let first = PitchDetector.lowestPitch - 1
        let changes = tracker.update(active: result.pitches) { pitch in
            result.magnitudes[pitch - first]
        }
        handler(changes, result.level, tracker.heldPitches)
    }

    func reset() -> [NoteTracker.Change] {
        lock.lock()
        defer { lock.unlock() }
        return tracker.reset()
    }
}
