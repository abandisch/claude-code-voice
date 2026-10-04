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

    // A user's own mute (make mute: an empty file) is never ours to remove.
    func release() {
        guard (try? FileManager.default.attributesOfItem(atPath: file.path))?[.type] as? FileAttributeType == .typeRegular,
              let handle = try? FileHandle(forReadingFrom: file) else { return }
        let head = try? handle.read(upToCount: 16)
        try? handle.close()
        if head == Self.marker { try? FileManager.default.removeItem(at: file) }
    }
}
