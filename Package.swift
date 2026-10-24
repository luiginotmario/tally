// swift-tools-version: 6.2
import PackageDescription

let approachable: [SwiftSetting] = [
  .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
  .enableUpcomingFeature("InferIsolatedConformances"),
]

let package = Package(
  name: "Tally",
  platforms: [.macOS(.v14)],
  targets: [
    // Pure logic: hook payloads, the board of keys, device packets, key artwork.
    .target(name: "TallyKit", swiftSettings: approachable),
    // The menu bar app and the `tally` command, in one binary.
    .executableTarget(
      name: "Tally",
      dependencies: ["TallyKit"],
      swiftSettings: approachable + [.defaultIsolation(MainActor.self)]
    ),
    .testTarget(name: "TallyKitTests", dependencies: ["TallyKit"], swiftSettings: approachable),
  ]
)
