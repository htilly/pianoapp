import SwiftUI

/// Noterna i ett vanligt notsystem. De rullar förbi en spelmarkör i takt med
/// låten, och de tangenter man trycker ner visas direkt i systemet, så att man
/// ser sambandet mellan tangenten och noten.
struct ScoreView: View {
    let notation: Notation
    let time: Double
    let results: [NoteResult]
    let targets: [Bool]
    let held: [Int: Bool]
    let naming: NoteNaming
    let showNames: Bool
    let loop: ClosedRange<Double>?
    let loopStartCandidate: Double?
    let isWaiting: Bool
    /// I Lyssna-läget ska man inte spela själv, men noterna ska ändå synas tydligt.
    let isListening: Bool

    var body: some View {
        Canvas { ctx, size in
            ScoreRenderer(view: self, size: size).draw(in: &ctx)
        }
        .accessibilityElement()
        .accessibilityLabel("Noter")
    }
}

/// Mått som bara beror på låten och höjden.
struct ScoreMetrics {
    /// Avstånd mellan två linjer i systemet.
    let spacing: CGFloat
    let pointsPerTick: CGFloat
    /// Övre kanten på det första systemets översta linje.
    let firstStaffTop: CGFloat
    let staffDistance: CGFloat

    /// Plats ovanför, under och mellan systemen, i radavstånd.
    private static let margin: CGFloat = 5.5
    private static let between: CGFloat = 7

    static func unitsTall(staves: Int) -> CGFloat {
        let n = CGFloat(max(1, staves))
        return margin * 2 + n * 4 + (n - 1) * between
    }

    /// Lägsta höjd där noterna går att läsa.
    static func minimumHeight(staves: Int) -> CGFloat {
        unitsTall(staves: staves) * 7
    }

    init(notation: Notation, height: CGFloat) {
        let units = Self.unitsTall(staves: notation.clefs.count)
        spacing = max(5, min(15, height / units))
        // Tätare noter kräver mer plats, så att sextondelarna inte krockar.
        let perQuarter: CGFloat = notation.shortestTicks < 6 ? 11 : notation.shortestTicks < 12 ? 8 : 6.5
        pointsPerTick = spacing * perQuarter / CGFloat(Notation.ticksPerQuarter)
        firstStaffTop = (height - units * spacing) / 2 + Self.margin * spacing
        staffDistance = (4 + Self.between) * spacing
    }

    func staffTop(_ index: Int) -> CGFloat {
        firstStaffTop + CGFloat(index) * staffDistance
    }
}

private struct ScoreRenderer {
    let view: ScoreView
    let size: CGSize
    let m: ScoreMetrics
    let notation: Notation
    let sp: CGFloat
    let gutter: CGFloat
    let playheadX: CGFloat
    let position: Double

    private let paper = Color(red: 0.98, green: 0.96, blue: 0.90)
    private let ink = Color(red: 0.13, green: 0.13, blue: 0.17)
    private let lineColor = Color(red: 0.36, green: 0.36, blue: 0.38)

    init(view: ScoreView, size: CGSize) {
        self.view = view
        self.size = size
        notation = view.notation
        m = ScoreMetrics(notation: view.notation, height: size.height)
        sp = m.spacing
        let signature = CGFloat(abs(notation.key.fifths)) * sp * 1.05
        gutter = sp * 4.2 + signature + sp * 2.6
        playheadX = gutter + max(sp * 4, min(size.width * 0.12, sp * 9))
        position = notation.tick(atTime: view.time)
    }

    private func x(_ tick: Double) -> CGFloat {
        playheadX + CGFloat(tick - position) * m.pointsPerTick
    }

    /// Taktstrecket står strax före taktens första not, inte ovanpå den.
    private func barlineX(_ tick: Double) -> CGFloat {
        x(tick) - sp * 1.9
    }

    private func y(_ pos: Int, _ clef: Clef) -> CGFloat {
        let index = notation.clefs.firstIndex(of: clef) ?? 0
        return m.staffTop(index) + 4 * sp - CGFloat(pos) * sp / 2
    }

    private var visibleTicks: ClosedRange<Double> {
        let margin = Double(sp * 4 / m.pointsPerTick)
        let first = position - Double(playheadX - gutter) / Double(m.pointsPerTick) - margin
        let last = position + Double(size.width - playheadX) / Double(m.pointsPerTick) + margin
        return first...last
    }

    // MARK: - Hela bilden

    func draw(in ctx: inout GraphicsContext) {
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(paper))

        drawLoop(in: &ctx)
        drawStaffLines(in: &ctx)
        drawBarlines(in: &ctx)
        drawPlayhead(in: &ctx)
        drawRests(in: &ctx)
        drawChords(in: &ctx)
        drawPressedKeys(in: &ctx)
        drawGutter(in: &ctx)
    }

    // MARK: - System

    private func drawStaffLines(in ctx: inout GraphicsContext) {
        for clef in notation.clefs {
            var path = Path()
            for line in 0..<5 {
                let ly = y(line * 2, clef)
                path.move(to: CGPoint(x: 0, y: ly))
                path.addLine(to: CGPoint(x: size.width, y: ly))
            }
            ctx.stroke(path, with: .color(lineColor), lineWidth: 1)
        }
    }

    private func drawBarlines(in ctx: inout GraphicsContext) {
        guard let top = notation.clefs.first, let bottom = notation.clefs.last else { return }
        let yTop = y(8, top)
        let yBottom = y(0, bottom)
        for bar in 0...notation.barCount {
            let tick = Double(bar * notation.barTicks)
            guard visibleTicks.contains(tick) else { continue }
            let bx = barlineX(tick)
            var path = Path()
            path.move(to: CGPoint(x: bx, y: yTop))
            path.addLine(to: CGPoint(x: bx, y: yBottom))
            ctx.stroke(path, with: .color(ink.opacity(0.75)), lineWidth: bar == notation.barCount ? 3 : 1)
            if bar == notation.barCount {
                var thin = Path()
                thin.move(to: CGPoint(x: bx - 5, y: yTop))
                thin.addLine(to: CGPoint(x: bx - 5, y: yBottom))
                ctx.stroke(thin, with: .color(ink.opacity(0.75)), lineWidth: 1)
            } else {
                // Samma taktnummer som i de fallande noterna.
                let number = Text("\(bar + 1)")
                    .font(.system(size: max(9, sp), weight: .medium, design: .rounded))
                    .foregroundColor(ink.opacity(0.5))
                ctx.draw(number, at: CGPoint(x: bx + 3, y: yTop - sp * 0.4), anchor: .bottomLeading)
            }
        }
    }

    private func drawLoop(in ctx: inout GraphicsContext) {
        let top = y(8, notation.clefs.first ?? .treble) - sp * 2
        let bottom = y(0, notation.clefs.last ?? .treble) + sp * 2
        func marker(_ time: Double) {
            let lx = barlineX(notation.tick(atTime: time))
            var path = Path()
            path.move(to: CGPoint(x: lx, y: top))
            path.addLine(to: CGPoint(x: lx, y: bottom))
            ctx.stroke(path, with: .color(.orange), style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
        }
        if let loop = view.loop {
            let x1 = barlineX(notation.tick(atTime: loop.lowerBound))
            let x2 = barlineX(notation.tick(atTime: loop.upperBound))
            ctx.fill(Path(CGRect(x: x1, y: top, width: x2 - x1, height: bottom - top)),
                     with: .color(.yellow.opacity(0.22)))
            marker(loop.lowerBound)
            marker(loop.upperBound)
        } else if let start = view.loopStartCandidate {
            marker(start)
        }
    }

    private func drawPlayhead(in ctx: inout GraphicsContext) {
        let top = y(8, notation.clefs.first ?? .treble) - sp * 3
        let bottom = y(0, notation.clefs.last ?? .treble) + sp * 3
        let color: Color = view.isWaiting ? .orange : Palette.right
        ctx.fill(Path(CGRect(x: playheadX - sp * 0.9, y: top, width: sp * 1.8, height: bottom - top)),
                 with: .color(color.opacity(0.14)))
        var path = Path()
        path.move(to: CGPoint(x: playheadX, y: top))
        path.addLine(to: CGPoint(x: playheadX, y: bottom))
        ctx.stroke(path, with: .color(color.opacity(0.9)), lineWidth: 2)
    }

    // MARK: - Fast vänsterkant: klaver, tonart och taktart

    private func drawGutter(in ctx: inout GraphicsContext) {
        // Noter som passerat försvinner under klavret.
        ctx.fill(Path(CGRect(x: 0, y: 0, width: gutter, height: size.height)), with: .color(paper))
        let fade = Gradient(colors: [paper, paper.opacity(0)])
        ctx.fill(
            Path(CGRect(x: gutter, y: 0, width: sp * 2, height: size.height)),
            with: .linearGradient(fade, startPoint: CGPoint(x: gutter, y: 0), endPoint: CGPoint(x: gutter + sp * 2, y: 0))
        )

        for clef in notation.clefs {
            var lines = Path()
            for line in 0..<5 {
                let ly = y(line * 2, clef)
                lines.move(to: CGPoint(x: 0, y: ly))
                lines.addLine(to: CGPoint(x: gutter + sp * 2, y: ly))
            }
            ctx.stroke(lines, with: .color(lineColor), lineWidth: 1)

            drawClef(clef, in: &ctx)

            var ax = sp * 4.4
            for sign in notation.key.signaturePositions(clef: clef) {
                drawAccidental(sign.accidental, at: CGPoint(x: ax, y: y(sign.position, clef)), color: ink, in: &ctx)
                ax += sp * 1.05
            }
            let numberFont = Font.system(size: sp * 2.3, weight: .heavy, design: .serif)
            let digitsX = ax + sp * 0.5
            ctx.draw(Text("\(notation.timeSignature.numerator)").font(numberFont).foregroundColor(ink),
                     at: CGPoint(x: digitsX, y: y(6, clef)))
            ctx.draw(Text("\(notation.timeSignature.denominator)").font(numberFont).foregroundColor(ink),
                     at: CGPoint(x: digitsX, y: y(2, clef)))
        }
    }

    /// Klavren har händernas färger, samma som de fallande noterna.
    private func drawClef(_ clef: Clef, in ctx: inout GraphicsContext) {
        let color = clef == .treble ? Palette.right : Palette.left
        switch clef {
        case .treble:
            let glyph = Text("\u{1D11E}").font(.custom("Apple Symbols", size: sp * 9.2)).foregroundColor(color)
            ctx.draw(glyph, at: CGPoint(x: sp * 2.2, y: y(4, .treble)))
        case .bass:
            let glyph = Text("\u{1D122}").font(.custom("Apple Symbols", size: sp * 5.4)).foregroundColor(color)
            ctx.draw(glyph, at: CGPoint(x: sp * 2.2, y: y(4, .bass) + sp * 0.1))
        }
    }

    // MARK: - Pauser

    private func drawRests(in ctx: inout GraphicsContext) {
        let range = visibleTicks
        for rest in notation.rests {
            let t = Double(rest.start)
            if t > range.upperBound { break }
            if Double(rest.start + rest.ticks) < range.lowerBound { continue }
            let rx = rest.fillsBar ? x(t + Double(rest.ticks) / 2) - sp : x(t)
            drawRest(rest, at: rx, in: &ctx)
        }
    }

    private func drawRest(_ rest: NotationRest, at rx: CGFloat, in ctx: inout GraphicsContext) {
        let color = GraphicsContext.Shading.color(ink.opacity(0.85))
        let middle = y(4, rest.clef)
        switch rest.value {
        case .whole:
            let lineY = y(6, rest.clef)
            ctx.fill(Path(CGRect(x: rx - sp * 0.7, y: lineY, width: sp * 1.4, height: sp * 0.55)), with: color)
        case .half:
            ctx.fill(Path(CGRect(x: rx - sp * 0.7, y: middle - sp * 0.55, width: sp * 1.4, height: sp * 0.55)), with: color)
        case .quarter:
            var path = Path()
            path.move(to: CGPoint(x: rx - sp * 0.25, y: middle - sp * 1.5))
            path.addLine(to: CGPoint(x: rx + sp * 0.4, y: middle - sp * 0.6))
            path.addLine(to: CGPoint(x: rx - sp * 0.3, y: middle + sp * 0.15))
            path.addLine(to: CGPoint(x: rx + sp * 0.35, y: middle + sp * 0.95))
            path.addQuadCurve(to: CGPoint(x: rx + sp * 0.05, y: middle + sp * 1.55),
                              control: CGPoint(x: rx - sp * 0.65, y: middle + sp * 0.75))
            ctx.stroke(path, with: color, style: StrokeStyle(lineWidth: sp * 0.3, lineCap: .round, lineJoin: .round))
        case .eighth, .sixteenth:
            let hooks = rest.value == .sixteenth ? 2 : 1
            var slash = Path()
            slash.move(to: CGPoint(x: rx + sp * 0.5, y: middle - sp * 0.9))
            slash.addLine(to: CGPoint(x: rx - sp * 0.05, y: middle + sp * (hooks == 2 ? 1.5 : 0.9)))
            ctx.stroke(slash, with: color, style: StrokeStyle(lineWidth: sp * 0.14, lineCap: .round))
            for i in 0..<hooks {
                let hy = middle - sp * 0.8 + CGFloat(i) * sp * 0.95
                let hx = rx + sp * 0.5 - CGFloat(i) * sp * 0.22
                var hook = Path()
                hook.move(to: CGPoint(x: hx, y: hy))
                hook.addQuadCurve(to: CGPoint(x: hx - sp * 0.75, y: hy + sp * 0.1),
                                  control: CGPoint(x: hx - sp * 0.35, y: hy + sp * 0.4))
                ctx.stroke(hook, with: color, style: StrokeStyle(lineWidth: sp * 0.14, lineCap: .round))
                ctx.fill(Path(ellipseIn: CGRect(x: hx - sp * 1.0, y: hy - sp * 0.2, width: sp * 0.42, height: sp * 0.42)), with: color)
            }
        }
    }

    // MARK: - Noter

    private struct Style {
        var color: Color
        var opacity: Double
        var current: Bool
    }

    private func style(of head: NotationHead, in chord: NotationChord) -> Style {
        let target = head.noteIndex < view.targets.count && view.targets[head.noteIndex]
        let result = head.noteIndex < view.results.count ? view.results[head.noteIndex] : .pending
        let current = position >= Double(chord.start) - 0.01 && position < Double(chord.end)
        switch result {
        case .hit:
            return Style(color: Palette.correct, opacity: 1, current: current)
        case .missed:
            return Style(color: Color(white: 0.55), opacity: 0.8, current: current)
        default:
            // Färgerna är samma som på de fallande noterna, men mörkare mot papperet.
            let base: Color
            switch head.part {
            case .right: base = Color(red: 0.08, green: 0.36, blue: 0.85)
            case .left: base = Color(red: 0.86, green: 0.38, blue: 0.02)
            case .accompaniment: base = Color(white: 0.45)
            }
            return Style(color: base, opacity: target || view.isListening ? 1 : 0.45, current: current)
        }
    }

    private func drawChords(in ctx: inout GraphicsContext) {
        let range = visibleTicks
        let chords = notation.chords
        // Binärsökning: långa låtar ska inte gå igenom alla noter varje bildruta.
        var low = 0
        var high = chords.count
        let longest = Double(notation.barTicks)
        while low < high {
            let mid = (low + high) / 2
            if Double(chords[mid].start) + longest < range.lowerBound { low = mid + 1 } else { high = mid }
        }
        var drawnGroups = Set<Int>()
        var index = low
        while index < chords.count {
            let chord = chords[index]
            if Double(chord.start) > range.upperBound { break }
            if Double(chord.end) >= range.lowerBound {
                drawChord(chord, in: &ctx)
                if let g = chord.beamGroup, drawnGroups.insert(g).inserted {
                    drawBeam(notation.beamGroups[g], in: &ctx)
                }
            }
            index += 1
        }
    }

    /// Där skaftet börjar: y-läget vid notens yttersta huvud.
    private func stemGeometry(_ chord: NotationChord) -> (x: CGFloat, near: CGFloat, far: CGFloat) {
        let hx = x(Double(chord.start))
        let stemX = chord.stemUp ? hx + sp * 0.6 : hx - sp * 0.6
        guard let low = chord.heads.first, let high = chord.heads.last else { return (stemX, 0, 0) }
        let lowY = y(low.position, chord.clef)
        let highY = y(high.position, chord.clef)
        let middle = y(4, chord.clef)
        if chord.stemUp {
            // Långt under systemet når skaftet ända till mittlinjen.
            return (stemX, lowY, min(highY - sp * 3.4, middle))
        }
        return (stemX, highY, max(lowY + sp * 3.4, middle))
    }

    private func drawChord(_ chord: NotationChord, in ctx: inout GraphicsContext) {
        let hx = x(Double(chord.start))
        let mainStyle = chord.heads.first.map { style(of: $0, in: chord) }
            ?? Style(color: ink, opacity: 1, current: false)
        let stemColor = GraphicsContext.Shading.color(mainStyle.color.opacity(mainStyle.opacity))

        // Hjälplinjer.
        var ledgers = Path()
        for head in chord.heads {
            addLedgers(for: head.position, clef: chord.clef, x: hx, to: &ledgers)
        }
        ctx.stroke(ledgers, with: .color(lineColor), lineWidth: 1)

        // Skaft och flaggor.
        if chord.value != .whole {
            let stem = stemGeometry(chord)
            if chord.beamGroup == nil {
                var path = Path()
                path.move(to: CGPoint(x: stem.x, y: stem.near))
                path.addLine(to: CGPoint(x: stem.x, y: stem.far))
                ctx.stroke(path, with: stemColor, lineWidth: max(1, sp * 0.13))
                drawFlags(chord, stem: stem, shading: stemColor, in: &ctx)
            }
        }

        // Notskrift: sekunder i ett ackord står på var sin sida om skaftet.
        var displaced = false
        var previous: Int?
        let ordered = chord.stemUp ? chord.heads : chord.heads.reversed()
        for head in ordered {
            if let p = previous, abs(head.position - p) == 1 {
                displaced.toggle()
            } else {
                displaced = false
            }
            previous = head.position
            let shift = displaced ? (chord.stemUp ? sp * 1.2 : -sp * 1.2) : 0
            let center = CGPoint(x: hx + shift, y: y(head.position, chord.clef))
            let s = style(of: head, in: chord)
            drawHead(chord.value, at: center, style: s, in: &ctx)

            if chord.dotted {
                let up = head.position % 2 == 0 ? -sp / 2 : 0
                let dot = CGRect(x: center.x + sp * 0.9, y: center.y + up - sp * 0.17, width: sp * 0.34, height: sp * 0.34)
                ctx.fill(Path(ellipseIn: dot), with: .color(s.color.opacity(s.opacity)))
            }
            if chord.tiesToNext {
                drawTie(from: center, toTick: chord.end, stemUp: chord.stemUp, shading: .color(s.color.opacity(s.opacity)), in: &ctx)
            }
        }

        // Förtecken, i kolumner så att de inte krockar i ett ackord.
        var column = 0
        for head in chord.heads.reversed() {
            guard let accidental = head.accidental else { continue }
            let s = style(of: head, in: chord)
            let ax = hx - sp * 1.35 - CGFloat(column) * sp * 1.05
            drawAccidental(accidental, at: CGPoint(x: ax, y: y(head.position, chord.clef)), color: s.color.opacity(s.opacity), in: &ctx)
            column = (column + 1) % 3
        }

        if chord.triplet && chord.beamGroup == nil {
            drawTripletMark(at: CGPoint(x: hx, y: stemGeometry(chord).far + (chord.stemUp ? -sp * 0.8 : sp * 0.8)), in: &ctx)
        }

        if view.showNames {
            drawNames(chord, x: hx, in: &ctx)
        }
    }

    private func addLedgers(for pos: Int, clef: Clef, x hx: CGFloat, to path: inout Path) {
        let halfWidth = sp * 1.0
        if pos <= -2 {
            for p in stride(from: -2, through: pos, by: -2) {
                let ly = y(p, clef)
                path.move(to: CGPoint(x: hx - halfWidth, y: ly))
                path.addLine(to: CGPoint(x: hx + halfWidth, y: ly))
            }
        } else if pos >= 10 {
            for p in stride(from: 10, through: pos, by: 2) {
                let ly = y(p, clef)
                path.move(to: CGPoint(x: hx - halfWidth, y: ly))
                path.addLine(to: CGPoint(x: hx + halfWidth, y: ly))
            }
        }
    }

    private func drawHead(_ value: NoteValue, at center: CGPoint, style: Style, in ctx: inout GraphicsContext) {
        let color = style.color.opacity(style.opacity)
        // Noten vid markören glöder, så att ögat hittar var man är.
        if style.current {
            let r = sp * 1.15
            ctx.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)),
                     with: .color(style.color.opacity(0.28)))
        }
        let w = sp * 1.32
        let h = sp * 0.95
        let oval = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
        let tilt = CGAffineTransform(translationX: center.x, y: center.y).rotated(by: -.pi / 9)
        var path = Path(ellipseIn: oval).applying(tilt)
        if value == .half || value == .whole {
            // Öppet notskrift: ett smalt hål i ovalen.
            let hole = CGRect(x: -w * 0.34, y: -h * 0.2, width: w * 0.68, height: h * 0.4)
            path.addPath(Path(ellipseIn: hole).applying(tilt))
            ctx.fill(path, with: .color(color), style: FillStyle(eoFill: true))
        } else {
            ctx.fill(path, with: .color(color))
        }
    }

    private func drawFlags(_ chord: NotationChord, stem: (x: CGFloat, near: CGFloat, far: CGFloat),
                           shading: GraphicsContext.Shading, in ctx: inout GraphicsContext) {
        let direction: CGFloat = chord.stemUp ? 1 : -1
        for i in 0..<chord.value.beams {
            let startY = stem.far + direction * CGFloat(i) * sp * 0.75
            var flag = Path()
            flag.move(to: CGPoint(x: stem.x, y: startY))
            flag.addCurve(
                to: CGPoint(x: stem.x + sp * 0.95, y: startY + direction * sp * 2.2),
                control1: CGPoint(x: stem.x + sp * 0.2, y: startY + direction * sp * 1.0),
                control2: CGPoint(x: stem.x + sp * 1.35, y: startY + direction * sp * 1.2)
            )
            ctx.stroke(flag, with: shading, style: StrokeStyle(lineWidth: sp * 0.22, lineCap: .round))
        }
    }

    private func drawBeam(_ members: [Int], in ctx: inout GraphicsContext) {
        let chords = members.map { notation.chords[$0] }
        guard let first = chords.first else { return }
        let up = first.stemUp
        let geometry = chords.map { stemGeometry($0) }
        let x1 = geometry[0].x
        let x2 = geometry[geometry.count - 1].x
        // Svag lutning som följer melodin, men balken måste nå förbi alla huvuden.
        let rawSlope = (geometry[geometry.count - 1].far - geometry[0].far) / max(1, x2 - x1)
        let slope = max(-0.18, min(0.18, rawSlope))
        var base = geometry[0].far
        for g in geometry {
            let lineAtStem = base + (g.x - x1) * slope
            if up { base += min(0, g.far - lineAtStem) } else { base += max(0, g.far - lineAtStem) }
        }
        let lineY = { (sx: CGFloat) in base + (sx - x1) * slope }
        // Balken byter färg först när sista noten i gruppen är spelad.
        let lastChord = chords[chords.count - 1]
        let style0 = lastChord.heads.first.map { style(of: $0, in: lastChord) } ?? Style(color: ink, opacity: 1, current: false)
        let shading = GraphicsContext.Shading.color(style0.color.opacity(style0.opacity))
        let thickness = sp * 0.48
        let direction: CGFloat = up ? 1 : -1

        for (c, g) in zip(chords, geometry) {
            let headStyle = c.heads.first.map { style(of: $0, in: c) } ?? style0
            var stem = Path()
            stem.move(to: CGPoint(x: g.x, y: g.near))
            stem.addLine(to: CGPoint(x: g.x, y: lineY(g.x)))
            ctx.stroke(stem, with: .color(headStyle.color.opacity(headStyle.opacity)), lineWidth: max(1, sp * 0.13))
        }

        func bar(_ from: CGFloat, _ to: CGFloat, level: Int) {
            let offset = direction * CGFloat(level) * sp * 0.72
            var path = Path()
            let half = thickness / 2 * direction
            path.move(to: CGPoint(x: from, y: lineY(from) + offset))
            path.addLine(to: CGPoint(x: to, y: lineY(to) + offset))
            path.addLine(to: CGPoint(x: to, y: lineY(to) + offset + half * 2))
            path.addLine(to: CGPoint(x: from, y: lineY(from) + offset + half * 2))
            path.closeSubpath()
            ctx.fill(path, with: shading)
        }
        bar(x1, x2, level: 0)

        // Sextondelar får en andra balk, eller en stump om grannen är längre.
        for (i, c) in chords.enumerated() where c.value == .sixteenth {
            let nextIs16 = i + 1 < chords.count && chords[i + 1].value == .sixteenth
            let previousIs16 = i > 0 && chords[i - 1].value == .sixteenth
            if nextIs16 {
                bar(geometry[i].x, geometry[i + 1].x, level: 1)
            } else if !previousIs16 {
                let stub = sp * 1.0
                let toRight = i == 0
                bar(geometry[i].x + (toRight ? 0 : -stub), geometry[i].x + (toRight ? stub : 0), level: 1)
            }
        }

        if first.triplet {
            let mid = (x1 + x2) / 2
            drawTripletMark(at: CGPoint(x: mid, y: lineY(mid) + (up ? -sp * 0.9 : sp * 0.9)), in: &ctx)
        }
    }

    private func drawTripletMark(at point: CGPoint, in ctx: inout GraphicsContext) {
        ctx.draw(Text("3").font(.system(size: max(9, sp * 1.1), weight: .bold, design: .serif).italic()).foregroundColor(ink),
                 at: point)
    }

    private func drawTie(from center: CGPoint, toTick: Int, stemUp: Bool, shading: GraphicsContext.Shading, in ctx: inout GraphicsContext) {
        let endX = x(Double(toTick))
        let direction: CGFloat = stemUp ? 1 : -1
        let y0 = center.y + direction * sp * 0.65
        var path = Path()
        path.move(to: CGPoint(x: center.x + sp * 0.5, y: y0))
        path.addQuadCurve(
            to: CGPoint(x: endX - sp * 0.5, y: y0),
            control: CGPoint(x: (center.x + endX) / 2, y: y0 + direction * sp * 0.9)
        )
        ctx.stroke(path, with: shading, style: StrokeStyle(lineWidth: max(1, sp * 0.16), lineCap: .round))
    }

    /// Notnamnen står på motsatt sida om skaftet. Det går att slå av i inställningarna
    /// när man vill öva på att läsa utan hjälp.
    private func drawNames(_ chord: NotationChord, x hx: CGFloat, in ctx: inout GraphicsContext) {
        guard let low = chord.heads.first, let high = chord.heads.last, let first = chord.heads.first else { return }
        // Bundna fortsättningar är samma ton, så namnet behövs bara en gång.
        let tiedContinuation = notation.chords.contains { $0.clef == chord.clef && $0.end == chord.start && $0.tiesToNext }
        if tiedContinuation { return }
        let names = chord.heads.reversed().map { view.naming.name(for: $0.spelled) }.joined(separator: "\n")
        let s = style(of: first, in: chord)
        let fontSize = max(8, sp * 1.05)
        let text = Text(names)
            .font(.system(size: fontSize, weight: .heavy, design: .rounded))
            .foregroundColor(s.color.opacity(max(s.opacity, 0.7)))
        let resolved = ctx.resolve(text)
        let box = resolved.measure(in: CGSize(width: 80, height: 200))
        let centerY: CGFloat
        if chord.stemUp {
            centerY = y(low.position, chord.clef) + sp * 0.75 + box.height / 2
        } else {
            centerY = y(high.position, chord.clef) - sp * 0.75 - box.height / 2
        }
        let rect = CGRect(x: hx - box.width / 2 - 1, y: centerY - box.height / 2, width: box.width + 2, height: box.height)
        ctx.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(paper.opacity(0.85)))
        ctx.draw(resolved, at: CGPoint(x: hx, y: centerY))
    }

    /// Förtecken ritas som figurer, så att de ser likadana ut oavsett typsnitt.
    private func drawAccidental(_ accidental: Accidental, at c: CGPoint, color: Color, in ctx: inout GraphicsContext) {
        let shading = GraphicsContext.Shading.color(color)
        let thin = StrokeStyle(lineWidth: max(1, sp * 0.11), lineCap: .butt)
        let thick = StrokeStyle(lineWidth: max(1.5, sp * 0.3), lineCap: .butt)
        switch accidental {
        case .sharp:
            var verticals = Path()
            for dx in [-sp * 0.2, sp * 0.2] {
                verticals.move(to: CGPoint(x: c.x + dx, y: c.y - sp * 1.2))
                verticals.addLine(to: CGPoint(x: c.x + dx, y: c.y + sp * 1.2))
            }
            ctx.stroke(verticals, with: shading, style: thin)
            var bars = Path()
            for dy in [-sp * 0.42, sp * 0.42] {
                bars.move(to: CGPoint(x: c.x - sp * 0.42, y: c.y + dy + sp * 0.12))
                bars.addLine(to: CGPoint(x: c.x + sp * 0.42, y: c.y + dy - sp * 0.12))
            }
            ctx.stroke(bars, with: shading, style: thick)
        case .flat:
            var stem = Path()
            stem.move(to: CGPoint(x: c.x - sp * 0.3, y: c.y - sp * 1.5))
            stem.addLine(to: CGPoint(x: c.x - sp * 0.3, y: c.y + sp * 0.5))
            ctx.stroke(stem, with: shading, style: StrokeStyle(lineWidth: max(1, sp * 0.13)))
            var bowl = Path()
            bowl.move(to: CGPoint(x: c.x - sp * 0.3, y: c.y - sp * 0.2))
            bowl.addCurve(
                to: CGPoint(x: c.x - sp * 0.3, y: c.y + sp * 0.5),
                control1: CGPoint(x: c.x + sp * 0.2, y: c.y - sp * 0.65),
                control2: CGPoint(x: c.x + sp * 0.75, y: c.y - sp * 0.05)
            )
            ctx.stroke(bowl, with: shading, style: StrokeStyle(lineWidth: max(1.2, sp * 0.2), lineCap: .round))
        case .natural:
            var verticals = Path()
            verticals.move(to: CGPoint(x: c.x - sp * 0.28, y: c.y - sp * 1.2))
            verticals.addLine(to: CGPoint(x: c.x - sp * 0.28, y: c.y + sp * 0.5))
            verticals.move(to: CGPoint(x: c.x + sp * 0.28, y: c.y - sp * 0.5))
            verticals.addLine(to: CGPoint(x: c.x + sp * 0.28, y: c.y + sp * 1.2))
            ctx.stroke(verticals, with: shading, style: thin)
            var bars = Path()
            for dy in [-sp * 0.4, sp * 0.4] {
                bars.move(to: CGPoint(x: c.x - sp * 0.28, y: c.y + dy + sp * 0.1))
                bars.addLine(to: CGPoint(x: c.x + sp * 0.28, y: c.y + dy - sp * 0.1))
            }
            ctx.stroke(bars, with: shading, style: thick)
        }
    }

    // MARK: - Det man själv spelar

    /// Nedtryckta tangenter visas vid markören: grönt om det är rätt, rött om det är fel.
    private func drawPressedKeys(in ctx: inout GraphicsContext) {
        for (pitch, correct) in view.held.sorted(by: { $0.key < $1.key }) {
            let place = notation.placement(ofPitch: pitch)
            var ledgers = Path()
            addLedgers(for: place.position, clef: place.clef, x: playheadX, to: &ledgers)
            ctx.stroke(ledgers, with: .color(lineColor), lineWidth: 1)

            let color = correct ? Palette.correct : Palette.wrong
            let center = CGPoint(x: playheadX, y: y(place.position, place.clef))
            let r = sp * 0.95
            ctx.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)),
                     with: .color(color.opacity(0.35)))
            drawHead(.quarter, at: center, style: Style(color: color, opacity: 1, current: false), in: &ctx)

            // En svart tangent visas alltid med sitt förtecken.
            if place.spelled.alter != 0 {
                let sign: Accidental = place.spelled.alter > 0 ? .sharp : .flat
                drawAccidental(sign, at: CGPoint(x: playheadX - sp * 1.35, y: center.y), color: color, in: &ctx)
            }

            let label = Text(view.naming.name(for: place.spelled))
                .font(.system(size: max(10, sp * 1.25), weight: .heavy, design: .rounded))
                .foregroundColor(.white)
            let resolved = ctx.resolve(label)
            let box = resolved.measure(in: CGSize(width: 60, height: 40))
            let bubble = CGRect(x: playheadX + sp * 1.1, y: center.y - box.height / 2 - 1, width: box.width + 8, height: box.height + 2)
            ctx.fill(Path(roundedRect: bubble, cornerRadius: 4), with: .color(color))
            ctx.draw(resolved, at: CGPoint(x: bubble.midX, y: bubble.midY))
        }
    }
}
