import Testing
@testable import Waldo

struct TextDiffTests {
    private func render(_ segments: [TextDiff.Segment]?) -> String? {
        segments?.map { segment in
            switch segment.kind {
            case .same: segment.text
            case .removed: "[-\(segment.text)-]"
            case .inserted: "{+\(segment.text)+}"
            }
        }.joined()
    }

    @Test func groupsAPhraseReplacement() {
        #expect(render(TextDiff.segments(from: "I write you because we was testing",
                                         to: "I'm writing to you because we were testing"))
                == "[-I write-]{+I'm writing to+} you because we [-was-]{+were+} testing")
    }

    @Test func addedPunctuationDoesNotMarkTheWord() {
        #expect(render(TextDiff.segments(from: "Hi everybody just a quick heads up tomorrow is my birthday!",
                                         to: "Hi everyone, just a quick heads up: tomorrow is my birthday!"))
                == "Hi [-everybody-]{+everyone,+} just a quick heads up{+:+} tomorrow is my birthday!")
    }

    @Test func rebuildsBothTexts() {
        let old = "hey, the deploy dont work.\nCan u check?"
        let new = "Hey, the deploy doesn't work.\nCan you check?"
        let segments = TextDiff.segments(from: old, to: new)!
        #expect(segments.filter { $0.kind != .inserted }.map(\.text).joined() == old)
        #expect(segments.filter { $0.kind != .removed }.map(\.text).joined() == new)
    }

    @Test func skipsTranslations() {
        #expect(TextDiff.segments(from: "¿me podés pasar el link?", to: "Can you send me the link?") == nil)
    }

    @Test func unchangedTextIsOneSegment() {
        #expect(TextDiff.segments(from: "All good.", to: "All good.") == [.init(kind: .same, text: "All good.")])
    }
}
