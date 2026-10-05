import Foundation

enum TranscribeResult: Equatable { case text(String), noSpeech, failed(String), timedOut, unreachable }

func parseTranscription(status: Int, body: Data) -> TranscribeResult {
    let obj = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
    guard status == 200 else { return .failed((obj?["error"] as? String) ?? "HTTP \(status)") }
    guard let obj = obj, let text = obj["text"] as? String else { return .failed("malformed response") }
    if (obj["no_speech"] as? Bool) == true { return .noSpeech }
    let clean = sanitise(text)
    return clean.isEmpty ? .noSpeech : .text(clean)
}

func transportResult(_ error: Error) -> TranscribeResult {
    (error as? URLError)?.code == .timedOut ? .timedOut : .unreachable
}

func transcribeResult(_ reply: CollectedReply) -> TranscribeResult {
    switch reply {
    case .body(let status, let data): return parseTranscription(status: status, body: data)
    case .tooLarge: return .failed("Transcription server reply too large")
    case .transport(let error): return transportResult(error)
    }
}

let maxReplyBytes = 256 * 1024

// A declared length of -1 means unknown; the received bytes are checked as they arrive.
func replyFits(_ bytes: Int64, limit: Int = maxReplyBytes) -> Bool {
    bytes <= Int64(limit)
}
