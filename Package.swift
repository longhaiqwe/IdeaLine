// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "IdeaLine",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "IdeaLine", targets: ["IdeaLine"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.2")],
    targets: [
        .executableTarget(name: "IdeaLine", dependencies: [.product(name: "Sparkle", package: "Sparkle")],
                          linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .testTarget(name: "IdeaLineTests", dependencies: ["IdeaLine"])
    ]
)
