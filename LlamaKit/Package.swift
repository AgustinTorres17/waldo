// swift-tools-version: 5.9
import PackageDescription

// The official llama.cpp XCFramework (RESEARCH §1.4), pinned to the build that
// semver release v0.5.0 maps to. To upgrade: read the libllama API changelog
// (ggml-org/llama.cpp#9289), update URL + checksum, rebuild clean.
let package = Package(
    name: "LlamaKit",
    platforms: [.macOS("13.3")],
    products: [
        .library(name: "llama", targets: ["llama"]),
    ],
    targets: [
        .binaryTarget(
            name: "llama",
            url: "https://github.com/ggml-org/llama.cpp/releases/download/b11146/llama-b11146-xcframework.zip",
            checksum: "1c306afe9fe68a90c4bdc74619d8558d6e0754f085deb105dd2d70293a9a964f"
        ),
    ]
)
