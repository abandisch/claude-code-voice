import Foundation

// MARK: - Voice and speed for the hooks

// Shared with the shell hooks: exactly "VOICE=…\nSPEED=…\n"; only values passing these checks are read or written.
// hook/speak-kokoro.sh and hook/notify-kokoro.sh must parse alike (pattern, 512-byte cap, NUL and cut lines);
// hook/test-hooks.sh and SpeechConfTests pin the same cases.
func isVoiceID(_ s: String) -> Bool {
    let b = Array(s.utf8)
    func lower(_ c: UInt8) -> Bool { c >= UInt8(ascii: "a") && c <= UInt8(ascii: "z") }
    return (4...23).contains(b.count) && lower(b[0]) && lower(b[1]) && b[2] == UInt8(ascii: "_") && b[3...].allSatisfy(lower)
}

func isSpeedText(_ s: String) -> Bool {
    let b = Array(s.utf8)
    func digit(_ c: UInt8) -> Bool { c >= UInt8(ascii: "0") && c <= UInt8(ascii: "9") }
    return b.count == 3 && digit(b[0]) && b[1] == UInt8(ascii: ".") && digit(b[2])
}

struct SpeechConf: Equatable {
    static let defaultVoice = "bf_emma"
    static let defaultSpeed = "1.0"
    // The hooks read the same 512 bytes, so the menu shows what they use.
    static let maxBytes = 512
    var voice = SpeechConf.defaultVoice
    var speed = SpeechConf.defaultSpeed

    // The first valid line of each kind wins; like the hooks' whole-line match, a CRLF line is invalid.
    // A line counts only if it ends within the cap: at a newline, or where a file that fits ends.
    init(parsing data: Data) {
        var window = data.prefix(Self.maxBytes)
        if data.count > Self.maxBytes, window.last != UInt8(ascii: "\n") {
            window = window[..<(window.lastIndex(of: UInt8(ascii: "\n")) ?? window.startIndex)]
        }
        var voice: String?, speed: String?
        // Split as bytes: as a String, "\r\n" is one Character and would hide the line break.
        for line in window.split(separator: UInt8(ascii: "\n")) {
            let value = String(decoding: line.dropFirst(6), as: UTF8.self)
            if voice == nil, line.starts(with: "VOICE=".utf8), isVoiceID(value) { voice = value }
            if speed == nil, line.starts(with: "SPEED=".utf8), isSpeedText(value) { speed = value }
        }
        self.voice = voice ?? Self.defaultVoice
        self.speed = speed ?? Self.defaultSpeed
    }

    init() {}

    var text: String { "VOICE=\(voice)\nSPEED=\(speed)\n" }
}

struct SpeechConfFile {
    let claudeDir: URL
    var file: URL { claudeDir.appendingPathComponent("hooks/pardon.conf") }

    init(claudeDir: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")) {
        self.claudeDir = claudeDir
    }

    // One byte past the cap tells a cut last line from a file that ends there.
    func read() -> SpeechConf {
        guard isRegularFile(file), let handle = try? FileHandle(forReadingFrom: file) else { return SpeechConf() }
        defer { try? handle.close() }
        return SpeechConf(parsing: (try? handle.read(upToCount: SpeechConf.maxBytes + 1)) ?? Data())
    }

    // Nil keeps the value already in the file; an invalid value writes nothing.
    func write(voice: String? = nil, speed: String? = nil) {
        if let voice = voice, !isVoiceID(voice) { return }
        if let speed = speed, !isSpeedText(speed) { return }
        let fm = FileManager.default
        guard fm.fileExists(atPath: claudeDir.path) else { return }
        var conf = read()
        conf.voice = voice ?? conf.voice
        conf.speed = speed ?? conf.speed
        try? fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: false)
        replaceAtomically(file, with: Data(conf.text.utf8))
    }
}
