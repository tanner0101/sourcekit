// swift-tools-version:3.1

import PackageDescription

let package = Package(
    name: "SourceKit",
    dependencies: [
    	.Package(url: "https://github.com/tanner0101/csourcekit.git", majorVersion: 0)
    ]
)
