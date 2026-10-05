import Foundation

// MARK: - Test voice

let testSentence = "This is how I sound."

// Tenths by integer arithmetic, so no locale can turn the dot into a comma.
func speedText(_ speed: Double) -> String {
    let tenths = Int((speed * 10).rounded())
    return "\(tenths / 10).\(tenths % 10)"
}

let speedSteps = [0.8, 0.9, 1.0, 1.1, 1.2, 1.3, 1.5].map(speedText)

private struct SpeakBody: Encodable { let text: String, voice: String, speed: Double }

func speakBody(text: String, voice: String, speed: String) -> Data? {
    guard let speed = Double(speed) else { return nil }
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    return try? encoder.encode(SpeakBody(text: text, voice: voice, speed: speed))
}

func speechStatusText(_ up: Bool?) -> String {
    switch up {
    case true?: return "Speech: running"
    case false?: return "Speech: not running — make run"
    case nil: return "Speech: checking…"
    }
}

// The one rule for the menu's speech items, at build time and when speech comes or goes with the menu open.
func speechItemsEnabled(up: Bool?, hasVoices: Bool) -> (voice: Bool, speed: Bool, test: Bool) {
    let up = up == true
    return (up && hasVoices, up, up)
}

// Mute is deliberately not an input: a test is an explicit request. The open microphone must not hear it.
func testMayStart(_ state: UIState) -> Bool { state != .listening }

func testMayPlay(status: Int, state: UIState) -> Bool { status == 200 && testMayStart(state) }

// Only a RIFF/WAVE body reaches the decoder.
func looksLikeWAV(_ data: Data) -> Bool {
    let b = [UInt8](data.prefix(12))
    return b.count == 12 && b[0..<4].elementsEqual("RIFF".utf8) && b[8..<12].elementsEqual("WAVE".utf8)
}
