import Testing
@testable import PardonKit

@Suite struct TranscriptTests {
    @Test func words() {
        check("words: empty", wordCount("") == 0)
        check("words: whitespace only", wordCount("  \n\t ") == 0)
        check("words: extra whitespace", wordCount("  hello   there  ") == 2)
        check("words: newlines and tabs", wordCount("one\ntwo\tthree\n") == 3)
    }

    @Test func sanitising() {
        check("sanitise: interior newline", sanitise("one\ntwo") == "one two")
        check("sanitise: carriage return", sanitise("one\rtwo") == "one two")
        check("sanitise: tab", sanitise("one\ttwo") == "one two")
        check("sanitise: escape sequence", sanitise("a\u{1B}[201~b") == "a [201~b")
        check("sanitise: U+2028", sanitise("one\u{2028}two") == "one two")
        check("sanitise: U+202E", sanitise("one\u{202E}two") == "one two")
        check("sanitise: capped at 4000", sanitise(String(repeating: "a", count: 5000)).count == 4000)
        check("sanitise: plain text unchanged", sanitise("Hello there, sir.") == "Hello there, sir.")
        check("sanitise: accents and apostrophes kept", sanitise("Café, naïve — it's Zoë’s") == "Café, naïve — it's Zoë’s")
    }
}
