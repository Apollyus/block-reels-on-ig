// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MyGramCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "MyGramCore", targets: ["MyGramCore"]),
    ],
    targets: [
        .target(
            name: "MyGramCore",
            resources: [
                .copy("Resources/filters.json"),
                .copy("Resources/filters.js"),
            ]
        ),
        .testTarget(name: "MyGramCoreTests", dependencies: ["MyGramCore"]),
    ]
)
