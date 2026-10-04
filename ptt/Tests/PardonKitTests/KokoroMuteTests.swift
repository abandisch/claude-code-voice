import Foundation
import Testing
@testable import PardonKit

@Suite struct KokoroMuteTests {
    @Test func muteFlag() {
        let fm = FileManager.default
        let tmp = ProcessInfo.processInfo.environment["TMPDIR"] ?? NSTemporaryDirectory()
        let scratch = URL(fileURLWithPath: tmp).appendingPathComponent("pardon-tests-\(UUID().uuidString)")
        check("mute: temporary directory created", (try? fm.createDirectory(at: scratch, withIntermediateDirectories: false)) != nil)
        defer {
            try? fm.removeItem(at: scratch)
            check("mute: temporary directory removed", !fm.fileExists(atPath: scratch.path))
        }
        let claude = scratch.appendingPathComponent("claude")
        let mute = KokoroMute(claudeDir: claude)
        mute.engage()
        check("mute: no .claude directory, nothing created", !fm.fileExists(atPath: claude.path))
        try? fm.createDirectory(at: claude, withIntermediateDirectories: false)
        mute.engage()
        check("mute: engage writes pardon", (try? Data(contentsOf: mute.file)) == KokoroMute.marker)
        mute.release()
        check("mute: release removes ours", !fm.fileExists(atPath: mute.file.path))
        try? Data().write(to: mute.file)
        mute.engage()
        check("mute: a user's empty file is not overwritten", (try? Data(contentsOf: mute.file)) == Data())
        mute.release()
        check("mute: a user's empty file is not removed", fm.fileExists(atPath: mute.file.path))
        try? Data("pardon\n".utf8).write(to: mute.file)
        mute.release()
        check("mute: pardon plus newline is not removed", fm.fileExists(atPath: mute.file.path))
    }
}
