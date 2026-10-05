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

    @Test func manualMute() {
        let fm = FileManager.default
        let tmp = ProcessInfo.processInfo.environment["TMPDIR"] ?? NSTemporaryDirectory()
        let scratch = URL(fileURLWithPath: tmp).appendingPathComponent("pardon-tests-\(UUID().uuidString)")
        check("manual mute: temporary directory created", (try? fm.createDirectory(at: scratch, withIntermediateDirectories: false)) != nil)
        defer {
            try? fm.removeItem(at: scratch)
            check("manual mute: temporary directory removed", !fm.fileExists(atPath: scratch.path))
        }
        let claude = scratch.appendingPathComponent("claude")
        let mute = KokoroMute(claudeDir: claude)
        func contents() -> Data? { try? Data(contentsOf: mute.file) }
        mute.setManual(true)
        check("manual mute: no .claude directory, nothing created", !fm.fileExists(atPath: claude.path))
        check("manual mute: not manual without a file", !mute.isManual)
        try? fm.createDirectory(at: claude, withIntermediateDirectories: false)
        mute.setManual(true)
        check("manual mute: on creates hooks/ and an empty file", contents() == Data() && mute.isManual)
        mute.setManual(false)
        check("manual mute: off removes it", !fm.fileExists(atPath: mute.file.path) && !mute.isManual)
        mute.setManual(false)
        check("manual mute: off with no file is harmless", !fm.fileExists(atPath: mute.file.path))
        mute.engage()
        check("manual mute: our marker is not a manual mute", !mute.isManual)
        mute.setManual(true)
        check("manual mute: on replaces our marker with an empty file", contents() == Data() && mute.isManual)
        try? Data("user note".utf8).write(to: mute.file)
        mute.setManual(true)
        check("manual mute: on leaves a user's file alone", contents() == Data("user note".utf8) && mute.isManual)
        mute.setManual(false)
        check("manual mute: off removes a user's file whatever it holds", !fm.fileExists(atPath: mute.file.path))
        mute.engage()
        mute.setManual(false)
        check("manual mute: off removes our marker too", !fm.fileExists(atPath: mute.file.path))
        try? fm.createDirectory(at: mute.file, withIntermediateDirectories: false)
        mute.setManual(false)
        check("manual mute: a directory in its place is not removed or counted", fm.fileExists(atPath: mute.file.path) && !mute.isManual)
        try? fm.removeItem(at: mute.file)
    }

    @Test func manualMuteSurvivesRecording() {
        let fm = FileManager.default
        let tmp = ProcessInfo.processInfo.environment["TMPDIR"] ?? NSTemporaryDirectory()
        let scratch = URL(fileURLWithPath: tmp).appendingPathComponent("pardon-tests-\(UUID().uuidString)")
        check("mute sequence: temporary directory created", (try? fm.createDirectory(at: scratch, withIntermediateDirectories: false)) != nil)
        defer {
            try? fm.removeItem(at: scratch)
            check("mute sequence: temporary directory removed", !fm.fileExists(atPath: scratch.path))
        }
        let claude = scratch.appendingPathComponent("claude")
        try? fm.createDirectory(at: claude, withIntermediateDirectories: false)
        let mute = KokoroMute(claudeDir: claude)
        mute.setManual(true)
        mute.engage()
        mute.release()
        check("mute sequence: manual on, engage, release, still muted", fm.fileExists(atPath: mute.file.path) && mute.isManual)
        mute.setManual(false)
        mute.engage()
        mute.setManual(true)
        mute.release()
        check("mute sequence: engaged, manual on, release, still muted", fm.fileExists(atPath: mute.file.path) && mute.isManual)
        mute.setManual(false)
        mute.engage()
        mute.setManual(false)
        mute.engage()
        check("mute sequence: manual off mid-session, re-engaged, holds the marker", (try? Data(contentsOf: mute.file)) == KokoroMute.marker)
        mute.release()
        check("mute sequence: the session's release then unmutes", !fm.fileExists(atPath: mute.file.path))
    }

    @Test func unmuteMidRecording() {
        for state in [UIState.idle, .listening, .transcribing] {
            for turningOn in [false, true] {
                for setting in [false, true] {
                    let want = !turningOn && state != .idle && setting
                    check("mute rule: \(state), on \(turningOn), while-recording \(setting) -> re-engage \(want)",
                          recordingMuteReturns(turningOn: turningOn, state: state, muteWhileRecording: setting) == want)
                }
            }
        }
        check("mute rule: unmuting mid-recording re-engages", recordingMuteReturns(turningOn: false, state: .listening, muteWhileRecording: true)
              && recordingMuteReturns(turningOn: false, state: .transcribing, muteWhileRecording: true))
        check("mute rule: idle never re-engages", !recordingMuteReturns(turningOn: false, state: .idle, muteWhileRecording: true))
        check("mute rule: setting off never re-engages", !recordingMuteReturns(turningOn: false, state: .listening, muteWhileRecording: false))
        check("mute rule: turning mute on never re-engages", !recordingMuteReturns(turningOn: true, state: .listening, muteWhileRecording: true))
    }

    @Test func symlinks() {
        let fm = FileManager.default
        let tmp = ProcessInfo.processInfo.environment["TMPDIR"] ?? NSTemporaryDirectory()
        let scratch = URL(fileURLWithPath: tmp).appendingPathComponent("pardon-tests-\(UUID().uuidString)")
        check("mute link: temporary directory created", (try? fm.createDirectory(at: scratch, withIntermediateDirectories: false)) != nil)
        defer {
            try? fm.removeItem(at: scratch)
            check("mute link: temporary directory removed", !fm.fileExists(atPath: scratch.path))
        }
        let claude = scratch.appendingPathComponent("claude")
        try? fm.createDirectory(at: claude.appendingPathComponent("hooks"), withIntermediateDirectories: true)
        let mute = KokoroMute(claudeDir: claude)
        let target = scratch.appendingPathComponent("elsewhere")
        func link() { try? fm.removeItem(at: mute.file); try? fm.createSymbolicLink(at: mute.file, withDestinationURL: target) }
        func isLink() -> Bool { (try? fm.destinationOfSymbolicLink(atPath: mute.file.path)) != nil }
        try? Data().write(to: target)
        link()
        check("mute link: a link to an empty file is a manual mute, as for the hooks", mute.isManual)
        mute.setManual(false)
        check("mute link: off removes the link, not its target", !isLink() && !fm.fileExists(atPath: mute.file.path) && fm.fileExists(atPath: target.path))
        try? KokoroMute.marker.write(to: target)
        link()
        mute.release()
        check("mute link: release leaves a link to a marker alone", isLink() && (try? Data(contentsOf: target)) == KokoroMute.marker)
        check("mute link: a link to a marker is not a manual mute", !mute.isManual)
        mute.setManual(true)
        check("mute link: on replaces a link to a marker with an empty regular file",
              !isLink() && isRegularFile(mute.file, followingLink: false) && (try? Data(contentsOf: mute.file)) == Data() && mute.isManual)
        check("mute link: the marker target is untouched", (try? Data(contentsOf: target)) == KokoroMute.marker)
        try? fm.removeItem(at: mute.file)
        try? fm.removeItem(at: target)
        link()
        check("mute link: a dangling link is not a mute", !mute.isManual)
        mute.setManual(false)
        check("mute link: off leaves a dangling link alone", isLink())
    }
}
