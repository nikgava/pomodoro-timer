// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Pomodoro",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PomodoroCore", targets: ["PomodoroCore"]),
        .executable(name: "Pomodoro", targets: ["Pomodoro"])
    ],
    targets: [
        .target(name: "PomodoroCore"),
        .executableTarget(
            name: "Pomodoro",
            dependencies: ["PomodoroCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("CoreAudio")
            ]
        ),
        .testTarget(
            name: "PomodoroCoreTests",
            dependencies: ["PomodoroCore"],
            exclude: ["StandaloneRunner.swift"]
        )
    ],
    swiftLanguageModes: [.v6]
)
