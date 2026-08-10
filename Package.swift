// swift-tools-version:6.0
import PackageDescription
let package = Package(
  name: "RecBurn",
  platforms: [.macOS(.v15)],
  targets: [ .executableTarget(name: "RecBurn", path: "Sources/RecBurn",
             swiftSettings: [.unsafeFlags(["-parse-as-library"])]) ]
)
