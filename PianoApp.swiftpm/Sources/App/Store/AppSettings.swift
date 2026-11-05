import Foundation
import Observation

/// Var appens egna toner (komp, Lyssna-läget) ska låta.
enum SoundOutput: String, CaseIterable, Identifiable {
    case automatic  // pianot om det är anslutet, annars iPaden
    case piano
    case device
    case both

    var id: String { rawValue }

    var label: String {
        switch self {
        case .automatic: return "Automatiskt"
        case .piano: return "Pianot"
        case .device: return "iPaden"
        case .both: return "Båda"
        }
    }
}

/// Vad övningsskärmen visar ovanför klaviaturen.
enum ScoreDisplay: String, CaseIterable, Identifiable {
    case both       // noter och fallande noter
    case notes      // bara noter: träna på att läsa
    case falling    // bara fallande noter

    var id: String { rawValue }

    var label: String {
        switch self {
        case .both: return "Noter och fallande"
        case .notes: return "Bara noter"
        case .falling: return "Bara fallande"
        }
    }

    var systemImage: String {
        switch self {
        case .both: return "square.split.1x2"
        case .notes: return "music.quarternote.3"
        case .falling: return "arrow.down.to.line"
        }
    }
}

@MainActor
@Observable
final class AppSettings {
    var soundOutput: SoundOutput { didSet { save("soundOutput", soundOutput.rawValue) } }
    var noteNaming: NoteNaming { didSet { save("noteNaming", noteNaming.rawValue) } }
    var showNoteNames: Bool { didSet { save("showNoteNames", showNoteNames) } }
    var showKeyLabels: Bool { didSet { save("showKeyLabels", showKeyLabels) } }
    var scoreDisplay: ScoreDisplay { didSet { save("scoreDisplay", scoreDisplay.rawValue) } }
    /// Pixlar per sekund som noterna faller.
    var fallSpeed: Double { didSet { save("fallSpeed", fallSpeed) } }
    var hitWindow: Double { didSet { save("hitWindow", hitWindow) } }
    var volume: Double { didSet { save("volume", volume) } }
    var playerName: String { didSet { save("playerName", playerName) } }

    init() {
        let d = UserDefaults.standard
        soundOutput = SoundOutput(rawValue: d.string(forKey: "soundOutput") ?? "") ?? .automatic
        noteNaming = NoteNaming(rawValue: d.string(forKey: "noteNaming") ?? "") ?? .swedish
        showNoteNames = d.object(forKey: "showNoteNames") as? Bool ?? true
        showKeyLabels = d.object(forKey: "showKeyLabels") as? Bool ?? true
        scoreDisplay = ScoreDisplay(rawValue: d.string(forKey: "scoreDisplay") ?? "") ?? .both
        fallSpeed = d.object(forKey: "fallSpeed") as? Double ?? 160
        hitWindow = d.object(forKey: "hitWindow") as? Double ?? 0.18
        volume = d.object(forKey: "volume") as? Double ?? 0.8
        playerName = d.string(forKey: "playerName") ?? ""
    }

    private func save(_ key: String, _ value: Any) {
        UserDefaults.standard.set(value, forKey: key)
    }
}
