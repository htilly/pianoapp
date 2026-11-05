import SwiftUI

/// Laddar låten och visar övningsskärmen (eller ett fel).
@MainActor
struct PracticeContainer: View {
    let stored: StoredSong
    @Environment(SongStore.self) private var store
    @Environment(MIDIManager.self) private var midi
    @Environment(AppSettings.self) private var settings

    var body: some View {
        if let song = try? store.song(for: stored), !song.notes.isEmpty {
            PracticeView(stored: stored, song: song, midi: midi, settings: settings, store: store)
        } else {
            ContentUnavailableView("Kunde inte öppna låten", systemImage: "exclamationmark.triangle",
                                   description: Text("Noterna gick inte att läsa, eller alla spår är tysta."))
        }
    }
}

@MainActor
struct PracticeView: View {
    @State private var controller: PracticeController
    private let settings: AppSettings
    private let midi: MIDIManager
    @Environment(\.dismiss) private var dismiss
    @State private var pulse = false

    init(stored: StoredSong, song: Song, midi: MIDIManager, settings: AppSettings, store: SongStore) {
        let c = PracticeController(stored: stored, song: song, midi: midi, settings: settings)
        c.onFinished = { [weak store] score in store?.recordResult(songID: stored.id, score: score) }
        _controller = State(initialValue: c)
        self.settings = settings
        self.midi = midi
    }

    private var song: Song { controller.song }

    var body: some View {
        let range = KeyboardLayout.range(for: song)
        VStack(spacing: 0) {
            controls
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.bar)

            GeometryReader { geo in
                let layout = KeyboardLayout(lowest: range.0, highest: range.1, width: geo.size.width)
                let keyboardHeight = min(220, max(120, geo.size.height * 0.28))
                VStack(spacing: 0) {
                    ZStack(alignment: .top) {
                        FallingNotesView(
                            song: song,
                            layout: layout,
                            time: controller.time,
                            results: controller.results,
                            targets: controller.targets,
                            pixelsPerSecond: settings.fallSpeed,
                            naming: settings.noteNaming,
                            showNames: settings.showNoteNames,
                            loop: controller.config.loop,
                            loopStartCandidate: controller.loopStartCandidate,
                            isWaiting: controller.isWaiting
                        )
                        statusOverlay
                    }
                    KeyboardView(
                        layout: layout,
                        highlights: highlights,
                        held: controller.heldKeys,
                        naming: settings.noteNaming,
                        showLabels: settings.showKeyLabels,
                        pulse: pulse,
                        onDown: { controller.keyDown($0, fromTouch: true) },
                        onUp: { controller.keyUp($0, fromTouch: true) }
                    )
                    .frame(height: keyboardHeight)
                }
            }
        }
        .background(Palette.background)
        .navigationTitle(song.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                MIDIStatusBadge()
            }
        }
        .onAppear {
            controller.attach()
            withAnimation(.easeInOut(duration: 0.5).repeatForever()) { pulse = true }
        }
        .onDisappear { controller.detach() }
        .sheet(isPresented: Binding(get: { controller.showResult }, set: { if !$0 { controller.restart() } })) {
            ResultView(
                score: controller.score,
                title: song.title,
                speed: controller.config.speed,
                onAgain: { controller.restart() },
                onSlower: {
                    controller.updateConfig { $0.speed = max(0.25, (($0.speed - 0.1) * 20).rounded() / 20) }
                    controller.restart()
                },
                onDone: {
                    controller.restart()
                    dismiss()
                }
            )
            .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Delar

    private var highlights: [Int: Color] {
        var out: [Int: Color] = [:]
        for i in controller.highlighted where i < song.notes.count {
            let n = song.notes[i]
            let isTarget = controller.config.mode != .listen && controller.config.hands.contains(n.part)
            // Målnoter går före komp om båda lyser på samma tangent.
            if out[n.pitch] == nil || isTarget {
                out[n.pitch] = isTarget || controller.config.mode == .listen
                    ? Palette.color(for: n.part)
                    : Palette.accompaniment.opacity(0.6)
            }
        }
        return out
    }

    private var controls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                Button {
                    controller.togglePlay()
                } label: {
                    Image(systemName: controller.isRunning ? "pause.fill" : "play.fill")
                        .font(.title.bold())
                        .frame(width: 56, height: 44)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.space, modifiers: [])

                Button {
                    controller.restart()
                } label: {
                    Image(systemName: "backward.end.fill").font(.title3).frame(height: 44)
                }
                .buttonStyle(.bordered)

                Picker("Läge", selection: Binding(
                    get: { controller.config.mode },
                    set: { m in controller.updateConfig { $0.mode = m } }
                )) {
                    ForEach(PracticeMode.allCases, id: \.self) { m in
                        Text(m.label).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 380)

                Spacer(minLength: 8)

                ScoreBadge(score: controller.score, mode: controller.config.mode)
            }

            HStack(spacing: 14) {
                handPicker
                    .frame(maxWidth: 300)

                HStack(spacing: 6) {
                    Image(systemName: "tortoise.fill").foregroundStyle(.secondary)
                    Slider(value: Binding(
                        get: { controller.config.speed },
                        set: { v in controller.updateConfig { $0.speed = (v * 20).rounded() / 20 } }
                    ), in: 0.25...1.5)
                    .frame(minWidth: 120, maxWidth: 220)
                    Image(systemName: "hare.fill").foregroundStyle(.secondary)
                    Text("\(Int((controller.config.speed * 100).rounded())) %")
                        .font(.body.monospacedDigit().bold())
                        .frame(width: 56, alignment: .leading)
                }

                Spacer(minLength: 8)

                Toggle(isOn: Binding(
                    get: { controller.config.metronome },
                    set: { v in controller.updateConfig { $0.metronome = v } }
                )) {
                    Image(systemName: "metronome.fill")
                }
                .toggleStyle(.button)
                .help("Metronom")

                if controller.config.mode != .listen && !otherParts.isEmpty {
                    Toggle(isOn: Binding(
                        get: { controller.config.accompaniment },
                        set: { v in controller.updateConfig { $0.accompaniment = v } }
                    )) {
                        Label("Komp", systemImage: "music.note.list")
                    }
                    .toggleStyle(.button)
                    .help("Appen spelar den andra handen")
                }

                Button {
                    controller.loopButtonTapped()
                } label: {
                    Label(loopLabel, systemImage: "repeat")
                }
                .buttonStyle(.bordered)
                .tint(controller.config.loop != nil || controller.loopStartCandidate != nil ? .yellow : nil)
            }

            ProgressSlider(controller: controller)
        }
    }

    private var otherParts: Set<Part> {
        Set(song.notes.map(\.part)).subtracting(controller.config.hands)
    }

    private var loopLabel: String {
        if controller.config.loop != nil { return "Sluta loopa" }
        if controller.loopStartCandidate != nil { return "Sätt slut" }
        return "Loopa"
    }

    private var handPicker: some View {
        let parts = controller.availableParts
        return Picker("Hand", selection: Binding(
            get: { handKey(controller.config.hands) },
            set: { key in
                controller.updateConfig { c in
                    switch key {
                    case "right": c.hands = [.right]
                    case "left": c.hands = [.left]
                    default: c.hands = [.right, .left]
                    }
                }
            }
        )) {
            if parts.contains(.left) { Text("✋ Vänster").tag("left") }
            if parts.contains(.left) && parts.contains(.right) { Text("Båda").tag("both") }
            if parts.contains(.right) { Text("Höger 🤚").tag("right") }
        }
        .pickerStyle(.segmented)
        .disabled(controller.config.mode == .listen || parts.count < 2)
    }

    private func handKey(_ hands: Set<Part>) -> String {
        if hands == [.right] { return "right" }
        if hands == [.left] { return "left" }
        return "both"
    }

    @ViewBuilder
    private var statusOverlay: some View {
        VStack(spacing: 8) {
            if !controller.isRunning && !controller.isFinished && controller.time <= 0.01 {
                VStack(spacing: 6) {
                    Text(controller.config.mode == .wait ? "Tryck på en lysande tangent för att börja!" : "Tryck på ▶ för att börja")
                        .font(.title2.bold())
                    Text(modeHint)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if !midi.isConnected {
                        Text("Inget piano anslutet – du kan spela på skärmen, eller ansluta pianot under ⚙︎ Inställningar.")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
                .multilineTextAlignment(.center)
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .padding(.top, 40)
            } else if controller.isWaiting && controller.config.mode == .wait {
                Text("Spela de lysande tangenterna")
                    .font(.headline)
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(.yellow.opacity(0.85), in: Capsule())
                    .foregroundStyle(.black)
                    .padding(.top, 12)
            } else if controller.time < 0 {
                Text("\(Int(ceil(-controller.time / song.firstBeatInterval)))")
                    .font(.system(size: 80, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.top, 40)
            }
            if controller.score.streak >= 10 && controller.config.mode != .listen {
                Text("🔥 \(controller.score.streak) i rad!")
                    .font(.headline)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.orange.opacity(0.85), in: Capsule())
                    .foregroundStyle(.white)
            }
        }
        .allowsHitTesting(false)
    }

    private var modeHint: String {
        switch controller.config.mode {
        case .wait: return "Låten väntar på dig vid varje ton. Ta den tid du behöver."
        case .playAlong: return "Låten går i jämn takt. Försök träffa när noten når linjen."
        case .listen: return "Lyssna och titta på hur låten ska låta."
        }
    }
}

/// Visar och flyttar positionen i låten.
@MainActor
private struct ProgressSlider: View {
    let controller: PracticeController

    var body: some View {
        let duration = max(0.1, controller.song.duration)
        HStack(spacing: 10) {
            Text(format(max(0, controller.time)))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Slider(value: Binding(
                get: { min(duration, max(0, controller.time)) },
                set: { controller.seek(to: $0) }
            ), in: 0...duration)
            .disabled(controller.isRunning)
            Text(format(duration))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private func format(_ t: Double) -> String {
        let s = Int(t)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// Stjärnor och poäng under spelet.
struct ScoreBadge: View {
    let score: Score
    let mode: PracticeMode

    var body: some View {
        if mode != .listen {
            HStack(spacing: 10) {
                StarsView(stars: score.stars, size: 18)
                Label("\(score.hits)", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Palette.correct)
                if mode == .playAlong {
                    Label("\(score.misses)", systemImage: "circle.dashed")
                        .foregroundStyle(.secondary)
                }
                Label("\(score.wrong)", systemImage: "xmark.circle.fill")
                    .foregroundStyle(Palette.wrong)
            }
            .font(.headline.monospacedDigit())
        }
    }
}

struct StarsView: View {
    let stars: Int
    var size: CGFloat = 24

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { i in
                Image(systemName: i < stars ? "star.fill" : "star")
                    .foregroundStyle(i < stars ? .yellow : .secondary)
            }
        }
        .font(.system(size: size))
    }
}
