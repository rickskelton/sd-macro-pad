// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SDMacroPads",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "SDPadKit", targets: ["SDPadKit"]),
        .executable(name: "sdpad", targets: ["sdpad"]),
        .executable(name: "SDPadApp", targets: ["SDPadApp"]),
    ],
    targets: [
        .target(name: "SDPadKit"),
        .executableTarget(name: "sdpad", dependencies: ["SDPadKit"]),
        .executableTarget(name: "SDPadApp", dependencies: ["SDPadKit"]),
    ]
)
