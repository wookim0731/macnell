// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Macnell",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "Macnell", path: "Sources/Macnell")
    ]
)
