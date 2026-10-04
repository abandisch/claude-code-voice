import Foundation

func wordCount(_ s: String) -> Int {
    s.split(whereSeparator: { $0.isWhitespace }).count
}

let maxTranscriptChars = 4000

// Control, format and line/paragraph separators could act as keystrokes in the target window.
func sanitise(_ s: String) -> String {
    var scalars = String.UnicodeScalarView()
    for u in s.unicodeScalars {
        switch u.properties.generalCategory {
        case .control, .format, .lineSeparator, .paragraphSeparator: scalars.append(" ")
        default: scalars.append(u)
        }
    }
    let collapsed = String(scalars).split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    return String(collapsed.prefix(maxTranscriptChars)).trimmingCharacters(in: .whitespaces)
}
