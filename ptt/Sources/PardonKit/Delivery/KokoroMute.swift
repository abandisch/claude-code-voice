import Foundation

// MARK: - Kokoro mute flag

struct KokoroMute {
    static let marker = Data("pardon".utf8)
    let claudeDir: URL
    var file: URL { claudeDir.appendingPathComponent("hooks/mute") }

    init(claudeDir: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")) {
        self.claudeDir = claudeDir
    }

    func engage() {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: file.path), fm.fileExists(atPath: claudeDir.path) else { return }
        try? fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: false)
        try? Self.marker.write(to: file, options: .withoutOverwriting)
    }

    // Nil when there is no regular file to judge; read through a symlink, as the hooks do.
    private var head: Data? {
        guard isRegularFile(file), let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: 16)) ?? Data()
    }

    // A user's own mute (make mute: an empty file, or any symlink) is never ours to remove.
    func release() {
        if isRegularFile(file, followingLink: false), head == Self.marker { try? FileManager.default.removeItem(at: file) }
    }

    var isManual: Bool { head.map { $0 != Self.marker } ?? false }

    // On, ours becomes the user's (empty, as make mute leaves it); off, the file goes whoever wrote it.
    // Either way a symlink itself is replaced or removed, never its target.
    func setManual(_ on: Bool) {
        let fm = FileManager.default
        guard on else {
            if isRegularFile(file) { try? fm.removeItem(at: file) }
            return
        }
        if let head = head {
            if head == Self.marker { replaceAtomically(file, with: Data()) }
            return
        }
        guard !fm.fileExists(atPath: file.path), fm.fileExists(atPath: claudeDir.path) else { return }
        try? fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: false)
        try? Data().write(to: file, options: .withoutOverwriting)
    }
}

// Unmuting by hand mid-recording hands the mute back to the recording, which releases it at the end.
func recordingMuteReturns(turningOn: Bool, state: UIState, muteWhileRecording: Bool) -> Bool {
    !turningOn && state != .idle && muteWhileRecording
}
