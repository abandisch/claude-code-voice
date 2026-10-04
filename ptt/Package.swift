// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Pardon",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "PardonKit"),
        .executableTarget(name: "Pardon", dependencies: ["PardonKit"]),
        .testTarget(name: "PardonKitTests", dependencies: ["PardonKit"]),
    ]
)
