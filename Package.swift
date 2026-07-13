// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Cleanova",
    platforms: [.macOS(.v14)],
    dependencies: [
        // 원격 오류/크래시 수집. 실제 배포 전 DSN을 발급받아 설정하세요.
        .package(url: "https://github.com/getsentry/sentry-cocoa", from: "9.21.0"),
        // 웹 배포용 자동 업데이트 프레임워크.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "Cleanova",
            dependencies: [
                .product(name: "Sentry", package: "sentry-cocoa"),
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/Cleanova",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreServices"),
            ]
        )
    ]
)
