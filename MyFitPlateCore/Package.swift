// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MyFitPlateCore",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10),
        .macOS(.v14)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "MyFitPlateCore",
            targets: ["MyFitPlateCore"]),
        // The few types the app shares with its widget and Live Activity extensions. Keeping it
        // separate keeps those extensions small; Core re-exports it for the app.
        .library(
            name: "MyFitPlateShared",
            targets: ["MyFitPlateShared"]),
    ],
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.7.0")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "MyFitPlateShared",
            resources: [
                .copy("PrivacyInfo.xcprivacy")
            ]
        ),
        .target(
            name: "MyFitPlateCore",
            dependencies: [
                "MyFitPlateShared",
                .product(name: "SwiftSoup", package: "SwiftSoup")
            ],
            resources: [
                .copy("PrivacyInfo.xcprivacy")
            ]
        ),
        .testTarget(
            name: "MyFitPlateCoreTests",
            dependencies: ["MyFitPlateCore", "MyFitPlateShared"]),
    ]
)
