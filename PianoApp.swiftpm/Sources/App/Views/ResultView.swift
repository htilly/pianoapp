import SwiftUI

struct ResultView: View {
    let score: Score
    let title: String
    let speed: Double
    var onAgain: () -> Void
    var onSlower: () -> Void
    var onDone: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            Text(headline)
                .font(.system(size: 40, weight: .heavy, design: .rounded))
                .multilineTextAlignment(.center)
            Text(title)
                .font(.title3)
                .foregroundStyle(.secondary)

            if score.mode != .listen {
                StarsView(stars: score.stars, size: 54)

                HStack(spacing: 28) {
                    stat("\(Int((score.accuracy * 100).rounded())) %", "Träffsäkerhet")
                    stat("\(score.hits)", "Rätt")
                    if score.mode == .playAlong { stat("\(score.misses)", "Missade") }
                    stat("\(score.wrong)", "Fel tangent")
                    stat("\(score.bestStreak)", "Bästa svit")
                }

                Text(tip)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            HStack(spacing: 16) {
                Button(action: onAgain) {
                    Label("Spela igen", systemImage: "arrow.counterclockwise")
                        .font(.title3.bold()).padding(.horizontal, 8).padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)

                if score.mode != .listen && score.stars < 3 && speed > 0.3 {
                    Button(action: onSlower) {
                        Label("Lite långsammare", systemImage: "tortoise.fill")
                            .font(.title3).padding(.horizontal, 8).padding(.vertical, 4)
                    }
                    .buttonStyle(.bordered)
                }

                Button(action: onDone) {
                    Label("Välj ny låt", systemImage: "music.note.list")
                        .font(.title3).padding(.horizontal, 8).padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(30)
    }

    private var headline: String {
        if score.mode == .listen { return "Låten är slut 🎶" }
        switch score.stars {
        case 3: return "Fantastiskt! 🎉"
        case 2: return "Riktigt bra! 👏"
        case 1: return "Bra kämpat! 💪"
        default: return "Bra försök! 🙂"
        }
    }

    private var tip: String {
        switch score.stars {
        case 3:
            return speed < 1 ? "Prova att höja tempot en bit nästa gång!" : "Du kan den här! Prova Spela med-läget eller en ny låt."
        case 2:
            return "Nästan perfekt. Loopa det svåra stället några gånger."
        default:
            return "Sänk tempot och öva en hand i taget – det är så proffsen gör."
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title.bold().monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}
