import Foundation

/// A user-defined set of preferences (tone, guidelines, examples) layered on top
/// of every task: Translate / Correct, Rephrase and the hotkeys.
struct CustomMode: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var guidelines = ""
    var likedExamples = ""
    var dislikedExamples = ""

    /// Per-field limits keep the prompt within Apple's 4,096-token context.
    static let maxNameLength = 40
    static let maxFieldLength = 1_000

    var isEmpty: Bool {
        [guidelines, likedExamples, dislikedExamples].allSatisfy {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    static let starters = [
        CustomMode(id: UUID(uuidString: "0B7C1E5A-6F4D-4E21-9A3B-5D2C8E1F7A01")!, name: "Work",
                   guidelines: "Professional but friendly, like a message to a coworker on Slack. Clear and direct. No slang or profanity."),
        CustomMode(id: UUID(uuidString: "0B7C1E5A-6F4D-4E21-9A3B-5D2C8E1F7A02")!, name: "Friends",
                   guidelines: "Casual and relaxed, like texting a friend. Contractions and everyday words. Never formal or stiff."),
    ]
}

/// The mode and language to use in one app instead of the defaults. A nil
/// `modeID` means no mode there; a nil `language` means the default language.
struct AppRule: Codable, Hashable, Identifiable, Sendable {
    var bundleID: String
    var modeID: UUID?
    /// Optional, so rules saved before it existed still decode.
    var language: TargetLanguage?

    var id: String { bundleID }
}
