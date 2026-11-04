// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FloadAttribution",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "FloadAttribution", targets: ["FloadAttribution"]),
    ],
    targets: [
        .target(
            name: "FloadAttribution",
            resources: [.copy("Resources/PrivacyInfo.xcprivacy")],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .testTarget(
            name: "FloadAttributionTests",
            dependencies: ["FloadAttribution"],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
    ]
)
