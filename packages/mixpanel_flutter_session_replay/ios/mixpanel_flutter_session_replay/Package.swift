// swift-tools-version: 5.6
import PackageDescription

let package = Package(
    name: "mixpanel_flutter_session_replay",
    platforms: [
        .iOS("13.0")
    ],
    products: [
        .library(
            name: "mixpanel-flutter-session-replay",
            targets: ["mixpanel_flutter_session_replay"]
        )
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "mixpanel_flutter_session_replay",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ],
            path: "Sources/mixpanel_flutter_session_replay",
            resources: []
        )
    ]
)
