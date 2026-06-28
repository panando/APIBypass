// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "APIBypass",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "APIBypass", targets: ["APIBypass"])
    ],
    dependencies: [
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),
        .package(url: "https://github.com/LebJe/TOMLKit.git", from: "0.5.0"),
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "CodexRouterCore",
            dependencies: [
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "TOMLKit", package: "TOMLKit"),
            ],
            path: "CodexRouterCore"
        ),
        .executableTarget(
            name: "APIBypass",
            dependencies: [
                "CodexRouterCore",
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "HummingbirdRouter", package: "hummingbird")
            ],
            path: "APIBypass",
            exclude: ["CHANGES.md"]
        ),
        .testTarget(
            name: "APIBypassTests",
            dependencies: ["APIBypass"],
            path: "APIBypassTests"
        )
    ]
)
