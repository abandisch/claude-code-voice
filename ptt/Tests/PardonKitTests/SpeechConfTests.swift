import Foundation
import Testing
@testable import PardonKit

@Suite struct SpeechConfTests {
    @Test func validation() {
        check("conf: voice ids that pass", ["bf_emma", "am_adam", "zz_a", "ab_" + String(repeating: "x", count: 20)].allSatisfy(isVoiceID))
        check("conf: voice ids that fail", !["", "bf_", "b_emma", "bfx_emma", "BF_emma", "bf_Emma", "bf-emma", "bf_emma1", "bf_em ma",
                                               "ab_" + String(repeating: "x", count: 21), "bf_emma\n", "bf_émma"].contains(where: isVoiceID))
        check("conf: speeds that pass", ["1.0", "0.8", "9.9", "0.0"].allSatisfy(isSpeedText))
        check("conf: speeds that fail", !["1", "1.", ".5", "1,0", "10.0", "1.00", "-1.0", "1.0\n", "١.٠"].contains(where: isSpeedText))
    }

    @Test func parsing() {
        func parse(_ s: String) -> SpeechConf { SpeechConf(parsing: Data(s.utf8)) }
        check("conf: defaults are bf_emma at 1.0", SpeechConf() == parse("") && SpeechConf().voice == "bf_emma" && SpeechConf().speed == "1.0")
        check("conf: valid file", parse("VOICE=am_adam\nSPEED=1.3\n") == parse("SPEED=1.3\nVOICE=am_adam"))
        check("conf: valid values read", parse("VOICE=am_adam\nSPEED=1.3\n").voice == "am_adam" && parse("VOICE=am_adam\nSPEED=1.3\n").speed == "1.3")
        check("conf: missing speed keeps the default", parse("VOICE=am_adam\n") == SpeechConf(parsing: Data("VOICE=am_adam\nSPEED=1.0\n".utf8)))
        check("conf: command substitution ignored", parse("VOICE=$(touch x)\nSPEED=1.1\n").voice == "bf_emma")
        check("conf: trailing command ignored", parse("VOICE=bf_emma; rm -rf ~\n").voice == "bf_emma"
              && parse("VOICE=am_adam; rm\n").voice == "bf_emma")
        check("conf: backticks and quotes ignored", parse("VOICE=`id`\nVOICE=\"am_adam\"\nSPEED='1.2'\n") == SpeechConf())
        check("conf: leading space ignored", parse(" VOICE=am_adam\nSPEED =1.2\n") == SpeechConf())
        check("conf: CRLF lines are invalid, as for the hooks", parse("VOICE=am_adam\r\nSPEED=1.2\r\n") == SpeechConf())
        check("conf: a CRLF line does not hide the next", parse("VOICE=am_adam\r\nSPEED=1.2\n").speed == "1.2")
        check("conf: first valid line wins", parse("VOICE=am_adam\nVOICE=bm_fable\nSPEED=0.9\nSPEED=1.5\n").voice == "am_adam"
              && parse("VOICE=am_adam\nVOICE=bm_fable\nSPEED=0.9\nSPEED=1.5\n").speed == "0.9")
        check("conf: an invalid line does not block a later valid one", parse("VOICE=x\nVOICE=bm_fable\nSPEED=fast\nSPEED=1.1\n").voice == "bm_fable"
              && parse("VOICE=x\nVOICE=bm_fable\nSPEED=fast\nSPEED=1.1\n").speed == "1.1")
        check("conf: overlong voice ignored", parse("VOICE=bf_" + String(repeating: "a", count: 4000) + "\n").voice == "bf_emma")
        let late = String(repeating: "#\n", count: 300) + "VOICE=am_adam\n"
        check("conf: past the 512-byte cap is not read", parse(late).voice == "bf_emma")
        var junk = Data((0..<256).map { UInt8($0) })
        junk.append(Data("\nVOICE=am_adam\n".utf8))
        check("conf: binary junk is skipped", SpeechConf(parsing: junk).voice == "am_adam")
        check("conf: binary junk alone gives the defaults", SpeechConf(parsing: Data([0, 0xff, 0xfe, 0x0a, 0x80])) == SpeechConf())
        check("conf: NUL inside a value ignored", SpeechConf(parsing: Data("VOICE=bf_e\u{0}ma\n".utf8)) == SpeechConf())
        check("conf: text is exactly two newline-terminated lines", parse("VOICE=am_adam\nSPEED=1.3").text == "VOICE=am_adam\nSPEED=1.3\n")
    }

    // The same cases as hook/test-hooks.sh, with the same results, so the two parsers cannot drift apart.
    @Test func hookParity() {
        func parse(_ s: String) -> SpeechConf { SpeechConf(parsing: Data(s.utf8)) }
        func bytes(_ b: [UInt8]) -> SpeechConf { SpeechConf(parsing: Data(b)) }
        func pad(_ n: Int) -> String { "#" + String(repeating: "0", count: n - 2) + "\n" }
        func letters(_ n: Int) -> String { String(repeating: "a", count: n) }
        func conf(_ voice: String, _ speed: String) -> SpeechConf { var c = SpeechConf(); c.voice = voice; c.speed = speed; return c }
        check("parity: first valid line of each kind wins", parse("VOICE=am_adam\nVOICE=bm_fable\nSPEED=0.9\nSPEED=1.5\n") == conf("am_adam", "0.9"))
        check("parity: no trailing newline", parse("VOICE=bm_fable\nSPEED=1.3") == conf("bm_fable", "1.3"))
        check("parity: shortest voice zz_a accepted", parse("VOICE=zz_a\n") == conf("zz_a", "1.0"))
        check("parity: 20-letter voice name accepted", parse("VOICE=zz_\(letters(20))\n") == conf("zz_" + letters(20), "1.0"))
        check("parity: 21-letter voice name gives the defaults", parse("VOICE=zz_\(letters(21))\n") == SpeechConf())
        check("parity: pad lines are the sizes the hook test uses", pad(512).utf8.count == 512 && pad(497).utf8.count == 497)
        check("parity: lines past the 512-byte cap are not read", parse(pad(512) + "VOICE=bm_fable\nSPEED=1.3\n") == SpeechConf())
        check("parity: voice line ending at byte 512 accepted", parse(pad(497) + "VOICE=bm_fable\nSPEED=1.3\n") == conf("bm_fable", "1.0"))
        check("parity: voice line cut by the cap is not read", parse(pad(501) + "VOICE=bm_fable\n") == SpeechConf())
        check("parity: newline just past the cap, line not read", parse(pad(498) + "VOICE=bm_fable\n") == SpeechConf())
        check("parity: 512-byte file without trailing newline accepted", parse(pad(498) + "VOICE=bm_fable") == conf("bm_fable", "1.0"))
        check("parity: invalid UTF-8 line skipped", bytes(Array("X=".utf8) + [0xff] + Array("\nVOICE=bm_fable\n".utf8)) == conf("bm_fable", "1.0"))
        check("parity: binary junk skipped", bytes((0...255).map { UInt8($0) } + Array("\nVOICE=am_adam\n".utf8)) == conf("am_adam", "1.0"))
        check("parity: NUL inside a value, next line still read",
              bytes(Array("VOICE=bm_fable".utf8) + [0] + Array("\nSPEED=1.3\n".utf8)) == conf("bf_emma", "1.3"))
        check("parity: a combining mark after the prefix is not a voice", parse("VOICE=\u{301}bm_fable\n") == SpeechConf())
    }

    @Test func file() {
        let fm = FileManager.default
        let tmp = ProcessInfo.processInfo.environment["TMPDIR"] ?? NSTemporaryDirectory()
        let scratch = URL(fileURLWithPath: tmp).appendingPathComponent("pardon-tests-\(UUID().uuidString)")
        check("conf file: temporary directory created", (try? fm.createDirectory(at: scratch, withIntermediateDirectories: false)) != nil)
        defer {
            try? fm.removeItem(at: scratch)
            check("conf file: temporary directory removed", !fm.fileExists(atPath: scratch.path))
        }
        let claude = scratch.appendingPathComponent("claude")
        let conf = SpeechConfFile(claudeDir: claude)
        func contents() -> String? { (try? Data(contentsOf: conf.file)).map { String(decoding: $0, as: UTF8.self) } }
        check("conf file: missing file gives the defaults", conf.read() == SpeechConf())
        conf.write(voice: "am_adam")
        check("conf file: no .claude directory, nothing created", !fm.fileExists(atPath: claude.path))
        try? fm.createDirectory(at: claude, withIntermediateDirectories: false)
        conf.write(voice: "am_adam")
        check("conf file: write creates hooks/ and both lines", contents() == "VOICE=am_adam\nSPEED=1.0\n")
        conf.write(speed: "1.3")
        check("conf file: a speed write keeps the voice", contents() == "VOICE=am_adam\nSPEED=1.3\n")
        conf.write(voice: "bm_fable")
        check("conf file: a voice write keeps the speed", contents() == "VOICE=bm_fable\nSPEED=1.3\n")
        check("conf file: round trip", conf.read().voice == "bm_fable" && conf.read().speed == "1.3")
        for bad in ["$(touch x)", "bf_emma; rm", "bf_emma\nSPEED=9.9", "BF_EMMA", ""] { conf.write(voice: bad) }
        for bad in ["1", "1,0", "1.0\nVOICE=x_y", "fast", "10.0"] { conf.write(speed: bad) }
        conf.write(voice: "am_adam", speed: "1,5")
        check("conf file: invalid values are never written", contents() == "VOICE=bm_fable\nSPEED=1.3\n")
        try? Data("# hand edited\nSPEED=0.9\nVOICE=nonsense here\n".utf8).write(to: conf.file)
        conf.write(voice: "af_bella")
        check("conf file: rewrite keeps a valid value and drops junk", contents() == "VOICE=af_bella\nSPEED=0.9\n")
        let leftovers = (try? fm.contentsOfDirectory(atPath: conf.file.deletingLastPathComponent().path)) ?? []
        check("conf file: atomic write leaves no temporary file", leftovers == ["pardon.conf"])
        try? Data((String(repeating: "#\n", count: 250) + "VOICE=bm_fable\n").utf8).write(to: conf.file)
        check("conf file: a line cut by the cap is not read from disk", conf.read() == SpeechConf())
        try? fm.removeItem(at: conf.file)
        try? fm.createDirectory(at: conf.file, withIntermediateDirectories: false)
        check("conf file: a directory in its place reads as the defaults", conf.read() == SpeechConf())
    }

    @Test func symlink() {
        let fm = FileManager.default
        let tmp = ProcessInfo.processInfo.environment["TMPDIR"] ?? NSTemporaryDirectory()
        let scratch = URL(fileURLWithPath: tmp).appendingPathComponent("pardon-tests-\(UUID().uuidString)")
        check("conf link: temporary directory created", (try? fm.createDirectory(at: scratch, withIntermediateDirectories: false)) != nil)
        defer {
            try? fm.removeItem(at: scratch)
            check("conf link: temporary directory removed", !fm.fileExists(atPath: scratch.path))
        }
        let claude = scratch.appendingPathComponent("claude")
        try? fm.createDirectory(at: claude.appendingPathComponent("hooks"), withIntermediateDirectories: true)
        let conf = SpeechConfFile(claudeDir: claude)
        let target = scratch.appendingPathComponent("elsewhere.conf")
        let original = Data("VOICE=am_adam\nSPEED=1.2\n".utf8)
        try? original.write(to: target)
        try? fm.createSymbolicLink(at: conf.file, withDestinationURL: target)
        check("conf link: read follows the link, as the hooks do", conf.read().voice == "am_adam" && conf.read().speed == "1.2")
        conf.write(speed: "1.5")
        check("conf link: a write keeps the value read through the link", conf.read().voice == "am_adam" && conf.read().speed == "1.5")
        check("conf link: the target is untouched", (try? Data(contentsOf: target)) == original)
        check("conf link: a regular file replaces the link", isRegularFile(conf.file, followingLink: false))
        try? fm.removeItem(at: conf.file)
        try? fm.createSymbolicLink(at: conf.file, withDestinationURL: scratch.appendingPathComponent("missing"))
        check("conf link: a dangling link reads as the defaults", conf.read() == SpeechConf())
        try? fm.removeItem(at: conf.file)
        try? fm.createSymbolicLink(at: conf.file, withDestinationURL: scratch)
        check("conf link: a link to a directory reads as the defaults", conf.read() == SpeechConf())
        try? fm.removeItem(at: conf.file)
        check("conf link: a FIFO behind a link is never opened", mkfifo(target.path + ".fifo", 0o600) == 0
              && (try? fm.createSymbolicLink(at: conf.file, withDestinationURL: URL(fileURLWithPath: target.path + ".fifo"))) != nil
              && !isRegularFile(conf.file) && conf.read() == SpeechConf())
    }
}
