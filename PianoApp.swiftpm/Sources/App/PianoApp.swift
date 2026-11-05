import SwiftUI

@main
@MainActor
struct PianoApp: App {
    @State private var midi = MIDIManager()
    @State private var store = SongStore()
    @State private var settings = AppSettings()

    init() {
        // Starta ljudmotorn direkt så att första tonen inte dröjer.
        SoundEngine.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environment(midi)
                .environment(store)
                .environment(settings)
                .onAppear { SoundEngine.shared.volume = Float(settings.volume) }
                .onChange(of: settings.volume) { _, v in SoundEngine.shared.volume = Float(v) }
        }
    }
}
