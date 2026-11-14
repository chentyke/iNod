// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NodeSeekCore",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "NodeSeekCore", targets: ["NodeSeekCore"]),
        .library(name: "NodeSeekClient", targets: ["NodeSeekClient"])
    ],
    targets: [
        .target(name: "NodeSeekCore"),
        .target(name: "NodeSeekClient", dependencies: ["NodeSeekCore"]),
        .testTarget(name: "NodeSeekCoreTests", dependencies: ["NodeSeekCore"], resources: [.copy("Fixtures")]),
        .testTarget(name: "NodeSeekClientTests", dependencies: ["NodeSeekClient", "NodeSeekCore"])
    ]
)
