import Foundation
import Testing
@testable import PardonKit

@Suite struct SpeakRequestTests {
    @Test func speeds() {
        check("speed: one decimal", speedText(1) == "1.0" && speedText(0.8) == "0.8" && speedText(1.5) == "1.5")
        check("speed: rounding", speedText(1.1000000000000001) == "1.1" && speedText(0.7999999999999999) == "0.8")
        check("speed: the seven steps", speedSteps == ["0.8", "0.9", "1.0", "1.1", "1.2", "1.3", "1.5"])
        check("speed: every step is valid for pardon.conf", speedSteps.allSatisfy(isSpeedText))
        check("speed: every step is within the server's 0.5 to 2.0", speedSteps.compactMap(Double.init).allSatisfy { (0.5...2.0).contains($0) })
    }

    @Test func body() {
        func decoded(_ d: Data?) -> [String: Any]? { d.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] } }
        let obj = decoded(speakBody(text: testSentence, voice: "bf_emma", speed: "1.3"))
        check("speak: valid JSON with the three fields", obj?.count == 3 && obj?["text"] as? String == "This is how I sound."
              && obj?["voice"] as? String == "bf_emma" && obj?["speed"] as? Double == 1.3)
        let hostile = #"a" , "voice": "x", "z": "\ end"# + "\n\u{0}"
        let escaped = decoded(speakBody(text: hostile, voice: "bf_emma", speed: "1.0"))
        check("speak: text is escaped, not spliced", escaped?.count == 3 && escaped?["text"] as? String == hostile
              && escaped?["voice"] as? String == "bf_emma")
        check("speak: an unparsable speed gives no body", speakBody(text: "x", voice: "bf_emma", speed: "fast") == nil)
        check("speak: test sentence fits the server's 1 to 2000 characters", (1...2000).contains(testSentence.count))
        check("constants: maxSpeakBytes is 4 MB", maxSpeakBytes == 4_194_304)
    }

    @Test func status() {
        check("speech status: running", speechStatusText(true) == "Speech: running")
        check("speech status: not running", speechStatusText(false) == "Speech: not running — make run")
        check("speech status: unknown", speechStatusText(nil) == "Speech: checking…")
    }

    @Test func enabledItems() {
        func e(_ up: Bool?, _ voices: Bool) -> [Bool] { let r = speechItemsEnabled(up: up, hasVoices: voices); return [r.voice, r.speed, r.test] }
        check("enabled: running with voices, all on", e(true, true) == [true, true, true])
        check("enabled: running without voices, Voice off", e(true, false) == [false, true, true])
        check("enabled: not running, all off", e(false, true) == [false, false, false] && e(false, false) == [false, false, false])
        check("enabled: unknown, all off", e(nil, true) == [false, false, false] && e(nil, false) == [false, false, false])
    }

    @Test func testVoiceRules() {
        check("test voice: may start when idle or transcribing", testMayStart(.idle) && testMayStart(.transcribing))
        check("test voice: never starts while listening", !testMayStart(.listening))
        check("test voice: a 200 plays when idle or transcribing", testMayPlay(status: 200, state: .idle) && testMayPlay(status: 200, state: .transcribing))
        check("test voice: a 200 never plays while listening", !testMayPlay(status: 200, state: .listening))
        check("test voice: an error status never plays", ![0, 204, 400, 500].contains { testMayPlay(status: $0, state: .idle) })
    }

    @Test func wavCheck() {
        let header = Data("RIFF".utf8) + Data([0x24, 0, 0, 0]) + Data("WAVE".utf8)
        check("wav: RIFF....WAVE accepted", looksLikeWAV(header) && looksLikeWAV(header + Data("fmt ".utf8)))
        check("wav: too short refused", !looksLikeWAV(Data()) && !looksLikeWAV(header.prefix(11)))
        check("wav: other containers refused", !looksLikeWAV(Data("RIFF\u{24}\0\0\0AVI ".utf8)) && !looksLikeWAV(Data("ID3\u{3}\0\0\0\0\0\0\0\0".utf8)))
        check("wav: JSON error body refused", !looksLikeWAV(Data(#"{"detail": "voice not found"}"#.utf8)))
        check("wav: lower-case magic refused", !looksLikeWAV(Data("riff\0\0\0\0wave".utf8)))
        check("constants: a test reply plays for at most 30 s", maxTestSeconds == 30)
    }
}
