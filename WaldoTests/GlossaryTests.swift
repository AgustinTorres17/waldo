import Foundation
import Testing
@testable import Waldo

struct GlossaryTests {
    @Test func parsesOneTermPerLine() {
        #expect(Glossary.terms(from: "  Corrigy \n\npull request\ncorrigy\n") == ["Corrigy", "pull request"])
    }

    @Test func matchesWholeWordsIgnoringCase() {
        let glossary = ["Go", "pull request", "C++"]
        #expect(Glossary.terms(in: "the good news: the Pull Request is in go", glossary: glossary) == ["Go", "pull request"])
        #expect(Glossary.terms(in: "we use C++ here", glossary: glossary) == ["C++"])
        #expect(Glossary.terms(in: "nothing good", glossary: glossary).isEmpty)
    }

    @Test func appliesTheGlossarySpelling() {
        #expect(Glossary.applySpelling(["Corrigy", "pull request"], to: "corrigy got a Pull Request")
                == "Corrigy got a pull request")
    }

    @Test func validatorRejectsAChangedTerm() {
        #expect(OutputValidator.validate("Revisá la solicitud de cambios.", input: "check the pull request",
                                         task: .translate(sourceName: nil), target: .spanish, requiredTerms: ["pull request"])
                == .invalid("The result changed a glossary term."))
    }

    @Test func termsGoInTheUserPromptOnly() {
        let request = PromptBuilder.request(for: .correct, text: "the pull request", target: .english,
                                            keepTerms: ["pull request"], engine: .llamaCpp, greedy: false)
        #expect(request.prompt.contains("Correct it as usual; only these exact terms stay as they are: \"pull request\"."))
        #expect(!request.instructions.contains("pull request"))
    }
}
