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
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.0.0")
    ],
    targets: [
        .executableTarget(
            name: "APIBypass",
            dependencies: [
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "HummingbirdRouter", package: "hummingbird")
            ],
            path: "APIBypass"
        ),
        .testTarget(
            name: "APIBypassTests",
            dependencies: ["APIBypass"],
            path: "APIBypassTests"
        )
    ]
)
