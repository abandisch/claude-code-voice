import Foundation

// MARK: - Files the voice hooks read

// Follows a symlink, as the hooks' [ -f ] does; false for a FIFO (opening one would block), a directory or nothing.
func isRegularFile(_ url: URL, followingLink: Bool = true) -> Bool {
    var st = stat()
    let found = followingLink ? stat(url.path, &st) : lstat(url.path, &st)
    return found == 0 && st.st_mode & S_IFMT == S_IFREG
}

// A sibling file renamed over the target: a reader sees the old file or the new one, never part of one.
// rename replaces a symlink itself, so a write never lands in the link's target.
func replaceAtomically(_ url: URL, with data: Data) {
    let tmp = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString)")
    guard (try? data.write(to: tmp, options: .withoutOverwriting)) != nil else { return }
    if rename(tmp.path, url.path) != 0 { try? FileManager.default.removeItem(at: tmp) }
}
