// swift-tools-version: 5.9
// Entry point for the Agamon Swift package.
// Add this package as a dependency in Xcode: File → Add Package Dependencies → local path.
// SwiftTerm provides PTY + VT100 terminal emulation (the hardest part, solved).
// Sparkle 2 provides auto-update via GitHub Releases appcast.

import PackageDescription

let package = Package(
    name: "Agamon",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.2.2"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "Agamon",
            dependencies: [
                .product(name: "SwiftTerm", package: "SwiftTerm"),
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/Agamon",
            resources: [
                .copy("Resources/Themes"),
                .copy("Resources/AppIcon.icns"),
            ]
        ),
    ]
)
