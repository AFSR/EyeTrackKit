// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "EyeTrackKit",
    platforms: [.iOS(.v16)],
    products: [
        .library(
            name: "EyeTrackKit",
            targets: ["EyeTrackKit"]),
    ],
    targets: [
        .target(
            name: "EyeTrackKit"),
        .testTarget(
            name: "EyeTrackKitTests",
            dependencies: ["EyeTrackKit"]),
    ],
    swiftLanguageVersions: [.v5]
)
