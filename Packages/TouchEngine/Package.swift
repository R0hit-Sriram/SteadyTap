// swift-tools-version:5.9
import PackageDescription

// The touch-interpretation engine. Pure Swift + Foundation, no UIKit, so it can be
// unit-tested with `swift test` on a Mac (or in a Linux Swift container).
let package = Package(
    name: "TouchEngine",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "TouchEngine", targets: ["TouchEngine"])],
    targets: [
        .target(name: "TouchEngine", resources: [.copy("Resources/words.txt")]),
        .testTarget(name: "TouchEngineTests", dependencies: ["TouchEngine"]),
    ]
)
