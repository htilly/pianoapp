// swift-tools-version: 5.9

// Pianoskola – en iPad-app som lär barn spela piano via MIDI.
//
// I Swift Playgrounds (iPad/Mac) och Xcode byggs hela appen.
// På Linux/CLI (`swift test`) byggs bara den plattformsoberoende kärnan
// i Sources/App/Core så att logiken kan testas utan Apples ramverk.

import PackageDescription

#if canImport(AppleProductTypes)
import AppleProductTypes

let package = Package(
    name: "Pianoskola",
    platforms: [
        .iOS("17.0")
    ],
    products: [
        .iOSApplication(
            name: "Pianoskola",
            targets: ["AppModule"],
            bundleIdentifier: "nu.tilly.pianoskola",
            displayVersion: "1.0",
            bundleVersion: "1",
            appIcon: .placeholder(icon: .star),
            accentColor: .presetColor(.blue),
            supportedDeviceFamilies: [
                .pad,
                .phone
            ],
            supportedInterfaceOrientations: [
                .landscapeRight,
                .landscapeLeft,
                .portrait,
                .portraitUpsideDown(.when(deviceFamilies: [.pad]))
            ],
            capabilities: [
                .bluetoothAlways(purposeString: "Pianoskola använder Bluetooth för att ansluta till ditt MIDI-piano.")
            ],
            appCategory: .education
        )
    ],
    targets: [
        .executableTarget(
            name: "AppModule",
            path: "Sources/App"
        )
    ]
)

#else

let package = Package(
    name: "Pianoskola",
    products: [
        .library(name: "PianoCore", targets: ["PianoCore"])
    ],
    targets: [
        .target(
            name: "PianoCore",
            path: "Sources/App/Core"
        ),
        .testTarget(
            name: "PianoCoreTests",
            dependencies: ["PianoCore"],
            path: "Tests/PianoCoreTests"
        )
    ]
)

#endif
