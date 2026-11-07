// swift-tools-version: 6.0
import Foundation
import PackageDescription

// The owner's libmtp fork (with MTPZ), installed by scripts/build-libmtp.sh.
let libmtpPrefix = ProcessInfo.processInfo.environment["LIBMTP_PREFIX"]
    ?? NSHomeDirectory() + "/.local/opt/libmtp-zune"

let package = Package(
    name: "ZuneManager",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ZuneManager", targets: ["ZuneManager"]),
        .executable(name: "zune-probe", targets: ["zune-probe"]),
    ],
    targets: [
        .systemLibrary(name: "CLibMTP", path: "Sources/CLibMTP"),
        .target(
            name: "ZuneKit",
            dependencies: ["CLibMTP"],
            swiftSettings: [.unsafeFlags(["-Xcc", "-I\(libmtpPrefix)/include"])],
            linkerSettings: [.unsafeFlags(["-L\(libmtpPrefix)/lib"]), .linkedLibrary("mtp")]
        ),
        .target(name: "ZuneTestSupport", dependencies: ["ZuneKit"]),
        .executableTarget(name: "ZuneManager", dependencies: ["ZuneKit"]),
        .executableTarget(name: "zune-probe", dependencies: ["ZuneKit", "ZuneTestSupport"]),
        // Run with scripts/test.sh (it supplies the Swift Testing paths).
        .testTarget(name: "ZuneKitTests", dependencies: ["ZuneKit", "ZuneTestSupport"]),
    ]
)
