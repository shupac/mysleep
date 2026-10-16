// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "SleepCore", platforms: [.macOS(.v14), .iOS(.v17), .watchOS(.v10)],
    products: [.library(name: "SleepCore", targets: ["SleepCore"])],
    targets: [
        .target(name: "SleepCore", path: "Core"),
        .testTarget(name: "SleepCoreTests", dependencies: ["SleepCore"], path: "Tests",
                    resources: [.copy("Fixtures")])
    ], swiftLanguageModes: [.v5])
