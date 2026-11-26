// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Dicteer",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Dicteer",
            path: "Sources/Dicteer",
            swiftSettings: [
                // A menu bar app is main-thread work almost everywhere, so default to the main actor.
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
            ]
        ),
    ]
)
