// swift-tools-version:4.0
import PackageDescription

let package = Package(
    name: "SourceKit",
    products: [
        .library(name: "SourceKit", targets: ["SourceKit"]),
    ],
    dependencies: [
        .package(url: "../csourcekit", .branch("master")),
    ],
    targets: [
        .target(name: "SourceKit"),
        .testTarget(name: "SourceKitTests", dependencies: ["SourceKit"]),
    ]
)
