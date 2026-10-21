// swift-tools-version: 6.2
// SwiftPM requires this exact filename; every other file uses kebab-case.
import PackageDescription

let package = Package(
  name: "Tot",
  platforms: [.macOS(.v26)],
  products: [.library(name: "TotCore", targets: ["TotCore"])],
  // Tests only: pins Sparkle's version ordering for date-based releases. The app links it via project.yml.
  dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")],
  targets: [
    .target(name: "TotCore", path: "sources/tot-core", linkerSettings: [.linkedLibrary("sqlite3")]),
    .testTarget(
      name: "TotCoreTests", dependencies: ["TotCore", .product(name: "Sparkle", package: "Sparkle")],
      path: "tests/tot-core-tests"),
  ]
)
