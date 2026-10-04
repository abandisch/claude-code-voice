import Foundation
import Testing
@testable import PardonKit

@Suite struct TranscriptionTests {
    @Test func parsing() {
        func parse(_ status: Int, _ s: String) -> TranscribeResult { parseTranscription(status: status, body: Data(s.utf8)) }
        check("parse: text", parse(200, #"{"text": " Hello there. ", "duration_s": 1.2, "no_speech": false}"#) == .text("Hello there."))
        check("parse: text is sanitised", parse(200, #"{"text": "rm -rf x\ny", "no_speech": false}"#) == .text("rm -rf x y"))
        check("parse: no_speech", parse(200, #"{"text": "", "duration_s": 1.0, "no_speech": true}"#) == .noSpeech)
        check("parse: no_speech with text", parse(200, #"{"text": "x", "no_speech": true}"#) == .noSpeech)
        check("parse: whitespace text", parse(200, #"{"text": "  \n ", "duration_s": 1.0, "no_speech": false}"#) == .noSpeech)
        check("parse: error JSON", parse(413, #"{"error": "too large"}"#) == .failed("too large"))
        check("parse: non-200 without JSON", parse(500, "oops") == .failed("HTTP 500"))
        check("parse: 500 with text is failed", parse(500, #"{"text": "x", "no_speech": false}"#) == .failed("HTTP 500"))
        check("parse: redirect is failed", parse(307, "") == .failed("HTTP 307"))
        check("parse: garbage", parse(200, "not json") == .failed("malformed response"))
        check("parse: 200 without text", parse(200, #"{"ok": true}"#) == .failed("malformed response"))
    }

    @Test func transport() {
        check("transport: timeout", transportResult(URLError(.timedOut)) == .timedOut)
        check("transport: cannot connect", transportResult(URLError(.cannotConnectToHost)) == .unreachable)
    }

    @Test func replyCap() {
        check("constants: maxReplyBytes is 256 KB", maxReplyBytes == 262_144)
        check("reply: under the cap fits", replyFits(Int64(maxReplyBytes - 1)))
        check("reply: exactly the cap fits", replyFits(Int64(maxReplyBytes)))
        check("reply: over the cap is refused", !replyFits(Int64(maxReplyBytes + 1)))
        check("reply: unknown declared length (-1) fits", replyFits(-1))
    }
}
