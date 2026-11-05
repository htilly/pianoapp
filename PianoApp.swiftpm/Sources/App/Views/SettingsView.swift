import SwiftUI
import CoreMIDI

@MainActor
struct SettingsView: View {
    @Environment(MIDIManager.self) private var midi
    @Environment(AppSettings.self) private var settings
    @Environment(SongStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var showBluetooth = false

    var body: some View {
        @Bindable var settings = settings
        @Bindable var midi = midi
        NavigationStack {
            Form {
                Section {
                    TextField("Vad heter du?", text: $settings.playerName)
                } header: {
                    Text("Spelare")
                }

                Section {
                    if midi.sources.isEmpty {
                        Label("Inget piano hittat", systemImage: "pianokeys")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(midi.sources) { s in
                            Label {
                                Text(s.name)
                            } icon: {
                                Image(systemName: "circle.fill").foregroundStyle(.green)
                            }
                        }
                    }
                    Button {
                        showBluetooth = true
                    } label: {
                        Label("Anslut Bluetooth-piano …", systemImage: "dot.radiowaves.left.and.right")
                    }
                    Button {
                        midi.refresh()
                    } label: {
                        Label("Sök efter enheter igen", systemImage: "arrow.clockwise")
                    }
                    if let e = midi.lastError {
                        Text(e).foregroundStyle(.red)
                    }
                } header: {
                    Text("Piano (MIDI)")
                } footer: {
                    Text("USB: koppla pianot med en USB-kabel (USB-C, eller Apples Lightning-till-USB-kameraadapter) – det hittas automatiskt.\nBluetooth: slå på Bluetooth-MIDI på pianot och tryck på ”Anslut Bluetooth-piano”. Parkoppla INTE pianot under iPadens vanliga Bluetooth-inställningar.")
                }

                Section {
                    Picker("Appens toner spelas på", selection: $settings.soundOutput) {
                        ForEach(SoundOutput.allCases) { o in Text(o.label).tag(o) }
                    }
                    if midi.destinations.count > 1 {
                        Picker("Skicka till", selection: $midi.selectedDestinationID) {
                            Text("Första hittade").tag(MIDIUniqueID?.none)
                            ForEach(midi.destinations) { d in Text(d.name).tag(Optional(d.id)) }
                        }
                    }
                    VStack(alignment: .leading) {
                        Text("Volym i iPaden")
                        Slider(value: $settings.volume, in: 0...1)
                    }
                    Button {
                        testSound()
                    } label: {
                        Label("Testa ljudet", systemImage: "speaker.wave.2.fill")
                    }
                } header: {
                    Text("Ljud")
                } footer: {
                    Text("”Automatiskt” spelar komp och Lyssna-läget på pianot när det är anslutet, annars i iPaden. Det du själv spelar på pianot låter alltid från pianot.")
                }

                Section("Visning") {
                    Picker("Vid övning visas", selection: $settings.scoreDisplay) {
                        ForEach(ScoreDisplay.allCases) { d in Text(d.label).tag(d) }
                    }
                    Picker("Notnamn", selection: $settings.noteNaming) {
                        Text("Svenska (C D E F G A H)").tag(NoteNaming.swedish)
                        Text("Engelska (C D E F G A B)").tag(NoteNaming.english)
                    }
                    Toggle("Visa notnamn på noterna", isOn: $settings.showNoteNames)
                    Toggle("Visa notnamn på tangenterna", isOn: $settings.showKeyLabels)
                    VStack(alignment: .leading) {
                        Text("Hur snabbt noterna faller: \(Int(settings.fallSpeed))")
                        Slider(value: $settings.fallSpeed, in: 80...360, step: 10)
                    }
                }

                Section {
                    VStack(alignment: .leading) {
                        Text("Tidsmarginal: \(Int(settings.hitWindow * 1000)) ms")
                        Slider(value: $settings.hitWindow, in: 0.08...0.4, step: 0.01)
                    }
                } header: {
                    Text("Spela med")
                } footer: {
                    Text("Hur nära i tid man måste trycka för att det ska räknas som rätt. Större = lättare.")
                }

                Section("Låtar") {
                    Button("Lägg tillbaka exempel-låtarna") { store.restoreExamples() }
                }
            }
            .navigationTitle("Inställningar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Klar") { dismiss() }.bold()
                }
            }
            .sheet(isPresented: $showBluetooth, onDismiss: { midi.refresh() }) {
                BluetoothMIDIView { showBluetooth = false }
            }
        }
    }

    private func testSound() {
        let notes = [60, 64, 67, 72]
        let sendToPiano = midi.canSend && settings.soundOutput != .device
        let onDevice = !sendToPiano || settings.soundOutput == .both
        let midi = midi
        Task { @MainActor in
            for n in notes {
                if sendToPiano { midi.sendNoteOn(n, velocity: 90) }
                if onDevice { SoundEngine.shared.noteOn(n, velocity: 90) }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
            for n in notes {
                if sendToPiano { midi.sendNoteOff(n) }
                SoundEngine.shared.noteOff(n)
            }
        }
    }
}
