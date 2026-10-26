// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "LectureRecorder",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "LectureCore", targets: ["LectureCore"]),
        .executable(name: "LectureRecorder", targets: ["LectureRecorder"]),
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", exact: "1.1.1"),
    ],
    targets: [
        .target(name: "LectureCore", dependencies: [.product(name: "WhisperKit", package: "argmax-oss-swift")], resources: [.process("Resources")]),
        .executableTarget(
            name: "LectureRecorder",
            dependencies: ["LectureCore"]
        ),
        .executableTarget(name: "LectureCoreChecks", dependencies: ["LectureCore"], path: "Tests/LectureCoreTests", exclude: ["README.md"]),
    ],
    swiftLanguageModes: [.v6]
)
