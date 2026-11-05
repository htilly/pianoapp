import Foundation

public enum SongFormat: String, Codable, Sendable {
    case abc
    case midi
}

/// Ett importerat stycke som ännu inte sparats.
public struct ImportedSong: Sendable {
    public var format: SongFormat
    /// ABC-text, eller MIDI-data som base64.
    public var source: String
    public var song: Song
}

public enum SongImporter {

    /// Tolkar inklistrad text: ABC-noter, eller MIDI som base64 / hex.
    /// En text med flera ABC-låtar (X:) ger flera resultat.
    public static func importText(_ text: String) throws -> [ImportedSong] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SongImportError.unrecognizedFormat }

        if let data = decodeBinaryText(trimmed), isMIDI(data) {
            return [try importMIDI(data)]
        }
        if ABCParser.looksLikeABC(trimmed) {
            let tunes = ABCParser.splitTunes(trimmed)
            var result: [ImportedSong] = []
            var firstError: Error?
            for (i, tune) in tunes.enumerated() {
                do {
                    let song = try ABCParser.parse(tune, fallbackTitle: tunes.count > 1 ? "ABC-låt \(i + 1)" : "ABC-låt")
                    result.append(ImportedSong(format: .abc, source: tune, song: song))
                } catch {
                    if firstError == nil { firstError = error }
                }
            }
            if result.isEmpty { throw firstError ?? SongImportError.noNotes }
            return result
        }
        throw SongImportError.unrecognizedFormat
    }

    /// Importerar en fil (.mid, .midi, .abc, .txt).
    public static func importFile(data: Data, fileName: String) throws -> [ImportedSong] {
        let baseName = (fileName as NSString).deletingPathExtension
        if isMIDI(data) {
            return [try importMIDI(data, title: baseName)]
        }
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw SongImportError.unrecognizedFormat
        }
        return try importText(text)
    }

    public static func importMIDI(_ data: Data, title: String = "MIDI-låt") throws -> ImportedSong {
        let song = try MIDIFileParser.parse(data, fallbackTitle: title)
        return ImportedSong(format: .midi, source: data.base64EncodedString(), song: song)
    }

    /// Tolkar sparad källa igen.
    public static func parse(format: SongFormat, source: String, title: String) throws -> Song {
        switch format {
        case .abc:
            return try ABCParser.parse(source, fallbackTitle: title)
        case .midi:
            guard let data = Data(base64Encoded: source, options: .ignoreUnknownCharacters) else {
                throw SongImportError.invalidMIDI("felaktig base64")
            }
            return try MIDIFileParser.parse(data, fallbackTitle: title)
        }
    }

    static func isMIDI(_ data: Data) -> Bool {
        data.count >= 14 && data.prefix(4) == Data("MThd".utf8)
    }

    /// Avkodar base64 (även data:-URL) eller hex ("4D 54 68 64 …").
    static func decodeBinaryText(_ text: String) -> Data? {
        var t = text
        if let comma = t.firstIndex(of: ","), t.hasPrefix("data:") {
            t = String(t[t.index(after: comma)...])
        }
        let compact = t.filter { !$0.isWhitespace }
        if compact.hasPrefix("TVRoZ"), let d = Data(base64Encoded: compact) ?? Data(base64Encoded: padded(compact)) {
            return d
        }
        // Hex
        let hex = compact.replacingOccurrences(of: "0x", with: "").replacingOccurrences(of: ",", with: "")
        if hex.lowercased().hasPrefix("4d546864"), hex.count % 2 == 0, hex.allSatisfy(\.isHexDigit) {
            var bytes: [UInt8] = []
            bytes.reserveCapacity(hex.count / 2)
            var idx = hex.startIndex
            while idx < hex.endIndex {
                let next = hex.index(idx, offsetBy: 2)
                guard let b = UInt8(hex[idx..<next], radix: 16) else { return nil }
                bytes.append(b)
                idx = next
            }
            return Data(bytes)
        }
        return nil
    }

    private static func padded(_ s: String) -> String {
        let rem = s.count % 4
        return rem == 0 ? s : s + String(repeating: "=", count: 4 - rem)
    }
}
