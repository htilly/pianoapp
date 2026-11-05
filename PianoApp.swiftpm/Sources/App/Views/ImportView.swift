import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct ImportView: View {
    @Environment(SongStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var imported: [ImportedSong] = []
    @State private var title = ""
    @State private var assignment = HandAssignment()
    @State private var error: String?
    @State private var showFilePicker = false
    @State private var showHelp = false
    @Environment(\.horizontalSizeClass) private var hSize

    private var fileTypes: [UTType] {
        var t: [UTType] = [.midi, .plainText, .text]
        if let abc = UTType(filenameExtension: "abc") { t.append(abc) }
        if let mid = UTType(filenameExtension: "mid") { t.append(mid) }
        return t
    }

    var body: some View {
        NavigationStack {
            Form {
                if imported.isEmpty {
                    inputSection
                } else {
                    previewSection
                }
                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                    }
                }
                Section {
                    DisclosureGroup("Hjälp: hur skriver man ABC-noter?", isExpanded: $showHelp) {
                        Text(Self.helpText)
                            .font(.callout)
                            .textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("Lägg till låt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if !imported.isEmpty {
                        Button(imported.count > 1 ? "Spara alla (\(imported.count))" : "Spara") { save() }
                            .bold()
                    } else {
                        Button("Läs in") { parseText() }
                            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .fileImporter(isPresented: $showFilePicker, allowedContentTypes: fileTypes) { result in
                handleFile(result)
            }
        }
    }

    // MARK: - Delar

    private var inputSection: some View {
        Section {
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("Klistra in ABC-noter här …\n\nX:1\nT:Min låt\nM:4/4\nL:1/4\nK:C\nC D E F | G2 G2 |]\n\n… eller en MIDI-fil som base64-text.")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                        .padding(.leading, 4)
                }
                TextEditor(text: $text)
                    .font(.system(.body, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .frame(minHeight: hSize == .compact ? 180 : 260)
            }
            ViewThatFits(in: .horizontal) {
                HStack { importButtons(spacer: true) }
                VStack(alignment: .leading, spacing: 10) { importButtons(spacer: false) }
            }
        } header: {
            Text("Noter")
        } footer: {
            Text("Gratis ABC-låtar finns t.ex. på abcnotation.com. MIDI-filer kan laddas ner från t.ex. musescore.com eller bitmidi.com. Du kan också be en AI-assistent skriva en låt i ABC-notation.")
        }
    }

    @ViewBuilder
    private func importButtons(spacer: Bool) -> some View {
                Button {
                    if let s = UIPasteboard.general.string {
                        text = s
                        parseText()
                    } else {
                        error = "Urklippet är tomt."
                    }
                } label: {
                    Label("Klistra in", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.bordered)

                Button {
                    showFilePicker = true
                } label: {
                    Label("Välj fil (.mid / .abc)", systemImage: "folder")
                }
                .buttonStyle(.bordered)

                if spacer { Spacer() }

                Button("Läs in") { parseText() }
                    .buttonStyle(.borderedProminent)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @ViewBuilder
    private var previewSection: some View {
        if imported.count > 1 {
            Section("Hittade \(imported.count) låtar") {
                ForEach(Array(imported.enumerated()), id: \.offset) { _, item in
                    HStack {
                        Text(item.song.title)
                        Spacer()
                        Text("\(item.song.notes.count) toner").foregroundStyle(.secondary)
                    }
                }
            }
        } else if let first = imported.first {
            Section("Låt") {
                TextField("Namn", text: $title)
                    .font(.headline)
                LabeledContent("Format", value: first.format == .midi ? "MIDI" : "ABC")
                LabeledContent("Antal toner", value: "\(first.song.notes.count)")
                LabeledContent("Längd", value: String(format: "%d:%02d", Int(first.song.duration) / 60, Int(first.song.duration) % 60))
                LabeledContent("Tempo", value: "\(Int(first.song.tempoMap.initialBPM.rounded())) slag/min")
            }
            HandEditor(song: first.song, assignment: $assignment)
        }
        Section {
            Button("Börja om", role: .destructive) {
                imported = []
                error = nil
            }
        }
    }

    // MARK: - Logik

    private func parseText() {
        error = nil
        do {
            setImported(try SongImporter.importText(text))
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func handleFile(_ result: Result<URL, Error>) {
        error = nil
        switch result {
        case .failure(let e):
            error = e.localizedDescription
        case .success(let url):
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                setImported(try SongImporter.importFile(data: data, fileName: url.lastPathComponent))
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func setImported(_ songs: [ImportedSong]) {
        imported = songs
        if let first = songs.first {
            title = first.song.title
            assignment = HandAssigner.automatic(for: first.song)
        }
    }

    private func save() {
        if imported.count == 1, let first = imported.first {
            store.add(first, title: title, assignment: assignment)
        } else {
            for item in imported { store.add(item) }
        }
        dismiss()
    }

    static let helpText = """
    ABC är ett enkelt sätt att skriva noter med vanliga bokstäver.

    Huvud (överst):
      X:1            låtens nummer
      T:Blinka lilla titel
      M:4/4          taktart
      L:1/4          grundlängd (1/4 = fjärdedel)
      Q:1/4=90       tempo
      K:C            tonart (G, F, Dm, Bb …)

    Noter:
      C D E F G A B  = mitt-C och uppåt
      c d e … b      = en oktav högre
      C, D,          = en oktav lägre (komma)
      c'             = två oktaver högre
      ^F  _B  =F     = kors, b, återställt
      C2  C/2  C3/2  = dubbelt så lång, halv, en och en halv
      z              = paus
      [CEG]          = ackord
      C-C            = bindebåge
      |  |:  :|      = taktstreck och repris
      [1 … :|[2 …    = 1:a och 2:a slut

    Två händer – skriv två stämmor:
      V:1
      V:2 clef=bass
      [V:1] E E F G | G F E D |
      [V:2] C,4     | G,,4    |

    Stämma 1 blir höger hand och stämma 2 (basklav) vänster hand. Det går att ändra när låten läses in.
    """
}

/// Välj vilken hand varje spår/stämma ska spelas med.
struct HandEditor: View {
    let song: Song
    @Binding var assignment: HandAssignment

    var body: some View {
        Section {
            ForEach(song.tracks) { track in
                Picker(selection: Binding(
                    get: { assignment.role(for: track.id) },
                    set: { assignment.roles[track.id] = $0 }
                )) {
                    ForEach(TrackRole.allCases, id: \.self) { r in Text(r.label).tag(r) }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.name)
                        Text("\(track.noteCount) toner · \(NoteNaming.swedish.name(for: track.lowestPitch, withOctave: true))–\(NoteNaming.swedish.name(for: track.highestPitch, withOctave: true))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if song.tracks.contains(where: { assignment.role(for: $0.id) == .split }) {
                Stepper(value: $assignment.splitPitch, in: 0...128) {
                    LabeledContent("Delningspunkt", value: splitLabel)
                }
            }
            summary
        } header: {
            Text("Händer")
        } footer: {
            Text("Höger hand visas i blått och vänster hand i orange. ”Dela” låter toner under delningspunkten spelas med vänster hand. ”Komp” spelas av appen.")
        }
    }

    private var splitLabel: String {
        switch assignment.splitPitch {
        case ...0: return "allt höger hand"
        case 128...: return "allt vänster hand"
        default: return "under \(NoteNaming.swedish.name(for: assignment.splitPitch, withOctave: true))"
        }
    }

    private var summary: some View {
        let applied = HandAssigner.apply(assignment, to: song)
        let r = applied.notes.filter { $0.part == .right }.count
        let l = applied.notes.filter { $0.part == .left }.count
        let a = applied.notes.filter { $0.part == .accompaniment }.count
        return HStack(spacing: 16) {
            Label("\(r) höger", systemImage: "circle.fill").foregroundStyle(Palette.right)
            Label("\(l) vänster", systemImage: "circle.fill").foregroundStyle(Palette.left)
            if a > 0 { Label("\(a) komp", systemImage: "circle.fill").foregroundStyle(Palette.accompaniment) }
        }
        .font(.callout)
    }
}

/// Ändra händer för en sparad låt.
@MainActor
struct HandEditSheet: View {
    let stored: StoredSong
    @Environment(SongStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var assignment = HandAssignment()
    @State private var base: Song?

    var body: some View {
        NavigationStack {
            Form {
                if let base {
                    HandEditor(song: base, assignment: $assignment)
                    Section {
                        Button("Återställ automatiskt val") { assignment = HandAssigner.automatic(for: base) }
                    }
                } else {
                    Text("Kunde inte läsa låten.")
                }
            }
            .navigationTitle(stored.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Avbryt") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Spara") {
                        var s = stored
                        s.assignment = assignment
                        store.update(s)
                        dismiss()
                    }
                    .bold()
                }
            }
            .onAppear {
                base = try? store.baseSong(for: stored)
                if let base { assignment = stored.assignment ?? HandAssigner.automatic(for: base) }
            }
        }
    }
}
