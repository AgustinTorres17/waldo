// swift-tools-version: 6.0
import PackageDescription

// Build with `make run` (see Makefile): SwiftPM compiles, the Makefile wraps the
// binary in Waldo.app. Only Command Line Tools are needed; Xcode can still open
// this file if you want an IDE.
let package = Package(
    name: "Waldo",
    platforms: [.macOS("13.3")],
    dependencies: [
        .package(path: "Vendor/KeyboardShortcuts"),
        .package(path: "LlamaKit"),
    ],
    targets: [
        .executableTarget(
            name: "Waldo",
            dependencies: [
                "KeyboardShortcuts",
                .product(name: "llama", package: "LlamaKit"),
            ],
            path: "Waldo",
            linkerSettings: [
                // FoundationModels only exists on macOS 26+; weak-link so the app still launches on 13.3.
                .unsafeFlags(["-Xlinker", "-weak_framework", "-Xlinker", "FoundationModels"]),
                // llama.framework is copied into Waldo.app/Contents/Frameworks.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        ),
        .testTarget(
            name: "WaldoTests",
            dependencies: ["Waldo"],
            path: "WaldoTests"
        ),
    ]
)
