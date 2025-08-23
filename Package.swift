// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ohmy408",
    platforms: [
        .iOS(.v13)
    ],
    products: [
        .library(
            name: "ohmy408",
            targets: ["ohmy408"]),
    ],
    dependencies: [
        .package(url: "https://github.com/SnapKit/SnapKit.git", from: "5.6.0"),
        .package(url: "https://github.com/JiongXing/PhotoBrowser.git", from: "3.1.0"),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.0")
    ],
    targets: [
        .target(
            name: "ohmy408",
            dependencies: [
                "SnapKit",
                .product(name: "JXPhotoBrowser", package: "PhotoBrowser"),
                "ZIPFoundation"
            ],
            path: "ohmy408"),
        .testTarget(
            name: "ohmy408Tests",
            dependencies: ["ohmy408"])
    ]
) 