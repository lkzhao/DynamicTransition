// swift-tools-version:5.8

import PackageDescription

let package = Package(
    name: "DynamicTransition",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "DynamicTransition",
            targets: ["DynamicTransition"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/lkzhao/BaseToolbox", from: "0.6.0"),
        .package(url: "https://github.com/kylebshr/ScreenCorners", from: "1.0.1"),
        .package(url: "https://github.com/lkzhao/StateManaged", from: "0.1.0"),
        .package(url: "https://github.com/b3ll/Motion", from: "0.1.5"),
    ],
    targets: [
        .target(
            name: "DynamicTransition",
            dependencies: ["BaseToolbox", "ScreenCorners", "Motion", "StateManaged"]
        )
    ]
)
