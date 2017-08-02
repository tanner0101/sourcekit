// swift-tools-version:4.0
import PackageDescription

let package = Package(
    name: "SourceKit",
    products: [
        .library(name: "SourceKit", targets: ["SourceKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/tanner0101/csourcekit.git", from: "0.0.0"),
        .package(url: "https://github.com/vapor/bits.git", from: "1.0.0"),
    ],
    targets: [
        .target(name: "SourceKit", dependencies: ["Bits"]),
        .testTarget(name: "SourceKitTests", dependencies: ["SourceKit"]),
    ]
)
