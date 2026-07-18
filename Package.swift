// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "BrightnessFollow",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "BrightnessFollow", targets: ["BrightnessFollow"]),
    ],
    targets: [
        .target(
            name: "DisplayBridge",
            path: "Sources/DisplayBridge",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "BrightnessFollow",
            dependencies: ["DisplayBridge"],
            path: "Sources/BrightnessFollow",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("CoreDisplay"),
                .linkedFramework("IOKit"),
                .linkedFramework("DisplayServices"),
                .unsafeFlags(["-F/System/Library/PrivateFrameworks"]),
            ]
        ),
        .testTarget(
            name: "BrightnessFollowTests",
            dependencies: ["BrightnessFollow"],
            path: "Tests/BrightnessFollowTests"
        ),
    ],
    swiftLanguageModes: [.v5]
)
