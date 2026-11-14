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
            displayVersion: "2.0.0",
            bundleVersion: "20261114",
            appIcon: .asset("AppIcon"),
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
                .bluetoothAlways(purposeString: "Pianoskola använder Bluetooth för att ansluta till ditt MIDI-piano."),
                .microphone(purposeString: "Pianoskola lyssnar med mikrofonen på ditt piano för att höra vilka toner du spelar. Ljudet sparas eller skickas aldrig.")
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
