import Foundation

/// Which inference engine the user allows.
enum EngineMode: String, CaseIterable, Identifiable, Sendable {
    case auto
    case foundationModels
    case llamaCpp

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: "Auto"
        case .foundationModels: "Apple Intelligence only"
        case .llamaCpp: "llama.cpp only"
        }
    }

    var detail: String {
        switch self {
        case .auto: "Uses Apple's on-device model when available, otherwise a downloaded llama.cpp model."
        case .foundationModels: "Uses Apple's on-device model (macOS 26 with Apple Intelligence)."
        case .llamaCpp: "Uses a downloaded open model running locally with llama.cpp."
        }
    }
}
