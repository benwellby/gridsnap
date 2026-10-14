// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "GridSnap",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(name: "GridSnap", path: "Sources/GridSnap")
    ],
    swiftLanguageModes: [.v5]
)
