// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "QuietTranslate",
    platforms: [.macOS(.v14)],
    targets: [.executableTarget(name: "QuietTranslate", resources: [.process("Assets")])]
)
