// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "ThreadlineLocalCore",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "ThreadlineLocalCore", targets: ["ThreadlineLocalCore"])
    ],
    targets: [
        .target(
            name: "ThreadlineLocalCore",
            path: "RedditJSON",
            exclude: [
                "AppIcon60x60@2x.png",
                "AppIcon60x60@3x.png",
                "Assets.xcassets",
                "BrowseView.swift",
                "DesignSystem.swift",
                "DetailViews.swift",
                "ExploreView.swift",
                "FeedViews.swift",
                "Info.plist",
                "LibraryViews.swift",
                "LocalFeatureViews.swift",
                "LocalLibrary.swift",
                "LocalMultiredditStore.swift",
                "RedditClient.swift",
                "RedditJSON.entitlements",
                "RedditJSONApp.swift",
                "SystemIntegrations.swift"
            ],
            sources: ["Models.swift", "LocalFeatureModels.swift"]
        ),
        .testTarget(
            name: "ThreadlineLocalCoreTests",
            dependencies: ["ThreadlineLocalCore"]
        )
    ]
)
