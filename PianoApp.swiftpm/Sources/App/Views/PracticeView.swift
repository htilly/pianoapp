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
    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.verticalSizeClass) private var vSize
    @State private var pulse = false
    @State private var hideRotateHint = false

    /// iPhone (eller smalt iPad-fönster): kompakt layout.
    private var isCompact: Bool { hSize == .compact || vSize == .compact }
    /// Stående iPhone.
    private var isPortraitPhone: Bool { hSize == .compact && vSize == .regular }

    init(stored: StoredSong, song: Song, midi: MIDIManager, settings: AppSettings, store: SongStore) {
        let c = PracticeController(stored: stored, song: song, midi: midi, settings: settings)
        c.onFinished = { [weak store] score in store?.recordResult(songID: stored.id, score: score) }
        _controller = State(initialValue: c)
        self.settings = settings
        self.midi = midi
    }

    private var song: Song { controller.song }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if isCompact { compactControls } else { controls }
            }
            .padding(.horizontal, isCompact ? 8 : 16)
            .padding(.vertical, isCompact ? 4 : 8)
            .background(.bar)

            if isPortraitPhone && !hideRotateHint {
                HStack {
                    Image(systemName: "rotate.right")
                    Text("Vrid telefonen för större tangenter")
                        .font(.footnote)
                    Spacer()
                    Button { hideRotateHint = true } label: { Image(systemName: "xmark") }
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(.yellow.opacity(0.9))
                .foregroundStyle(.black)
            }

            GeometryReader { geo in
                let range = KeyboardLayout.range(for: song, width: geo.size.width)
                let layout = KeyboardLayout(lowest: range.0, highest: range.1, width: geo.size.width)
                let keyboardHeight = min(220, max(isCompact ? 80 : 120, geo.size.height * 0.28))
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
                MIDIStatusBadge(compact: isCompact)
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

                Picker("Läge", selection: modeBinding) {
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
                    Slider(value: speedBinding, in: 0.25...1.5)
                    .frame(minWidth: 120, maxWidth: 220)
                    Image(systemName: "hare.fill").foregroundStyle(.secondary)
                    Text("\(Int((controller.config.speed * 100).rounded())) %")
                        .font(.body.monospacedDigit().bold())
                        .frame(width: 56, alignment: .leading)
                }

                Spacer(minLength: 8)

                Toggle(isOn: metronomeBinding) {
                    Image(systemName: "metronome.fill")
                }
                .toggleStyle(.button)
                .help("Metronom")

                if controller.config.mode != .listen && !otherParts.isEmpty {
                    Toggle(isOn: accompanimentBinding) {
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

    // MARK: - Kompakta kontroller (iPhone)

    private var compactControls: some View {
        VStack(spacing: 2) {
            HStack(spacing: 8) {
                Button {
                    controller.togglePlay()
                } label: {
                    Image(systemName: controller.isRunning ? "pause.fill" : "play.fill")
                        .font(.title3.bold())
                        .frame(width: 40, height: 30)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    controller.restart()
                } label: {
                    Image(systemName: "backward.end.fill").frame(height: 30)
                }
                .buttonStyle(.bordered)

                Menu {
                    Picker("Läge", selection: modeBinding) {
                        ForEach(PracticeMode.allCases, id: \.self) { m in Text(m.label).tag(m) }
                    }
                } label: {
                    chip(controller.config.mode.label, systemImage: modeIcon)
                }

                if controller.config.mode != .listen && controller.availableParts.count > 1 {
                    Menu {
                        Picker("Hand", selection: handBinding) {
                            Text("✋ Vänster hand").tag("left")
                            Text("Båda händerna").tag("both")
                            Text("Höger hand 🤚").tag("right")
                        }
                    } label: {
                        chip(handShortLabel, systemImage: "hand.raised.fill")
                    }
                }

                Menu {
                    Picker("Tempo", selection: speedBinding) {
                        ForEach([0.25, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0, 1.1, 1.25, 1.5], id: \.self) { v in
                            Text("\(Int(v * 100)) %").tag(v)
                        }
                    }
                } label: {
                    chip("\(Int((controller.config.speed * 100).rounded())) %", systemImage: "tortoise.fill")
                }

                Menu {
                    Toggle(isOn: metronomeBinding) { Label("Metronom", systemImage: "metronome.fill") }
                    if controller.config.mode != .listen && !otherParts.isEmpty {
                        Toggle(isOn: accompanimentBinding) { Label("Komp (appen spelar andra handen)", systemImage: "music.note.list") }
                    }
                    Button { controller.loopButtonTapped() } label: { Label(loopLabel, systemImage: "repeat") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundStyle(controller.config.loop != nil || controller.loopStartCandidate != nil ? .yellow : .accentColor)
                }

                Spacer(minLength: 4)

                ScoreBadge(score: controller.score, mode: controller.config.mode, compact: true)
            }
            ProgressSlider(controller: controller, compact: true)
        }
    }

    private func chip(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.subheadline.bold())
            .lineLimit(1)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color.accentColor.opacity(0.15), in: Capsule())
    }

    private var modeIcon: String {
        switch controller.config.mode {
        case .listen: return "ear.fill"
        case .wait: return "hourglass"
        case .playAlong: return "music.note"
        }
    }

    private var handShortLabel: String {
        switch handKey(controller.config.hands) {
        case "right": return "Höger"
        case "left": return "Vänster"
        default: return "Båda"
        }
    }

    // MARK: - Bindningar (delas av båda layouterna)

    private var modeBinding: Binding<PracticeMode> {
        Binding(get: { controller.config.mode }, set: { m in controller.updateConfig { $0.mode = m } })
    }

    private var handBinding: Binding<String> {
        Binding(
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
        )
    }

    private var speedBinding: Binding<Double> {
        Binding(get: { controller.config.speed }, set: { v in controller.updateConfig { $0.speed = (v * 20).rounded() / 20 } })
    }

    private var metronomeBinding: Binding<Bool> {
        Binding(get: { controller.config.metronome }, set: { v in controller.updateConfig { $0.metronome = v } })
    }

    private var accompanimentBinding: Binding<Bool> {
        Binding(get: { controller.config.accompaniment }, set: { v in controller.updateConfig { $0.accompaniment = v } })
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
        return Picker("Hand", selection: handBinding) {
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
                        .font(isCompact ? .headline : .title2.bold())
                    Text(modeHint)
                        .font(isCompact ? .caption : .callout)
                        .foregroundStyle(.secondary)
                    if !midi.isConnected {
                        Text("Inget piano anslutet – du kan spela på skärmen, eller ansluta pianot under ⚙︎ Inställningar.")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
                .multilineTextAlignment(.center)
                .padding(isCompact ? 10 : 16)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 12)
                .padding(.top, isCompact ? 12 : 40)
            } else if controller.isWaiting && controller.config.mode == .wait {
                Text("Spela de lysande tangenterna")
                    .font(.headline)
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(.yellow.opacity(0.85), in: Capsule())
                    .foregroundStyle(.black)
                    .padding(.top, 12)
            } else if controller.time < 0 {
                Text("\(Int(ceil(-controller.time / song.firstBeatInterval)))")
                    .font(.system(size: isCompact ? 50 : 80, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.top, isCompact ? 10 : 40)
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
    var compact = false

    var body: some View {
        let duration = max(0.1, controller.song.duration)
        HStack(spacing: 10) {
            if !compact {
                Text(format(max(0, controller.time)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: Binding(
                get: { min(duration, max(0, controller.time)) },
                set: { controller.seek(to: $0) }
            ), in: 0...duration)
            .disabled(controller.isRunning)
            .controlSize(compact ? .mini : .regular)
            if !compact {
                Text(format(duration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
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
    var compact = false

    var body: some View {
        if mode != .listen {
            HStack(spacing: compact ? 6 : 10) {
                StarsView(stars: score.stars, size: compact ? 12 : 18)
                Label("\(score.hits)", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Palette.correct)
                if mode == .playAlong && !compact {
                    Label("\(score.misses)", systemImage: "circle.dashed")
                        .foregroundStyle(.secondary)
                }
                Label("\(score.wrong)", systemImage: "xmark.circle.fill")
                    .foregroundStyle(Palette.wrong)
            }
            .font((compact ? Font.caption : Font.headline).monospacedDigit())
            .labelStyle(.titleAndIcon)
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
