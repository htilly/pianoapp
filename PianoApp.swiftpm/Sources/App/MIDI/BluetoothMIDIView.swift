import SwiftUI
import CoreAudioKit

/// Apples inbyggda vy för att hitta och ansluta Bluetooth-MIDI-enheter.
struct BluetoothMIDIView: UIViewControllerRepresentable {
    var onDone: () -> Void

    func makeUIViewController(context: Context) -> UINavigationController {
        let central = CABTMIDICentralViewController()
        central.title = "Bluetooth-MIDI"
        central.navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: context.coordinator,
            action: #selector(Coordinator.done)
        )
        return UINavigationController(rootViewController: central)
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onDone: onDone) }

    final class Coordinator: NSObject {
        let onDone: () -> Void
        init(onDone: @escaping () -> Void) { self.onDone = onDone }
        @objc func done() { onDone() }
    }
}
