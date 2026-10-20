// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "EconomixCore",
    defaultLocalization: "tr",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [
        .library(name: "EconomixCore", targets: ["EconomixCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/CoreOffice/CoreXLSX.git", .upToNextMinor(from: "0.14.2")),
    ],
    targets: [
        .target(name: "EconomixCore", dependencies: ["CoreXLSX"]),
        .testTarget(name: "EconomixCoreTests", dependencies: ["EconomixCore"], resources: [.copy("Fixtures")]),
    ]
)
