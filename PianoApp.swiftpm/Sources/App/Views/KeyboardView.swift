import SwiftUI

/// Färger som används i hela appen.
enum Palette {
    static let right = Color(red: 0.25, green: 0.56, blue: 1.0)    // höger hand: blå
    static let left = Color(red: 1.0, green: 0.58, blue: 0.18)     // vänster hand: orange
    static let accompaniment = Color(white: 0.55)
    static let correct = Color(red: 0.2, green: 0.85, blue: 0.4)
    static let wrong = Color(red: 0.95, green: 0.25, blue: 0.3)
    static let background = Color(red: 0.07, green: 0.08, blue: 0.13)

    static func color(for part: Part) -> Color {
        switch part {
        case .right: return right
        case .left: return left
        case .accompaniment: return accompaniment
        }
    }
}

/// Geometri för en klaviatur med ett visst omfång.
struct KeyboardLayout {
    let lowest: Int
    let highest: Int
    let width: CGFloat
    private let whiteIndex: [Int: Int]
    let whiteCount: Int

    init(lowest: Int, highest: Int, width: CGFloat) {
        var lo = max(21, lowest)
        var hi = min(108, highest)
        if lo.isBlackKey { lo -= 1 }
        if hi.isBlackKey { hi += 1 }
        if hi < lo + 12 { lo = min(lo, 96); hi = lo + 12 } // skydd mot konstiga omfång
        self.lowest = lo
        self.highest = hi
        self.width = width
        var map: [Int: Int] = [:]
        var n = 0
        for p in lo...hi where !p.isBlackKey {
            map[p] = n
            n += 1
        }
        whiteIndex = map
        whiteCount = max(1, n)
    }

    /// Omfång som passar en låt: hela oktaver, minst två.
    static func range(for song: Song) -> (Int, Int) {
        var lo = song.lowestPitch - 2
        var hi = song.highestPitch + 2
        lo -= ((lo % 12) + 12) % 12          // ner till C
        hi += 12 - (((hi % 12) + 12) % 12)   // upp till nästa C
        while hi - lo < 24 {
            if lo > 36 { lo -= 12 } else { hi += 12 }
        }
        lo = max(21, min(lo, 84))
        hi = min(108, max(hi, lo + 24))
        return (lo, hi)
    }

    var whiteWidth: CGFloat { width / CGFloat(whiteCount) }
    var blackWidth: CGFloat { whiteWidth * 0.62 }

    /// x-position och bredd för en tangent.
    func keyFrame(_ pitch: Int) -> (x: CGFloat, width: CGFloat)? {
        guard pitch >= lowest && pitch <= highest else { return nil }
        if pitch.isBlackKey {
            guard let left = whiteIndex[pitch - 1] else { return nil }
            let x = CGFloat(left + 1) * whiteWidth - blackWidth / 2
            return (x, blackWidth)
        }
        guard let i = whiteIndex[pitch] else { return nil }
        return (CGFloat(i) * whiteWidth, whiteWidth)
    }

    /// Vilken tangent som finns under en punkt.
    func pitch(at point: CGPoint, height: CGFloat) -> Int? {
        if point.y < height * 0.62 {
            for p in lowest...highest where p.isBlackKey {
                if let f = keyFrame(p), point.x >= f.x && point.x <= f.x + f.width { return p }
            }
        }
        let i = Int(point.x / whiteWidth)
        return whiteIndex.first { $0.value == i }?.key
    }
}

/// Pianoklaviatur. Lyser i handens färg där man ska spela, grönt/rött när man trycker.
struct KeyboardView: View {
    let layout: KeyboardLayout
    /// tonhöjd -> färg för tangenter som ska spelas
    let highlights: [Int: Color]
    /// tonhöjd -> rätt?
    let held: [Int: Bool]
    let naming: NoteNaming
    let showLabels: Bool
    let pulse: Bool
    var onDown: (Int) -> Void
    var onUp: (Int) -> Void

    @State private var touching: Int?

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            Canvas { ctx, size in
                let ww = layout.whiteWidth
                // Vita tangenter
                for p in layout.lowest...layout.highest where !p.isBlackKey {
                    guard let f = layout.keyFrame(p) else { continue }
                    let rect = CGRect(x: f.x + 1, y: 0, width: f.width - 2, height: size.height - 2)
                    let path = Path(roundedRect: rect, cornerRadii: .init(bottomLeading: 6, bottomTrailing: 6))
                    ctx.fill(path, with: .color(.white))
                    if let c = fill(for: p) {
                        ctx.fill(path, with: .color(c))
                    }
                    if showLabels {
                        let isC = p % 12 == 0
                        let label = naming.name(for: p, withOctave: isC && ww > 26)
                        let text = Text(label)
                            .font(.system(size: min(16, ww * 0.42), weight: isC ? .bold : .regular, design: .rounded))
                            .foregroundColor(isC ? .black : .gray)
                        ctx.draw(text, at: CGPoint(x: rect.midX, y: rect.maxY - min(16, ww * 0.42)))
                    }
                }
                // Svarta tangenter
                for p in layout.lowest...layout.highest where p.isBlackKey {
                    guard let f = layout.keyFrame(p) else { continue }
                    let rect = CGRect(x: f.x, y: 0, width: f.width, height: size.height * 0.62)
                    let path = Path(roundedRect: rect, cornerRadii: .init(bottomLeading: 4, bottomTrailing: 4))
                    ctx.fill(path, with: .color(Color(white: 0.1)))
                    if let c = fill(for: p) {
                        ctx.fill(path, with: .color(c))
                    }
                }
            }
            .background(Color.black)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let p = layout.pitch(at: value.location, height: h)
                        if p != touching {
                            if let old = touching { onUp(old) }
                            touching = p
                            if let p { onDown(p) }
                        }
                    }
                    .onEnded { _ in
                        if let old = touching { onUp(old) }
                        touching = nil
                    }
            )
        }
    }

    private func fill(for pitch: Int) -> Color? {
        if let ok = held[pitch] {
            return (ok ? Palette.correct : Palette.wrong).opacity(0.9)
        }
        if let c = highlights[pitch] {
            return c.opacity(pulse ? 0.95 : 0.7)
        }
        return nil
    }
}
