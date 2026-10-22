// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LiveGraded",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "LiveGraded",
            targets: ["LiveGraded"]
        )
    ],
    targets: [
        .target(
            name: "LiveGraded",
            path: "Sources"
        ),
        .testTarget(
            name: "LiveGradedTests",
            dependencies: ["LiveGraded"],
            path: "Tests"
        )
    ]
)
