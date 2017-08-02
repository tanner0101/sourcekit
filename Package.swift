// swift-tools-version:4.0
import PackageDescription

let package = Package(
    name: "SourceKit",
    products: [
        .library(name: "SourceKit", targets: ["SourceKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/tanner0101/csourcekit.git", from: "0.0.0"),
    ],
    targets: [
        .target(name: "SourceKit"),
        .testTarget(name: "SourceKitTests", dependencies: ["SourceKit"]),
    ]
)
