import Foundation
import Observation

/// En sparad låt: källan (ABC-text eller MIDI som base64) plus inställningar och resultat.
struct StoredSong: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var format: SongFormat
    var source: String
    var assignment: HandAssignment?
    var isExample: Bool = false
    var addedAt: Date = Date()
    var bestStars: Int = 0
    var bestAccuracy: Double = 0
    var timesPlayed: Int = 0
}

@MainActor
@Observable
final class SongStore {
    private(set) var songs: [StoredSong] = []
    @ObservationIgnored private var cache: [String: Song] = [:]

    private var fileURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("songs.json")
    }

    init() {
        load()
        addMissingExamples()
    }

    // MARK: - Läsa

    /// Färdig låt med handfördelning.
    func song(for stored: StoredSong) throws -> Song {
        let base = try baseSong(for: stored)
        let assignment = stored.assignment ?? HandAssigner.automatic(for: base)
        return HandAssigner.apply(assignment, to: base)
    }

    /// Låten utan handfördelning (alla spår).
    func baseSong(for stored: StoredSong) throws -> Song {
        if let s = cache[stored.id] { return s }
        let s = try SongImporter.parse(format: stored.format, source: stored.source, title: stored.title)
        cache[stored.id] = s
        return s
    }

    // MARK: - Ändra

    @discardableResult
    func add(_ imported: ImportedSong, title: String? = nil, assignment: HandAssignment? = nil) -> StoredSong {
        let stored = StoredSong(
            id: UUID().uuidString,
            title: (title?.isEmpty == false ? title! : imported.song.title),
            format: imported.format,
            source: imported.source,
            assignment: assignment
        )
        songs.insert(stored, at: firstUserIndex)
        cache[stored.id] = imported.song
        save()
        return stored
    }

    func update(_ song: StoredSong) {
        guard let i = songs.firstIndex(where: { $0.id == song.id }) else { return }
        songs[i] = song
        save()
    }

    func delete(_ song: StoredSong) {
        songs.removeAll { $0.id == song.id }
        cache[song.id] = nil
        if song.isExample {
            var hidden = UserDefaults.standard.stringArray(forKey: "hiddenExamples") ?? []
            hidden.append(song.id)
            UserDefaults.standard.set(hidden, forKey: "hiddenExamples")
        }
        save()
    }

    func restoreExamples() {
        UserDefaults.standard.removeObject(forKey: "hiddenExamples")
        addMissingExamples()
    }

    func recordResult(songID: String, score: Score) {
        guard let i = songs.firstIndex(where: { $0.id == songID }) else { return }
        songs[i].timesPlayed += 1
        if score.mode != .listen {
            songs[i].bestStars = max(songs[i].bestStars, score.stars)
            songs[i].bestAccuracy = max(songs[i].bestAccuracy, score.accuracy)
        }
        save()
    }

    // MARK: - Lagring

    private var firstUserIndex: Int {
        songs.firstIndex { !$0.isExample } ?? songs.count
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([StoredSong].self, from: data) else { return }
        songs = decoded
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(songs)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Kunde inte spara låtar: \(error)")
        }
    }

    private func addMissingExamples() {
        let hidden = Set(UserDefaults.standard.stringArray(forKey: "hiddenExamples") ?? [])
        var changed = false
        for (i, ex) in ExampleSongs.all.enumerated() where !hidden.contains(ex.id) {
            if let existing = songs.firstIndex(where: { $0.id == ex.id }) {
                // Uppdatera noterna om de ändrats i en ny version av appen.
                if songs[existing].source != ex.abc {
                    songs[existing].source = ex.abc
                    cache[ex.id] = nil
                    changed = true
                }
                continue
            }
            guard let parsed = try? ABCParser.parse(ex.abc) else { continue }
            let s = StoredSong(id: ex.id, title: parsed.title, format: .abc, source: ex.abc, isExample: true)
            songs.insert(s, at: min(i, songs.count))
            changed = true
        }
        if changed { save() }
    }
}
