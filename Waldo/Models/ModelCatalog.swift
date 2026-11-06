import Foundation

/// The prompt format a model family expects (RESEARCH §9.2: written in Swift,
/// not through llama_chat_apply_template, which can't turn Qwen3.5 thinking off).
enum PromptFamily: Sendable {
    case qwen35
}

/// A curated GGUF model (RESEARCH §2.5). URLs are pinned to a Hugging Face commit
/// and verified with SHA-256, so the file can't change under us.
struct ModelInfo: Identifiable, Sendable, Equatable {
    let id: String
    let name: String
    let summary: String
    let repo: String
    let revision: String
    let fileName: String
    let sizeBytes: Int64
    let sha256: String
    let family: PromptFamily
    /// Physical memory below which this model isn't recommended.
    let minimumMemoryGB: Int
    /// The vision projector (mmproj) that lets this model read captures in chats.
    var visionID: String? = nil
    /// The name on Hugging Face when it differs from `fileName` (every repo's
    /// projector is "mmproj-F16.gguf", so the local copy gets the model's name).
    var remoteFileName: String? = nil

    var downloadURL: URL {
        URL(string: "https://huggingface.co/\(repo)/resolve/\(revision)/\(remoteFileName ?? fileName)")!
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }
}

enum ModelCatalog {
    static let qwen35_4B = ModelInfo(
        id: "qwen3.5-4b-q4_k_m",
        name: "Qwen3.5 4B",
        summary: "Best quality. Recommended for Macs with 16 GB of memory or more.",
        repo: "unsloth/Qwen3.5-4B-GGUF",
        revision: "e87f176479d0855a907a41277aca2f8ee7a09523",
        fileName: "Qwen3.5-4B-Q4_K_M.gguf",
        sizeBytes: 2_740_937_888,
        sha256: "00fe7986ff5f6b463e62455821146049db6f9313603938a70800d1fb69ef11a4",
        family: .qwen35,
        minimumMemoryGB: 16,
        visionID: "qwen3.5-4b-mmproj-f16"
    )

    static let qwen35_2B = ModelInfo(
        id: "qwen3.5-2b-q5_k_m",
        name: "Qwen3.5 2B",
        summary: "Lighter and faster, lower quality. For Macs with 8 GB of memory.",
        repo: "unsloth/Qwen3.5-2B-GGUF",
        revision: "f6d5376be1edb4d416d56da11e5397a961aca8ae",
        fileName: "Qwen3.5-2B-Q5_K_M.gguf",
        sizeBytes: 1_435_238_656,
        sha256: "1885b3a9195f8cc09da9a7a7a75afdc1e8d5cbf9fc4a499c3961dddea37098ac",
        family: .qwen35,
        minimumMemoryGB: 8,
        visionID: "qwen3.5-2b-mmproj-f16"
    )

    static let all = [qwen35_4B, qwen35_2B]

    static let qwen35_4BVision = ModelInfo(
        id: "qwen3.5-4b-mmproj-f16",
        name: "Qwen3.5 4B Vision",
        summary: "Lets Qwen3.5 4B read the captures you add to chats.",
        repo: "unsloth/Qwen3.5-4B-GGUF",
        revision: "e87f176479d0855a907a41277aca2f8ee7a09523",
        fileName: "Qwen3.5-4B-mmproj-F16.gguf",
        sizeBytes: 672_423_616,
        sha256: "cd88edcf8d031894960bb0c9c5b9b7e1fea6ebee02b9f7ce925a00d12891f864",
        family: .qwen35,
        minimumMemoryGB: 16,
        remoteFileName: "mmproj-F16.gguf"
    )

    static let qwen35_2BVision = ModelInfo(
        id: "qwen3.5-2b-mmproj-f16",
        name: "Qwen3.5 2B Vision",
        summary: "Lets Qwen3.5 2B read the captures you add to chats.",
        repo: "unsloth/Qwen3.5-2B-GGUF",
        revision: "f6d5376be1edb4d416d56da11e5397a961aca8ae",
        fileName: "Qwen3.5-2B-mmproj-F16.gguf",
        sizeBytes: 668_227_264,
        sha256: "7035e9cb8d7c6a9681d07eef9a364783e86ea4cd73faab2eabb4f43a101830c7",
        family: .qwen35,
        minimumMemoryGB: 8,
        remoteFileName: "mmproj-F16.gguf"
    )

    /// Vision projectors: downloaded on their own, used with their model.
    static let projectors = [qwen35_4BVision, qwen35_2BVision]

    static func model(id: String) -> ModelInfo? {
        all.first { $0.id == id }
    }

    static func vision(for model: ModelInfo) -> ModelInfo? {
        projectors.first { $0.id == model.visionID }
    }

    /// The best model this Mac has enough memory for.
    static var recommended: ModelInfo {
        let memoryGB = Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824)
        return all.first { memoryGB >= $0.minimumMemoryGB } ?? qwen35_2B
    }

    /// ~/Library/Application Support/Waldo/Models
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Waldo/Models", isDirectory: true)
    }

    static func fileURL(for model: ModelInfo) -> URL {
        directory.appendingPathComponent(model.fileName)
    }

    static func isInstalled(_ model: ModelInfo) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(for: model).path)
    }
}
