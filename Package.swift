// swift-tools-version: 6.3
import PackageDescription

func swiftSettings(_ settings: PackageDescription.SwiftSetting...) -> [PackageDescription
  .SwiftSetting]
{
  [
    .swiftLanguageMode(.v6),
    .strictMemorySafety(),
    .defaultIsolation(.none),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("ImmutableWeakCaptures"),
    .enableUpcomingFeature("InternalImportsByDefault"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
  ] + settings
}

let package = Package(
  name: "swift-tui-terminal-view",
  platforms: [.macOS(.v15), .iOS(.v18)],
  products: [
    .library(name: "SwiftTUITerminalView", targets: ["SwiftTUITerminalView"])
  ],
  dependencies: [
    .package(url: "https://github.com/SwiftTUI/swift-tui.git", exact: "0.13.0"),
    .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.18.0"),
    .package(url: "https://github.com/swiftlang/swift-docc-plugin.git", from: "1.5.0"),
  ],
  targets: [
    .target(
      name: "SwiftTUITerminalEmulation",
      dependencies: [
        .product(name: "SwiftTUIRuntime", package: "swift-tui"),
        .product(name: "SwiftTerm", package: "SwiftTerm"),
      ],
      swiftSettings: swiftSettings()
    ),
    .target(
      name: "SwiftTUITerminalView",
      dependencies: [
        .product(name: "SwiftTUIRuntime", package: "swift-tui"),
        .product(name: "SwiftTUIPTYPrimitives", package: "swift-tui"),
        "SwiftTUITerminalEmulation",
      ],
      swiftSettings: swiftSettings()
    ),
    .testTarget(
      name: "SwiftTUITerminalViewTests",
      dependencies: [
        "SwiftTUITerminalView",
        .product(name: "SwiftTUITestSupport", package: "swift-tui"),
        .product(name: "SwiftTUIRuntime", package: "swift-tui"),
      ],
      swiftSettings: swiftSettings()
    ),
  ]
)
