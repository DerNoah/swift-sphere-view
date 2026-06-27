// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "swift-sphere-view",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "SphereView", targets: ["SphereView"]),
    ],
    targets: [
        .target(name: "SphereView"),
    ]
)
