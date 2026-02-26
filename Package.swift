// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WhisperBar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "WhisperBar", targets: ["WhisperBar"])
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit", from: "0.9.0"),
    ],
    targets: [
        .executableTarget(
            name: "WhisperBar",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit"),
            ],
            path: "Sources/WhisperBar",
            // Carbon.framework is part of the macOS SDK and auto-links via `import Carbon`
            linkerSettings: [
                .linkedFramework("Carbon"),
            ]
        )
    ]
)
