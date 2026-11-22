// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "telnyx-kit",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "TelnyxKit",
            targets: ["TelnyxKit"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.115.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", "3.0.0" ..< "6.0.0"),
    ],
    targets: [
        .target(
            name: "TelnyxKit",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "Crypto", package: "swift-crypto"),
            ]
        ),
        .testTarget(
            name: "TelnyxKitTests",
            dependencies: [
                "TelnyxKit",
                .product(name: "VaporTesting", package: "vapor"),
                .product(name: "Crypto", package: "swift-crypto"),
            ]
        ),
    ]
)
