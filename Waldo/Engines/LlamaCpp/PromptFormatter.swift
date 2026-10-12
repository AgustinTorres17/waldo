import Foundation

/// Renders system prompt, few-shot turns and the request exactly as the model's official Jinja template
/// would (RESEARCH §9.2), with thinking turned off.
enum PromptFormatter {
    static func format(_ request: GenerationRequest, family: PromptFamily) -> String {
        let (prefix, suffix) = parts(request, family: family)
        return prefix + suffix
    }

    /// `prefix` (system prompt and examples) is the same for every request with the
    /// same task and language, so the engine caches its evaluated state. It ends right
    /// before a special token, so tokenizing the parts separately matches the whole.
    static func parts(_ request: GenerationRequest, family: PromptFamily) -> (prefix: String, suffix: String) {
        switch family {
        case .qwen35:
            // Qwen3.5 chat_template.jinja: contents are trimmed, and enable_thinking=false
            // appends an empty think block to the generation prompt.
            // Earlier assistant turns carry no think block.
            var prefix = turn("system", request.instructions)
            for example in request.examples {
                prefix += turn("user", example.prompt) + turn("assistant", example.reply)
            }
            return (prefix, turn("user", request.prompt) + "<|im_start|>assistant\n<think>\n\n</think>\n\n")
        }
    }

    private static func turn(_ role: String, _ content: String) -> String {
        "<|im_start|>\(role)\n\(content.trimmingCharacters(in: .whitespacesAndNewlines))<|im_end|>\n"
    }
}
