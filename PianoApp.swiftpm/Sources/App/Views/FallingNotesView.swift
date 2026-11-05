import SwiftUI

/// Noterna faller ner mot klaviaturen. När en not når linjen längst ner ska den spelas.
struct FallingNotesView: View {
    let song: Song
    let layout: KeyboardLayout
    let time: Double
    let results: [NoteResult]
    let targets: [Bool]
    let pixelsPerSecond: Double
    let naming: NoteNaming
    let showNames: Bool
    let loop: ClosedRange<Double>?
    let loopStartCandidate: Double?
    let isWaiting: Bool

    var body: some View {
        Canvas { ctx, size in
            let hitY = size.height - 2
            let pps = pixelsPerSecond
            let ahead = Double(hitY) / pps

            // Bakgrund med ett band per C-oktav.
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Palette.background))
            for p in layout.lowest...layout.highest where p % 12 == 0 {
                if let f = layout.keyFrame(p) {
                    var line = Path()
                    line.move(to: CGPoint(x: f.x, y: 0))
                    line.addLine(to: CGPoint(x: f.x, y: size.height))
                    ctx.stroke(line, with: .color(.white.opacity(0.08)), lineWidth: 1)
                }
            }

            // Taktstreck.
            for (i, bt) in song.barTimes.enumerated() where bt >= time - 0.5 && bt <= time + ahead {
                let y = hitY - CGFloat((bt - time) * pps)
                var line = Path()
                line.move(to: CGPoint(x: 0, y: y))
                line.addLine(to: CGPoint(x: size.width, y: y))
                ctx.stroke(line, with: .color(.white.opacity(0.12)), lineWidth: 1)
                ctx.draw(Text("\(i + 1)").font(.caption2).foregroundColor(.white.opacity(0.35)),
                         at: CGPoint(x: 14, y: y - 8))
            }

            // Loop-markering.
            if let loop {
                let y1 = hitY - CGFloat((loop.lowerBound - time) * pps)
                let y2 = hitY - CGFloat((loop.upperBound - time) * pps)
                ctx.fill(Path(CGRect(x: 0, y: y2, width: size.width, height: y1 - y2)),
                         with: .color(.yellow.opacity(0.06)))
                for y in [y1, y2] {
                    var line = Path()
                    line.move(to: CGPoint(x: 0, y: y))
                    line.addLine(to: CGPoint(x: size.width, y: y))
                    ctx.stroke(line, with: .color(.yellow.opacity(0.6)), style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                }
            } else if let a = loopStartCandidate {
                let y = hitY - CGFloat((a - time) * pps)
                var line = Path()
                line.move(to: CGPoint(x: 0, y: y))
                line.addLine(to: CGPoint(x: size.width, y: y))
                ctx.stroke(line, with: .color(.yellow.opacity(0.8)), style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
            }

            // Noter.
            for (i, n) in song.notes.enumerated() {
                if n.start > time + ahead { break }
                if n.end < time - 0.3 { continue }
                guard let f = layout.keyFrame(n.pitch) else { continue }
                let yBottom = hitY - CGFloat((n.start - time) * pps)
                let h = max(10, CGFloat(n.duration * pps) - 3)
                let inset: CGFloat = n.pitch.isBlackKey ? 0 : 2
                let rect = CGRect(x: f.x + inset, y: yBottom - h, width: f.width - inset * 2, height: h)
                let path = Path(roundedRect: rect, cornerRadius: min(6, f.width / 3))

                let target = i < targets.count && targets[i]
                let result = i < results.count ? results[i] : .pending
                var color = Palette.color(for: n.part)
                var opacity = 1.0
                if !target { opacity = 0.35 }
                switch result {
                case .hit: color = Palette.correct
                case .missed: color = Color(white: 0.35); opacity = 0.7
                default: break
                }
                if n.pitch.isBlackKey && target && result == .pending { opacity = 0.85 }
                ctx.fill(path, with: .color(color.opacity(opacity)))
                if target {
                    ctx.stroke(path, with: .color(.white.opacity(result == .hit ? 0.9 : 0.35)), lineWidth: 1.5)
                }

                if showNames && rect.height >= 20 && f.width >= 14 {
                    let fontSize = min(15, f.width * 0.55)
                    let label = Text(naming.name(for: n.pitch))
                        .font(.system(size: fontSize, weight: .heavy, design: .rounded))
                        .foregroundColor(.white.opacity(target ? 1 : 0.6))
                    ctx.draw(label, at: CGPoint(x: rect.midX, y: rect.maxY - fontSize * 0.8))
                }
            }

            // Träfflinje.
            var hit = Path()
            hit.move(to: CGPoint(x: 0, y: hitY))
            hit.addLine(to: CGPoint(x: size.width, y: hitY))
            ctx.stroke(hit, with: .color((isWaiting ? Color.yellow : Color.white).opacity(0.8)), lineWidth: 3)
        }
    }
}
