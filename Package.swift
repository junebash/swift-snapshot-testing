// swift-tools-version:6.0

import PackageDescription

let package = Package(
  name: "swift-snapshot-testing",
  platforms: [
    .iOS(.v16),
    .macOS(.v13),
    .tvOS(.v16),
    .watchOS(.v9),
  ],
  products: [
    .library(
      name: "SnapshotTesting",
      targets: ["SnapshotTesting"]
    ),
    .library(
      name: "InlineSnapshotTesting",
      targets: ["InlineSnapshotTesting"]
    ),
    .library(
      name: "SnapshotTestingCustomDump",
      targets: ["SnapshotTestingCustomDump"]
    ),
    // Transient home for the native-async, protocol-based engine during the migration.
    // Collapsed into `SnapshotTesting` at the flip; see the migration plan.
    .library(
      name: "SnapshotTestingAsync",
      targets: ["SnapshotTestingAsync"]
    ),
  ],
  dependencies: [
    .package(url: "https://github.com/pointfreeco/swift-custom-dump", from: "1.3.3"),
    .package(url: "https://github.com/swiftlang/swift-syntax", "509.0.0"..<"605.0.0"),
  ],
  targets: [
    .target(
      name: "SnapshotTesting"
    ),
    .testTarget(
      name: "SnapshotTestingTests",
      dependencies: [
        "SnapshotTesting"
      ],
      exclude: [
        "__Fixtures__",
        "__Snapshots__",
      ]
    ),
    .target(
      name: "InlineSnapshotTesting",
      dependencies: [
        "SnapshotTesting",
        "SnapshotTestingCustomDump",
        .product(name: "SwiftParser", package: "swift-syntax"),
        .product(name: "SwiftSyntax", package: "swift-syntax"),
        .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
      ]
    ),
    .testTarget(
      name: "InlineSnapshotTestingTests",
      dependencies: [
        "InlineSnapshotTesting"
      ]
    ),
    .target(
      name: "SnapshotTestingCustomDump",
      dependencies: [
        "SnapshotTesting",
        "SnapshotTestingAsync",
        .product(name: "CustomDump", package: "swift-custom-dump"),
      ]
    ),
    // The native-async, protocol-based engine. Built under Swift 6 language mode
    // while the legacy `SnapshotTesting` target stays on v5 and green. At the
    // Phase 4 flip these sources move into `SnapshotTesting` and this target is removed.
    .target(
      name: "SnapshotTestingAsync",
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .testTarget(
      name: "SnapshotTestingAsyncTests",
      dependencies: [
        "SnapshotTestingAsync",
        "SnapshotTestingCustomDump",
      ],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
  ],
  swiftLanguageModes: [.v5]
)
