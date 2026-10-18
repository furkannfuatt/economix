// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "EcoomixCore",
    defaultLocalization: "tr",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [
        .library(name: "EcoomixCore", targets: ["EcoomixCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/CoreOffice/CoreXLSX.git", .upToNextMinor(from: "0.14.2")),
    ],
    targets: [
        .target(name: "EcoomixCore", dependencies: ["CoreXLSX"]),
        .testTarget(name: "EcoomixCoreTests", dependencies: ["EcoomixCore"], resources: [.copy("Fixtures")]),
    ]
)
