// swift-tools-version: 5.9
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
            exact: "6.4.0"
        )
    ],
    targets: [
        .target(
            name: "mixpanel_flutter",
            dependencies: [
                .product(name: "Mixpanel", package: "mixpanel-swift")
            ],
            path: "Sources/mixpanel_flutter",
            resources: []
        )
    ]
)
