// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Dochi",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Dochi",
            path: "Dochi"
        )
    ]
)
