// swift-tools-version: 5.6
import PackageDescription

let package = Package(
    name: "mixpanel_flutter",
    platforms: [
        .iOS("13.0")
    ],
    products: [
        .library(
            name: "mixpanel-flutter",
            targets: ["mixpanel_flutter"]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/mixpanel/mixpanel-swift.git",
            exact: "6.5.1"
        ),
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "mixpanel_flutter",
            dependencies: [
                .product(name: "Mixpanel", package: "mixpanel-swift"),
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ],
            path: "Sources/mixpanel_flutter",
            resources: []
        )
    ]
)
