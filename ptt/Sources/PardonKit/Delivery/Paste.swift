import CoreGraphics
import Foundation

// ANSI "V" position: used when the current layout has no Unicode data or no key types "v".
let pasteKeyCode: CGKeyCode = 9
let returnKeyCode: CGKeyCode = 36

// Unknown on both sides counts as unchanged; anything else that differs is a move.
func focusMoved(from before: pid_t?, to after: pid_t?) -> Bool {
    before != after
}

// Virtual key codes are 0..<128; the lowest code that matches wins.
func keyCode(producing target: String, fallback: CGKeyCode, translate: (CGKeyCode) -> String?) -> CGKeyCode {
    for code in CGKeyCode(0)..<128 where translate(code) == target { return code }
    return fallback
}

// Cmd-V is posted with Command held, and some layouts ("Dvorak – QWERTY ⌘") move keys under
// Command: look up "v" with Command first, then without, then the ANSI position.
func pasteKey(command: (CGKeyCode) -> String?, plain: (CGKeyCode) -> String?) -> CGKeyCode {
    let none = CGKeyCode.max
    let found = keyCode(producing: "v", fallback: none, translate: command)
    return found != none ? found : keyCode(producing: "v", fallback: pasteKeyCode, translate: plain)
}

enum SyntheticKey { case paste, submit }

// Focus is checked again before each key: a move before Cmd-V posts neither key, a move
// between Cmd-V and Return skips only Return.
func mayPost(_ key: SyntheticKey, pasted: Bool, moved: Bool) -> Bool {
    !moved && (key == .paste || pasted)
}
