// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Cleanova",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Cleanova",
            path: "Sources/Cleanova",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreServices"),
            ]
        )
    ]
)
