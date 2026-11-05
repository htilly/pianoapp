import SwiftUI

@MainActor
struct LibraryView: View {
    @Environment(SongStore.self) private var store
    @Environment(MIDIManager.self) private var midi
    @Environment(AppSettings.self) private var settings

    @State private var showImport = false
    @State private var showSettings = false
    @State private var editing: StoredSong?
    @State private var renaming: StoredSong?
    @State private var newName = ""
    @State private var path: [StoredSong] = []

    @Environment(\.horizontalSizeClass) private var hSize

    private var compact: Bool { hSize == .compact }
    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: compact ? 150 : 250), spacing: compact ? 10 : 16)]
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    LazyVGrid(columns: columns, spacing: compact ? 10 : 16) {
                        ForEach(store.songs) { song in
                            NavigationLink(value: song) {
                                SongCard(song: song)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button { editing = song } label: { Label("Ändra händer", systemImage: "hand.raised") }
                                Button { newName = song.title; renaming = song } label: { Label("Byt namn", systemImage: "pencil") }
                                Button(role: .destructive) { store.delete(song) } label: { Label("Ta bort", systemImage: "trash") }
                            }
                        }
                        Button { showImport = true } label: {
                            VStack(spacing: 10) {
                                Image(systemName: "plus.circle.fill").font(.system(size: 40))
                                Text("Lägg till låt").font(.headline)
                                Text("Klistra in ABC-noter eller välj en MIDI-fil")
                                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, minHeight: compact ? 120 : 150)
                            .background(RoundedRectangle(cornerRadius: 18).strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 6])).foregroundStyle(.tint))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .navigationTitle("Pianoskola")
            .navigationDestination(for: StoredSong.self) { song in
                PracticeContainer(stored: song)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: { MIDIStatusBadge(compact: compact) }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showImport = true } label: { Label("Lägg till", systemImage: "plus") }
                    Button { showSettings = true } label: { Label("Inställningar", systemImage: "gearshape") }
                }
            }
            .sheet(isPresented: $showImport) { ImportView() }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(item: $editing) { song in HandEditSheet(stored: song) }
            .alert("Byt namn", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Namn", text: $newName)
                Button("Spara") {
                    if var s = renaming, !newName.trimmingCharacters(in: .whitespaces).isEmpty {
                        s.title = newName
                        store.update(s)
                    }
                    renaming = nil
                }
                Button("Avbryt", role: .cancel) { renaming = nil }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(settings.playerName.isEmpty ? "Välj en låt att öva på" : "Hej \(settings.playerName)! Vad vill du spela idag?")
                .font(.title2.bold())
            Text("Tips: börja med en hand i taget i läget ”Vänta på mig”, och höj tempot när det går bra.")
                .foregroundStyle(.secondary)
        }
    }
}

struct SongCard: View {
    let song: StoredSong
    @Environment(SongStore.self) private var store

    var body: some View {
        let parsed = try? store.song(for: song)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: song.format == .midi ? "pianokeys" : "music.quarternote.3")
                    .font(.title2)
                    .foregroundStyle(.tint)
                Spacer()
                StarsView(stars: song.bestStars, size: 16)
            }
            Text(song.title)
                .font(.headline)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
            if let parsed {
                HStack(spacing: 8) {
                    Text(duration(parsed.duration))
                    Text("·")
                    Text(handsText(parsed))
                    if song.timesPlayed > 0 {
                        Text("·")
                        Text("spelad \(song.timesPlayed) ggr")
                    }
                }
                .font(.caption)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(.secondary)
            } else {
                Text("Kunde inte läsa noterna").font(.caption).foregroundStyle(.red)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(.secondarySystemBackground)))
        .contentShape(RoundedRectangle(cornerRadius: 18))
    }

    private func duration(_ t: Double) -> String {
        let s = Int(t.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private func handsText(_ s: Song) -> String {
        let parts = Set(s.notes.map(\.part))
        if parts.contains(.left) && parts.contains(.right) { return "Två händer" }
        if parts.contains(.left) { return "Vänster hand" }
        return "Höger hand"
    }
}

/// Liten indikator: är pianot anslutet?
struct MIDIStatusBadge: View {
    @Environment(MIDIManager.self) private var midi
    /// Bara en prick (för smala skärmar).
    var compact = false

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(midi.isConnected ? Color.green : Color.gray)
                .frame(width: 10, height: 10)
            if !compact {
                Text(midi.isConnected ? (midi.sources.first?.name ?? "Piano") : "Inget piano")
                    .font(.subheadline)
                    .lineLimit(1)
            }
        }
    }
}
