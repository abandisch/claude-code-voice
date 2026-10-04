import Foundation

let serverURL = URL(string: "http://127.0.0.1:8881")!
public let bundleID = "io.github.abandisch.pardon"
// "PARD": our own synthetic events carry it and the tap ignores them.
let pardonEventTag: Int64 = 0x5041_5244
let pasteDelay: TimeInterval = 0.1
let returnDelay: TimeInterval = 0.15
// Target apps read the pasteboard asynchronously after Cmd-V.
let restoreDelay: TimeInterval = 1.0
let healthInterval: TimeInterval = 10
let permissionInterval: TimeInterval = 2
let keyCheckInterval: TimeInterval = 1
let transcribeTimeout: TimeInterval = 120
let healthTimeout: TimeInterval = 2

enum DefaultsKey: String { case mode, side, autoSubmit, muteKokoro, showOrb, orbOrigin, character, animateIdle }

func now() -> TimeInterval { ProcessInfo.processInfo.systemUptime }
