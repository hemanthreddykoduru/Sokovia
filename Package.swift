// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Sokovia",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Sokovia", targets: ["Sokovia"]),
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "Sokovia",
            path: "Sources/Sokovia"
        ),
        .testTarget(
            name: "SokoviaTests",
            dependencies: ["Sokovia"],
            path: "Tests/SokoviaTests"
        ),
    ]
)
