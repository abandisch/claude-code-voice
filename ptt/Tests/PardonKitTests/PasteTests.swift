import CoreGraphics
import Testing
@testable import PardonKit

@Suite struct PasteTests {
    @Test func focus() {
        check("focus: same app has not moved", !focusMoved(from: 501, to: 501))
        check("focus: different app has moved", focusMoved(from: 501, to: 502))
        check("focus: unknown both times has not moved", !focusMoved(from: nil, to: nil))
        check("focus: known then unknown has moved", focusMoved(from: 501, to: nil))
        check("focus: unknown then known has moved", focusMoved(from: nil, to: 501))
    }

    @Test func pasteShortcut() {
        let qwerty: [CGKeyCode: String] = [0: "a", 1: "s", 6: "z", 7: "x", 8: "c", 9: "v", 11: "b"]
        let dvorak: [CGKeyCode: String] = [0: "a", 1: "o", 6: ";", 7: "q", 8: "j", 9: "k", 47: "v"]
        check("paste key: QWERTY is 9", keyCode(producing: "v", fallback: pasteKeyCode) { qwerty[$0] } == 9)
        check("paste key: Dvorak is 47", keyCode(producing: "v", fallback: pasteKeyCode) { dvorak[$0] } == 47)
        check("paste key: no match falls back to 9", keyCode(producing: "v", fallback: pasteKeyCode) { _ in "x" } == 9)
        check("paste key: nil results are skipped", keyCode(producing: "v", fallback: pasteKeyCode) { $0 == 30 ? "v" : nil } == 30)
        check("paste key: two keys type v, lowest wins", keyCode(producing: "v", fallback: pasteKeyCode) { [9: "v", 47: "v"][$0] } == 9)
        check("paste key: match at code 0 is found", keyCode(producing: "v", fallback: pasteKeyCode) { $0 == 0 ? "v" : nil } == 0)
        check("paste key: match at code 127 is found", keyCode(producing: "v", fallback: pasteKeyCode) { $0 == 127 ? "v" : nil } == 127)
        check("paste key: Command lookup wins (Dvorak – QWERTY ⌘)", pasteKey(command: { qwerty[$0] }, plain: { dvorak[$0] }) == 9)
        check("paste key: no Command match falls back to plain", pasteKey(command: { _ in nil }, plain: { dvorak[$0] }) == 47)
        check("paste key: neither matches falls back to 9", pasteKey(command: { _ in "x" }, plain: { _ in nil }) == 9)
    }

    @Test func keys() {
        check("keys: paste when focus stayed", mayPost(.paste, pasted: false, moved: false))
        check("keys: no paste when focus moved", !mayPost(.paste, pasted: false, moved: true))
        check("keys: Return after paste when focus stayed", mayPost(.submit, pasted: true, moved: false))
        check("keys: no Return when focus moved after paste", !mayPost(.submit, pasted: true, moved: true))
        check("keys: no Return when the paste was skipped", !mayPost(.submit, pasted: false, moved: false))
    }
}
