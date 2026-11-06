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
            return (prefix, turn("user", request.prompt) + assistantStart)
        }
    }

    private static func turn(_ role: String, _ content: String) -> String {
        "<|im_start|>\(role)\n\(content.trimmingCharacters(in: .whitespacesAndNewlines))<|im_end|>\n"
    }
}

extension PromptFormatter {
    /// What the model writes next in a chat.
    enum ChatStep {
        /// The search query for the last question.
        case searchQuery
        case answer
    }

    /// A chat from its start, with `marker` where each image goes, ending where
    /// the model writes the last turn's next step. Generated text (queries,
    /// answers with their reasoning) goes in exactly as written, after the same
    /// generation prompt it was written after, so a chat continued in place and
    /// one rebuilt from here read the same.
    static func chat(instructions: String, turns: [ChatTurn], marker: String,
                     family: PromptFamily) -> (prompt: String, step: ChatStep) {
        switch family {
        case .qwen35:
            var prompt = turn("system", instructions)
            for (index, item) in turns.enumerated() {
                var message = item.question
                if let quote = item.quote {
                    message = "Selected text:\n\"\"\"\n\(quote)\n\"\"\"\n\n" + message
                }
                if item.hasImage {
                    message = "\(marker)\n" + message
                }
                if let search = item.search {
                    prompt += turn("user", message + "\n\n" + ChatPrompts.queryRequest(search)) + assistantStart
                    guard let rawQuery = search.rawQuery else { return (prompt, .searchQuery) }
                    prompt += rawQuery + "<|im_end|>\n" + turn("user", ChatPrompts.searchResults(search))
                } else {
                    prompt += turn("user", message)
                }
                prompt += item.thinks ? thinkingStart : assistantStart
                if index == turns.count - 1 { return (prompt, .answer) }
                prompt += item.answer + "<|im_end|>\n"
            }
            return (prompt, .answer)
        }
    }

    /// Qwen3.5's generation prompt with thinking turned off.
    private static var assistantStart: String { "<|im_start|>assistant\n<think>\n\n</think>\n\n" }
    /// With thinking on: the model writes its reasoning, closes it with </think>, then answers.
    private static var thinkingStart: String { "<|im_start|>assistant\n<think>\n" }
}
