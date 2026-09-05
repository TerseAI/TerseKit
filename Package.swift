// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "TerseSwift",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "TerseKit", targets: ["TerseKit"]),
        .library(name: "TerseUI", targets: ["TerseUI"]),
    ],
    targets: [
        .target(name: "TerseKit"),
        .target(name: "TerseUI", dependencies: ["TerseKit"]),
        .testTarget(name: "TerseKitTests", dependencies: ["TerseKit", "TerseUI"]),
    ]
)
