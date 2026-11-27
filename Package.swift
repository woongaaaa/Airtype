// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Airtype",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AirtypeCore", targets: ["AirtypeCore"]),
        .executable(name: "Airtype", targets: ["AirtypeApp"]),
        .executable(name: "airtype-replay", targets: ["AirtypeReplay"]),
        .executable(name: "vision-export", targets: ["VisionExport"])
    ],
    targets: [
        .target(name: "AirtypeCore"),
        .executableTarget(name: "AirtypeApp", dependencies: ["AirtypeCore"]),
        .executableTarget(name: "AirtypeReplay", dependencies: ["AirtypeCore"]),
        .executableTarget(name: "VisionExport", dependencies: ["AirtypeCore"]),
        .testTarget(name: "AirtypeCoreTests", dependencies: ["AirtypeCore"])
    ],
    swiftLanguageModes: [.v5]
)
