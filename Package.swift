// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClipNest",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ClipNest",
            path: "ClipNest",
            exclude: ["Info.plist", "ClipNest.entitlements", "Assets.xcassets"],
            linkerSettings: [.linkedFramework("Carbon")]
        ),
    ]
)
