// swift-tools-version:5.1

import PackageDescription

let package = Package(
    name: "DynamicTransition",
    platforms: [
        .iOS(.v13)
    ],
    products: [
        .library(
            name: "DynamicTransition",
            targets: ["DynamicTransition"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/lkzhao/BaseToolbox", from: "0.1.0"),
        .package(url: "https://github.com/lkzhao/YetAnotherAnimationLibrary", from: "1.6.0"),
        .package(url: "https://github.com/kylebshr/ScreenCorners", from: "1.0.1"),
    ],
    targets: [
        .target(
            name: "DynamicTransition",
            dependencies: ["BaseToolbox", "ScreenCorners", "YetAnotherAnimationLibrary"]
        )
    ]
)
