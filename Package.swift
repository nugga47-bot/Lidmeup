// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Lidmeup",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Lidmeup",
            path: "Sources/Lidmeup",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreAudio"),
            ]
        ),
    ]
)
