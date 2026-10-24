// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "LectureRecorder",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "LectureCore", targets: ["LectureCore"]),
        .executable(name: "LectureRecorder", targets: ["LectureRecorder"]),
    ],
    targets: [
        .target(name: "LectureCore"),
        .executableTarget(
            name: "LectureRecorder",
            dependencies: ["LectureCore"]
        ),
        .executableTarget(name: "LectureCoreChecks", dependencies: ["LectureCore"], path: "Tests/LectureCoreTests", exclude: ["README.md"]),
    ],
    swiftLanguageModes: [.v6]
)
