// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "ScreenTaskMac",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "ScreenTaskMac", targets: ["ScreenTaskMac"])],
    targets: [
        .target(name: "ScreenTaskCore"),
        .executableTarget(name: "ScreenTaskMac", dependencies: ["ScreenTaskCore"], resources: [.copy("Resources")]),
        .executableTarget(name: "ScreenTaskCoreTests", dependencies: ["ScreenTaskCore"], path: "Tests/ScreenTaskCoreTests")
    ])
