import Foundation
import Testing

private let checkLogLock = NSLock()

// PARDON_CHECK_LOG collects every executed check name, so the test floor stays countable; tests run in parallel.
func check(_ name: String, _ ok: Bool, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(ok, Comment(rawValue: name), sourceLocation: sourceLocation)
    guard let path = ProcessInfo.processInfo.environment["PARDON_CHECK_LOG"] else { return }
    checkLogLock.lock()
    defer { checkLogLock.unlock() }
    let line = Data((name + "\n").utf8)
    if let log = FileHandle(forWritingAtPath: path) {
        log.seekToEndOfFile()
        log.write(line)
        log.closeFile()
    } else {
        try? line.write(to: URL(fileURLWithPath: path))
    }
}
