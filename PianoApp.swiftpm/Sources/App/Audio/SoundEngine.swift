import AVFoundation
import Foundation

/// Liten inbyggd pianosynt + metronom, används när ljudet inte ska gå till pianot.
final class SoundEngine: @unchecked Sendable {

    static let shared = SoundEngine()

    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private let lock = NSLock()
    private var voices: [Voice] = []
    private var sampleRate: Double = 44_100
    private(set) var isRunning = false

    var volume: Float = 0.8 {
        didSet { engine.mainMixerNode.outputVolume = volume }
    }

    private struct Voice {
        var pitch: Int          // -1 = metronomklick
        var frequency: Double
        var phase: Double = 0
        var amplitude: Double
        var age: Double = 0     // sekunder
        var releaseAge: Double? = nil
        var decay: Double       // sekunder till -60 dB ungefär
    }

    init() {
        configureSession()
        build()
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] _ in
            self?.start()
        }
    }

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setPreferredIOBufferDuration(0.005) // låg fördröjning
        try? session.setActive(true)
    }

    private func build() {
        let output = engine.outputNode.inputFormat(forBus: 0)
        sampleRate = output.sampleRate > 0 ? output.sampleRate : 44_100
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else { return }

        let node = AVAudioSourceNode(format: format) { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self else { return noErr }
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard let first = buffers.first, let data = first.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            self.render(into: data, frames: Int(frameCount))
            // Fler kanaler: kopiera.
            for b in buffers.dropFirst() {
                if let d = b.mData?.assumingMemoryBound(to: Float.self) {
                    d.update(from: data, count: Int(frameCount))
                }
            }
            return noErr
        }
        sourceNode = node
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = volume
        start()
    }

    func start() {
        guard !engine.isRunning else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            try engine.start()
            isRunning = true
        } catch {
            isRunning = false
        }
    }

    // MARK: - Spela

    func noteOn(_ pitch: Int, velocity: Int = 80) {
        start()
        let freq = 440.0 * pow(2.0, Double(pitch - 69) / 12.0)
        // Höga toner klingar kortare, som på ett riktigt piano.
        let decay = max(0.6, min(4.0, 3.5 - Double(pitch - 48) * 0.05))
        let amp = 0.18 * pow(Double(max(1, velocity)) / 127.0, 1.5) + 0.03
        lock.lock()
        // Samma ton igen: släpp den gamla.
        for i in voices.indices where voices[i].pitch == pitch && voices[i].releaseAge == nil {
            voices[i].releaseAge = 0
        }
        if voices.count > 48 { voices.removeFirst(voices.count - 48) }
        voices.append(Voice(pitch: pitch, frequency: freq, amplitude: amp, decay: decay))
        lock.unlock()
    }

    func noteOff(_ pitch: Int) {
        lock.lock()
        for i in voices.indices where voices[i].pitch == pitch && voices[i].releaseAge == nil {
            voices[i].releaseAge = 0
        }
        lock.unlock()
    }

    func allNotesOff() {
        lock.lock()
        for i in voices.indices where voices[i].releaseAge == nil { voices[i].releaseAge = 0 }
        lock.unlock()
    }

    func click(accent: Bool) {
        start()
        lock.lock()
        voices.append(Voice(pitch: -1, frequency: accent ? 1760 : 1320, amplitude: accent ? 0.35 : 0.22, decay: 0.05))
        lock.unlock()
    }

    // MARK: - Ljudtråden

    private func render(into out: UnsafeMutablePointer<Float>, frames: Int) {
        let dt = 1.0 / sampleRate
        let twoPi = 2.0 * Double.pi
        for f in 0..<frames { out[f] = 0 }

        lock.lock()
        defer { lock.unlock() }

        var i = 0
        while i < voices.count {
            var v = voices[i]
            let inc = twoPi * v.frequency * dt
            let isClick = v.pitch < 0
            var dead = false
            for f in 0..<frames {
                let attack = min(1.0, v.age / (isClick ? 0.001 : 0.004))
                var env = attack * exp(-v.age * 6.9 / v.decay)
                if let r = v.releaseAge {
                    env *= exp(-r / 0.07)
                    v.releaseAge = r + dt
                    if r > 0.5 { dead = true }
                }
                let p = v.phase
                let s: Double
                if isClick {
                    s = sin(p)
                } else {
                    // Grundton + övertoner som dör ut snabbare -> pianoaktig klang.
                    let bright = exp(-v.age * 3.0)
                    s = sin(p)
                        + 0.45 * bright * sin(2 * p)
                        + 0.22 * bright * sin(3 * p)
                        + 0.10 * bright * bright * sin(4 * p)
                        + 0.05 * bright * bright * sin(5 * p)
                }
                out[f] += Float(s * env * v.amplitude)
                v.phase = p + inc
                if v.phase > twoPi { v.phase -= twoPi }
                v.age += dt
            }
            if v.age > v.decay * 1.2 { dead = true }
            if dead {
                voices.remove(at: i)
            } else {
                voices[i] = v
                i += 1
            }
        }
        // Mjuk begränsning så att ackord inte spräcker ljudet.
        for f in 0..<frames {
            let x = out[f]
            out[f] = x / (1 + abs(x))
        }
    }
}
