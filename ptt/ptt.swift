// Pardon: hold Option, speak, release; the transcript from the local STT container
// (127.0.0.1:8881) is pasted into the focused window. Build with ptt/build.sh.
// This file is the app's core; main.swift is the entry point, pet.swift the orb and reactor.swift its arc reactor.
import AppKit
import ApplicationServices
import AVFoundation
import Carbon
import CoreGraphics
import Foundation
import ServiceManagement

// MARK: - Pure pieces (exercised by --self-test)

enum OptionKey { case left, right }
enum SideSetting: String, CaseIterable { case right, left, either }
enum ModeSetting: String { case hold, tap }
enum HotkeyAction: Equatable { case none, startRecording, stopAndSend, cancel }

struct HotkeyOutput: Equatable {
    var action: HotkeyAction = .none
    var deadline: TimeInterval? = nil
}

struct HotkeyMachine {
    static let armDelay: TimeInterval = 0.25
    static let tapMax: TimeInterval = 0.4
    // The server's limit is 120 s.
    static let maxSeconds: TimeInterval = 118

    enum Phase: Equatable { case idle, armed(TimeInterval), recording(TimeInterval), busy }
    // The orb is the pointer trigger; it ignores the side setting.
    enum Trigger { case key, pointer }

    var mode: ModeSetting
    var side: SideSetting
    private(set) var phase: Phase = .idle
    // Owner of the current or most recent session; survives finished() so the shell can check its physical state.
    private(set) var trigger = Trigger.key
    private var leftDown = false
    private var rightDown = false
    private var tapStart: TimeInterval?
    private var pointerHeld = false
    private var pointerTapStart: TimeInterval?

    init(mode: ModeSetting = .hold, side: SideSetting = .right) {
        self.mode = mode
        self.side = side
    }

    private func matches(_ key: OptionKey) -> Bool {
        switch side {
        case .either: return true
        case .left: return key == .left
        case .right: return key == .right
        }
    }

    private var matchingHeld: Bool {
        (leftDown && matches(.left)) || (rightDown && matches(.right))
    }

    private mutating func setHeld(_ key: OptionKey, _ down: Bool) {
        if key == .left { leftDown = down } else { rightDown = down }
    }

    private func owns(_ source: Trigger) -> Bool {
        phase == .idle || trigger == source
    }

    var isRecording: Bool {
        if case .recording = phase { return true }
        return false
    }

    // Armed or recording from the orb: a hidden orb could not end it.
    var pointerSessionLive: Bool {
        switch phase {
        case .armed, .recording: return trigger == .pointer
        default: return false
        }
    }

    mutating func optionDown(_ key: OptionKey, bare: Bool, at t: TimeInterval) -> HotkeyOutput {
        guard matches(key) else { return HotkeyOutput() }
        let alreadyHeld = matchingHeld
        setHeld(key, true)
        guard !alreadyHeld, phase != .busy, owns(.key) else { return HotkeyOutput() }
        guard bare else { tapStart = nil; return HotkeyOutput() }
        switch mode {
        case .hold:
            guard phase == .idle else { return HotkeyOutput() }
            trigger = .key
            phase = .armed(t)
            return HotkeyOutput(deadline: t + Self.armDelay)
        case .tap:
            tapStart = t
            return HotkeyOutput()
        }
    }

    mutating func optionUp(_ key: OptionKey, at t: TimeInterval) -> HotkeyOutput {
        guard matches(key) else { return HotkeyOutput() }
        setHeld(key, false)
        guard !matchingHeld, phase != .busy, owns(.key) else { return HotkeyOutput() }
        switch mode {
        case .hold:
            switch phase {
            case .armed: phase = .idle; return HotkeyOutput()
            case .recording: phase = .busy; return HotkeyOutput(action: .stopAndSend)
            default: return HotkeyOutput()
            }
        case .tap:
            defer { tapStart = nil }
            guard let start = tapStart, t - start <= Self.tapMax else { return HotkeyOutput() }
            switch phase {
            case .idle:
                trigger = .key
                phase = .recording(t)
                return HotkeyOutput(action: .startRecording, deadline: t + Self.maxSeconds)
            case .recording:
                phase = .busy
                return HotkeyOutput(action: .stopAndSend)
            default: return HotkeyOutput()
            }
        }
    }

    // A press while still held means the last release was lost: treat it as a fresh press.
    mutating func pointerDown(at t: TimeInterval) -> HotkeyOutput {
        pointerHeld = true
        guard phase != .busy, owns(.pointer) else { return HotkeyOutput() }
        switch mode {
        case .hold:
            guard phase == .idle else { return HotkeyOutput() }
            trigger = .pointer
            phase = .armed(t)
            return HotkeyOutput(deadline: t + Self.armDelay)
        case .tap:
            pointerTapStart = t
            return HotkeyOutput()
        }
    }

    mutating func pointerUp(at t: TimeInterval) -> HotkeyOutput {
        guard pointerHeld else { return HotkeyOutput() }
        pointerHeld = false
        guard phase != .busy, owns(.pointer) else { return HotkeyOutput() }
        switch mode {
        case .hold:
            switch phase {
            case .armed: phase = .idle; return HotkeyOutput()
            case .recording: phase = .busy; return HotkeyOutput(action: .stopAndSend)
            default: return HotkeyOutput()
            }
        case .tap:
            defer { pointerTapStart = nil }
            guard let start = pointerTapStart, t - start <= Self.tapMax else { return HotkeyOutput() }
            switch phase {
            case .idle:
                trigger = .pointer
                phase = .recording(t)
                return HotkeyOutput(action: .startRecording, deadline: t + Self.maxSeconds)
            case .recording:
                phase = .busy
                return HotkeyOutput(action: .stopAndSend)
            default: return HotkeyOutput()
            }
        }
    }

    // A press that became a drag: silent, and only before recording.
    mutating func pointerCancel() {
        pointerHeld = false
        pointerTapStart = nil
        if case .armed = phase, trigger == .pointer { phase = .idle }
    }

    mutating func otherInput(at t: TimeInterval) -> HotkeyOutput {
        tapStart = nil
        guard mode == .hold else { return HotkeyOutput() }
        switch phase {
        case .armed: phase = .idle; return HotkeyOutput()
        case .recording: phase = .idle; return HotkeyOutput(action: .cancel)
        default: return HotkeyOutput()
        }
    }

    mutating func tick(at t: TimeInterval) -> HotkeyOutput {
        switch phase {
        case .armed(let since):
            guard t >= since + Self.armDelay else { return HotkeyOutput(deadline: since + Self.armDelay) }
            phase = .recording(t)
            return HotkeyOutput(action: .startRecording, deadline: t + Self.maxSeconds)
        case .recording(let since):
            guard t >= since + Self.maxSeconds else { return HotkeyOutput(deadline: since + Self.maxSeconds) }
            phase = .busy
            return HotkeyOutput(action: .stopAndSend)
        default:
            return HotkeyOutput()
        }
    }

    // Held flags survive: a missed key-up would swallow the next press, so the shell resyncs
    // them with releaseAll when the session's trigger is not physically down.
    mutating func finished() {
        phase = .idle
        tapStart = nil
        pointerTapStart = nil
    }

    mutating func reset() {
        phase = .idle
        leftDown = false
        rightDown = false
        tapStart = nil
        pointerHeld = false
        pointerTapStart = nil
    }

    mutating func releaseAll(at t: TimeInterval) -> HotkeyOutput {
        leftDown = false
        rightDown = false
        tapStart = nil
        pointerHeld = false
        pointerTapStart = nil
        guard mode == .hold else { return HotkeyOutput() }
        switch phase {
        case .armed: phase = .idle; return HotkeyOutput()
        case .recording: phase = .busy; return HotkeyOutput(action: .stopAndSend)
        default: return HotkeyOutput()
        }
    }
}

func triggerHeld(_ trigger: HotkeyMachine.Trigger, optionDown: Bool, leftButtonDown: Bool) -> Bool {
    trigger == .pointer ? leftButtonDown : optionDown
}

let leftOptionKeyCode: Int64 = 58
let rightOptionKeyCode: Int64 = 61
// Device-dependent bits NX_DEVICELALTKEYMASK / NX_DEVICERALTKEYMASK; CGEventFlags has no per-side flag.
let leftOptionDeviceBit: UInt64 = 0x20
let rightOptionDeviceBit: UInt64 = 0x40

func decodeOption(keyCode: Int64, flags: UInt64) -> (key: OptionKey, down: Bool, bare: Bool)? {
    let key: OptionKey
    switch keyCode {
    case leftOptionKeyCode: key = .left
    case rightOptionKeyCode: key = .right
    default: return nil
    }
    let down = flags & (key == .left ? leftOptionDeviceBit : rightOptionDeviceBit) != 0
    let bare = CGEventFlags(rawValue: flags).intersection([.maskCommand, .maskControl, .maskShift, .maskSecondaryFn]).isEmpty
    return (key, down, bare)
}

let sampleRate = 16_000

func wavData(samples: [Int16], sampleRate: Int) -> Data {
    let dataBytes = samples.count * 2
    var d = Data(capacity: 44 + dataBytes)
    func u32(_ v: Int) { withUnsafeBytes(of: UInt32(v).littleEndian) { d.append(contentsOf: $0) } }
    func u16(_ v: Int) { withUnsafeBytes(of: UInt16(v).littleEndian) { d.append(contentsOf: $0) } }
    d.append(contentsOf: Array("RIFF".utf8)); u32(36 + dataBytes); d.append(contentsOf: Array("WAVE".utf8))
    d.append(contentsOf: Array("fmt ".utf8)); u32(16)
    u16(1); u16(1); u32(sampleRate); u32(sampleRate * 2); u16(2); u16(16)
    d.append(contentsOf: Array("data".utf8)); u32(dataBytes)
    samples.withUnsafeBufferPointer { buf in
        for s in buf { withUnsafeBytes(of: s.littleEndian) { d.append(contentsOf: $0) } }
    }
    return d
}

func wordCount(_ s: String) -> Int {
    s.split(whereSeparator: { $0.isWhitespace }).count
}

let maxTranscriptChars = 4000

// Control, format and line/paragraph separators could act as keystrokes in the target window.
func sanitise(_ s: String) -> String {
    var scalars = String.UnicodeScalarView()
    for u in s.unicodeScalars {
        switch u.properties.generalCategory {
        case .control, .format, .lineSeparator, .paragraphSeparator: scalars.append(" ")
        default: scalars.append(u)
        }
    }
    let collapsed = String(scalars).split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    return String(collapsed.prefix(maxTranscriptChars)).trimmingCharacters(in: .whitespaces)
}

enum TranscribeResult: Equatable { case text(String), noSpeech, failed(String), timedOut, unreachable }

func parseTranscription(status: Int, body: Data) -> TranscribeResult {
    let obj = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
    guard status == 200 else { return .failed((obj?["error"] as? String) ?? "HTTP \(status)") }
    guard let obj = obj, let text = obj["text"] as? String else { return .failed("malformed response") }
    if (obj["no_speech"] as? Bool) == true { return .noSpeech }
    let clean = sanitise(text)
    return clean.isEmpty ? .noSpeech : .text(clean)
}

func transportResult(_ error: Error) -> TranscribeResult {
    (error as? URLError)?.code == .timedOut ? .timedOut : .unreachable
}

let maxReplyBytes = 256 * 1024

// A declared length of -1 means unknown; the received bytes are checked as they arrive.
func replyFits(_ bytes: Int64) -> Bool {
    bytes <= Int64(maxReplyBytes)
}

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

// MARK: - Self-test

// Headless: no GUI, microphone or network; touches only a temporary directory.
func runSelfTest() -> Int32 {
    var passed = 0, failed = 0
    func check(_ name: String, _ ok: Bool) {
        print("\(ok ? "ok  " : "FAIL") \(name)")
        if ok { passed += 1 } else { failed += 1 }
    }
    let arm = HotkeyMachine.armDelay
    let start = HotkeyOutput(action: .startRecording, deadline: 0.3 + HotkeyMachine.maxSeconds)
    let none = HotkeyOutput()

    check("constants: maxSeconds is 118", HotkeyMachine.maxSeconds == 118)
    check("constants: armDelay is 0.25", HotkeyMachine.armDelay == 0.25)
    check("constants: tapMax is 0.4", HotkeyMachine.tapMax == 0.4)
    check("default side is right", HotkeyMachine().side == .right)

    var m = HotkeyMachine()
    check("hold: bare down arms with an armDelay deadline", m.optionDown(.right, bare: true, at: 0) == HotkeyOutput(deadline: arm))
    check("hold: release before arm yields nothing", m.optionUp(.right, at: 0.2) == none)
    check("hold: stale tick after early release yields nothing", m.tick(at: arm) == none && m.phase == .idle)

    m = HotkeyMachine()
    _ = m.optionDown(.right, bare: true, at: 0)
    check("hold: early tick re-asks for the deadline", m.tick(at: 0.1) == HotkeyOutput(deadline: arm))
    check("hold: tick past arm starts recording", m.tick(at: 0.3) == start)
    check("hold: release while recording stops and sends", m.optionUp(.right, at: 2) == HotkeyOutput(action: .stopAndSend))
    check("hold: busy ignores a new press", m.optionDown(.right, bare: true, at: 3) == none && m.phase == .busy)
    check("hold: busy ignores release", m.optionUp(.right, at: 3.1) == none)
    m.finished()
    check("hold: finished() returns to idle", m.phase == .idle)
    check("hold: next press after finished() arms again", m.optionDown(.right, bare: true, at: 4).deadline == 4 + arm)

    m = HotkeyMachine()
    _ = m.optionDown(.right, bare: true, at: 0)
    check("hold: tick at exactly armDelay starts", m.tick(at: arm).action == .startRecording)

    m = HotkeyMachine()
    _ = m.optionDown(.right, bare: true, at: 0)
    check("hold: chord before arm disarms silently", m.otherInput(at: 0.1) == none && m.phase == .idle)
    check("hold: tick after chord yields nothing", m.tick(at: 0.3) == none)
    check("hold: release after chord yields nothing", m.optionUp(.right, at: 0.5) == none)

    m = HotkeyMachine()
    _ = m.optionDown(.right, bare: true, at: 0); _ = m.tick(at: 0.3)
    check("hold: key while recording cancels", m.otherInput(at: 1) == HotkeyOutput(action: .cancel))
    check("hold: release after cancel does nothing", m.optionUp(.right, at: 1.5) == none && m.phase == .idle)

    m = HotkeyMachine(mode: .hold, side: .left)
    check("side left: right key ignored", m.optionDown(.right, bare: true, at: 0) == none && m.phase == .idle)
    check("side left: left key arms", m.optionDown(.left, bare: true, at: 1).deadline == 1 + arm)
    m = HotkeyMachine(mode: .hold, side: .right)
    check("side right: left key ignored", m.optionDown(.left, bare: true, at: 0) == none && m.phase == .idle)
    check("side right: right key arms", m.optionDown(.right, bare: true, at: 1).deadline == 1 + arm)

    m = HotkeyMachine(side: .either)
    _ = m.optionDown(.left, bare: true, at: 0); _ = m.tick(at: 0.3)
    check("either: second key while recording does nothing", m.optionDown(.right, bare: true, at: 1) == none)
    check("either: releasing one of two keeps recording", m.optionUp(.left, at: 2) == none && m.phase == .recording(0.3))
    check("either: releasing the last stops and sends", m.optionUp(.right, at: 3) == HotkeyOutput(action: .stopAndSend))

    m = HotkeyMachine()
    check("hold: non-bare press ignored", m.optionDown(.right, bare: false, at: 0) == none && m.phase == .idle)
    check("hold: tick after non-bare press yields nothing", m.tick(at: 0.5) == none)

    m = HotkeyMachine(mode: .tap)
    _ = m.optionDown(.right, bare: true, at: 0)
    check("tap: quick tap starts recording", m.optionUp(.right, at: 0.3) == start)
    _ = m.optionDown(.right, bare: true, at: 5)
    check("tap: quick tap while recording stops and sends", m.optionUp(.right, at: 5.2) == HotkeyOutput(action: .stopAndSend))
    check("tap: stop leaves busy", m.phase == .busy)
    _ = m.optionDown(.right, bare: true, at: 6)
    check("tap: tap while busy yields nothing", m.optionUp(.right, at: 6.1) == none && m.phase == .busy)
    m = HotkeyMachine(mode: .tap)
    _ = m.optionDown(.right, bare: true, at: 0)
    check("tap: long hold is not a tap", m.optionUp(.right, at: 0.5) == none && m.phase == .idle)
    _ = m.optionDown(.right, bare: true, at: 1); _ = m.otherInput(at: 1.1)
    check("tap: chord is not a tap", m.optionUp(.right, at: 1.2) == none && m.phase == .idle)
    _ = m.optionDown(.right, bare: false, at: 2)
    check("tap: non-bare press is not a tap", m.optionUp(.right, at: 2.1) == none && m.phase == .idle)
    _ = m.optionDown(.right, bare: true, at: 3); _ = m.optionUp(.right, at: 3.1)
    check("tap: typing while recording does not cancel", m.otherInput(at: 4) == none && m.phase == .recording(3.1))
    m = HotkeyMachine(mode: .tap)
    _ = m.optionDown(.right, bare: true, at: 0)
    check("tap: release at exactly tapMax is a tap", m.optionUp(.right, at: HotkeyMachine.tapMax).action == .startRecording)
    m = HotkeyMachine(mode: .tap, side: .either)
    _ = m.optionDown(.left, bare: true, at: 0); _ = m.optionDown(.right, bare: true, at: 0.05)
    let firstUp = m.optionUp(.left, at: 0.1)
    check("tap either: both keys tapped together start once",
          firstUp == none && m.optionUp(.right, at: 0.15).action == .startRecording && m.phase == .recording(0.15))

    m = HotkeyMachine(mode: .tap)
    _ = m.optionDown(.right, bare: true, at: 0); _ = m.optionUp(.right, at: 0.1)
    check("max: tick before the cap yields nothing new", m.tick(at: 60).action == .none)
    check("max: tick at the cap stops and sends", m.tick(at: 0.1 + HotkeyMachine.maxSeconds) == HotkeyOutput(action: .stopAndSend))
    check("max: tap cap leaves busy", m.phase == .busy)
    _ = m.optionDown(.right, bare: true, at: 200)
    check("max: tap after the tap cap yields nothing", m.optionUp(.right, at: 200.1) == none)
    m = HotkeyMachine()
    _ = m.optionDown(.right, bare: true, at: 0); _ = m.tick(at: 0.3)
    check("max: hold mode cap stops and sends", m.tick(at: 0.3 + HotkeyMachine.maxSeconds).action == .stopAndSend)
    check("max: hold cap leaves busy", m.phase == .busy)
    check("max: release after the hold cap yields nothing", m.optionUp(.right, at: 200) == none && m.phase == .busy)

    func resetLeavesIdle(_ mode: ModeSetting, _ prepare: (inout HotkeyMachine) -> Void) -> Bool {
        var r = HotkeyMachine(mode: mode)
        prepare(&r)
        r.reset()
        guard r.phase == .idle else { return false }
        switch mode {
        case .hold: return r.optionDown(.right, bare: true, at: 500) == HotkeyOutput(deadline: 500 + arm)
        case .tap:
            _ = r.optionDown(.right, bare: true, at: 500)
            return r.optionUp(.right, at: 500.1).action == .startRecording
        }
    }
    check("reset: from idle", resetLeavesIdle(.hold) { _ in })
    check("reset: from armed", resetLeavesIdle(.hold) { _ = $0.optionDown(.right, bare: true, at: 0) })
    check("reset: from recording (key still held)", resetLeavesIdle(.hold) {
        _ = $0.optionDown(.right, bare: true, at: 0); _ = $0.tick(at: 0.3)
    })
    check("reset: from busy (key still held)", resetLeavesIdle(.hold) {
        _ = $0.optionDown(.right, bare: true, at: 0); _ = $0.tick(at: 0.3); _ = $0.tick(at: 0.3 + HotkeyMachine.maxSeconds)
    })
    check("reset: tap mode from recording (key held)", resetLeavesIdle(.tap) {
        _ = $0.optionDown(.right, bare: true, at: 0); _ = $0.optionUp(.right, at: 0.1); _ = $0.optionDown(.right, bare: true, at: 1)
    })

    m = HotkeyMachine()
    _ = m.optionDown(.right, bare: true, at: 0)
    check("releaseAll: hold armed disarms", m.releaseAll(at: 0.1) == none && m.phase == .idle)
    check("releaseAll: tick after disarm yields nothing", m.tick(at: 0.3) == none)
    m = HotkeyMachine()
    _ = m.optionDown(.right, bare: true, at: 0); _ = m.tick(at: 0.3)
    check("releaseAll: hold recording stops and sends", m.releaseAll(at: 1) == HotkeyOutput(action: .stopAndSend) && m.phase == .busy)
    m.finished()
    check("releaseAll: next press arms (no stale held flag)", m.optionDown(.right, bare: true, at: 2) == HotkeyOutput(deadline: 2 + arm))
    m = HotkeyMachine(mode: .tap)
    _ = m.optionDown(.right, bare: true, at: 0); _ = m.optionUp(.right, at: 0.1)
    _ = m.optionDown(.right, bare: true, at: 1)
    check("releaseAll: tap recording keeps recording", m.releaseAll(at: 1.1) == none && m.phase == .recording(0.1))
    _ = m.optionDown(.right, bare: true, at: 2)
    check("releaseAll: tap afterwards stops and sends", m.optionUp(.right, at: 2.1) == HotkeyOutput(action: .stopAndSend))

    m = HotkeyMachine()
    check("pointer: press arms with an armDelay deadline", m.pointerDown(at: 0) == HotkeyOutput(deadline: arm))
    check("pointer: second press without release does nothing", m.pointerDown(at: 0.1) == none)
    check("pointer: release before arm is discarded", m.pointerUp(at: 0.2) == none && m.phase == .idle)
    check("pointer: stale tick after early release yields nothing", m.tick(at: arm) == none)
    _ = m.pointerDown(at: 0)
    check("pointer: tick past arm starts recording", m.tick(at: 0.3) == start && m.trigger == .pointer)
    check("pointer: release while recording stops and sends", m.pointerUp(at: 2) == HotkeyOutput(action: .stopAndSend) && m.phase == .busy)
    m.finished()
    _ = m.pointerDown(at: 3); _ = m.tick(at: 3.3)
    check("pointer: hold cap stops and sends", m.tick(at: 3.3 + HotkeyMachine.maxSeconds).action == .stopAndSend)
    check("pointer: release after the cap yields nothing", m.pointerUp(at: 200) == none && m.phase == .busy)
    m = HotkeyMachine(mode: .hold, side: .left)
    check("pointer: bypasses side left", m.pointerDown(at: 0).deadline == arm)
    m = HotkeyMachine(mode: .hold, side: .right)
    check("pointer: bypasses side right", m.pointerDown(at: 0).deadline == arm)

    m = HotkeyMachine()
    _ = m.pointerDown(at: 0)
    m.pointerCancel()
    check("pointer: drag cancels an armed press silently", m.phase == .idle && m.tick(at: 0.3) == none)
    check("pointer: release after a drag yields nothing", m.pointerUp(at: 0.5) == none && m.phase == .idle)
    check("pointer: press after a drag arms again", m.pointerDown(at: 1).deadline == 1 + arm)
    m = HotkeyMachine()
    _ = m.optionDown(.right, bare: true, at: 0)
    m.pointerCancel()
    check("pointer: cancel leaves a key session armed", m.phase == .armed(0))

    m = HotkeyMachine(mode: .tap)
    _ = m.pointerDown(at: 0)
    check("pointer tap: click starts recording", m.pointerUp(at: 0.3) == start && m.trigger == .pointer)
    _ = m.pointerDown(at: 5)
    check("pointer tap: click while recording stops and sends", m.pointerUp(at: 5.2) == HotkeyOutput(action: .stopAndSend))
    m = HotkeyMachine(mode: .tap)
    _ = m.pointerDown(at: 0)
    check("pointer tap: long press is not a click", m.pointerUp(at: 0.5) == none && m.phase == .idle)
    _ = m.pointerDown(at: 1); m.pointerCancel()
    check("pointer tap: drag is not a click", m.pointerUp(at: 1.1) == none && m.phase == .idle)
    _ = m.pointerDown(at: 2); _ = m.pointerUp(at: 2.1)
    check("pointer tap: cap stops and sends", m.tick(at: 2.1 + HotkeyMachine.maxSeconds).action == .stopAndSend)

    m = HotkeyMachine()
    _ = m.optionDown(.right, bare: true, at: 0)
    check("cross: press while a key session is armed is ignored", m.pointerDown(at: 0.1) == none && m.phase == .armed(0))
    check("cross: key session still starts", m.tick(at: 0.3) == start && m.trigger == .key)
    check("cross: release of the ignored press does nothing", m.pointerUp(at: 1) == none && m.phase == .recording(0.3))
    check("cross: key release stops and sends", m.optionUp(.right, at: 2) == HotkeyOutput(action: .stopAndSend))
    m = HotkeyMachine()
    _ = m.pointerDown(at: 0); _ = m.tick(at: 0.3)
    check("cross: Option while the orb records is ignored", m.optionDown(.right, bare: true, at: 1) == none)
    check("cross: Option release while the orb records is ignored", m.optionUp(.right, at: 1.5) == none && m.phase == .recording(0.3))
    check("cross: orb release stops and sends", m.pointerUp(at: 2) == HotkeyOutput(action: .stopAndSend))
    m = HotkeyMachine(mode: .tap)
    _ = m.optionDown(.right, bare: true, at: 0); _ = m.optionUp(.right, at: 0.1)
    _ = m.pointerDown(at: 1)
    check("cross tap: click does not stop a key recording", m.pointerUp(at: 1.1) == none && m.phase == .recording(0.1))
    _ = m.optionDown(.right, bare: true, at: 2)
    check("cross tap: key tap still stops it", m.optionUp(.right, at: 2.1).action == .stopAndSend)
    m = HotkeyMachine(mode: .tap)
    _ = m.pointerDown(at: 0); _ = m.pointerUp(at: 0.1)
    _ = m.optionDown(.right, bare: true, at: 1)
    check("cross tap: key tap does not stop an orb recording", m.optionUp(.right, at: 1.1) == none && m.phase == .recording(0.1))

    m = HotkeyMachine()
    _ = m.pointerDown(at: 0)
    check("pointer releaseAll: armed disarms", m.releaseAll(at: 0.1) == none && m.phase == .idle)
    _ = m.pointerDown(at: 1); _ = m.tick(at: 1.3)
    check("pointer releaseAll: recording stops and sends", m.releaseAll(at: 2) == HotkeyOutput(action: .stopAndSend))
    m.finished()
    check("pointer releaseAll: next press arms (no stale held flag)", m.pointerDown(at: 3) == HotkeyOutput(deadline: 3 + arm))
    m.reset()
    check("pointer reset: next press arms", m.pointerDown(at: 4) == HotkeyOutput(deadline: 4 + arm))

    for mode in [ModeSetting.hold, .tap] {
        func pointerSession(_ m: inout HotkeyMachine, at t: TimeInterval) -> Bool {
            _ = m.pointerDown(at: t)
            let started = mode == .hold ? m.tick(at: t + arm) : m.pointerUp(at: t + 0.1)
            guard started.action == .startRecording, m.trigger == .pointer else { return false }
            if mode == .tap { _ = m.pointerDown(at: t + 1) }
            return m.pointerUp(at: t + 1.1) == HotkeyOutput(action: .stopAndSend)
        }
        func keySession(_ m: inout HotkeyMachine, at t: TimeInterval) -> Bool {
            _ = m.optionDown(.right, bare: true, at: t)
            let started = mode == .hold ? m.tick(at: t + arm) : m.optionUp(.right, at: t + 0.1)
            guard started.action == .startRecording, m.trigger == .key else { return false }
            if mode == .tap { _ = m.optionDown(.right, bare: true, at: t + 1) }
            return m.optionUp(.right, at: t + 1.1) == HotkeyOutput(action: .stopAndSend)
        }
        m = HotkeyMachine(mode: mode)
        check("handover \(mode): orb session completes", pointerSession(&m, at: 0))
        m.finished()
        check("handover \(mode): key session after an orb session", keySession(&m, at: 10))
        m.finished()
        check("handover \(mode): orb session after a key session", pointerSession(&m, at: 20))
    }

    m = HotkeyMachine(mode: .tap)
    _ = m.pointerDown(at: 0)
    check("pointer tap: release at exactly tapMax starts", m.pointerUp(at: HotkeyMachine.tapMax).action == .startRecording)

    m = HotkeyMachine(mode: .tap)
    _ = m.pointerDown(at: 0)
    _ = m.pointerDown(at: 1)
    check("pointer tap: press after a lost release is a fresh press", m.pointerUp(at: 1.1).action == .startRecording)
    _ = m.pointerDown(at: 5)
    _ = m.pointerDown(at: 6)
    check("pointer tap: lost release while recording, next click stops", m.pointerUp(at: 6.1) == HotkeyOutput(action: .stopAndSend))

    m = HotkeyMachine()
    _ = m.pointerDown(at: 0); _ = m.tick(at: 0.3); _ = m.pointerUp(at: 1)
    check("pointer busy: press during busy yields nothing", m.pointerDown(at: 2) == none)
    check("pointer busy: its release yields nothing", m.pointerUp(at: 2.1) == none && m.phase == .busy)
    m.finished()
    check("pointer busy: next press after finished() arms", m.pointerDown(at: 3) == HotkeyOutput(deadline: 3 + arm))

    m = HotkeyMachine()
    _ = m.pointerDown(at: 0)
    check("pointer hold: other input while armed disarms silently", m.otherInput(at: 0.1) == none && m.phase == .idle)
    check("pointer hold: release after that yields nothing", m.pointerUp(at: 0.2) == none)
    _ = m.pointerDown(at: 1); _ = m.tick(at: 1.3)
    check("pointer hold: other input while recording cancels", m.otherInput(at: 2) == HotkeyOutput(action: .cancel) && m.phase == .idle)

    m = HotkeyMachine(mode: .tap)
    _ = m.pointerDown(at: 0); _ = m.pointerUp(at: 0.1)
    check("pointer tap: releaseAll keeps recording", m.releaseAll(at: 0.5) == none && m.phase == .recording(0.1))
    _ = m.pointerDown(at: 1)
    check("pointer tap: click after releaseAll stops", m.pointerUp(at: 1.1) == HotkeyOutput(action: .stopAndSend))
    m.finished()
    _ = m.pointerDown(at: 2)
    check("pointer tap: click after finished() starts", m.pointerUp(at: 2.1) == HotkeyOutput(action: .startRecording, deadline: 2.1 + HotkeyMachine.maxSeconds))
    m.reset()
    _ = m.pointerDown(at: 3)
    check("pointer tap: click after reset() starts", m.phase == .idle && m.pointerUp(at: 3.1).action == .startRecording)

    m = HotkeyMachine()
    check("live: idle is not a live orb session", !m.pointerSessionLive && !m.isRecording)
    _ = m.pointerDown(at: 0)
    check("live: orb armed", m.pointerSessionLive && !m.isRecording)
    _ = m.tick(at: 0.3)
    check("live: orb recording", m.pointerSessionLive && m.isRecording)
    _ = m.pointerUp(at: 1)
    check("live: orb busy is not live", !m.pointerSessionLive && !m.isRecording)
    m.finished()
    _ = m.optionDown(.right, bare: true, at: 2); _ = m.tick(at: 2.3)
    check("live: key recording is not an orb session", !m.pointerSessionLive && m.isRecording)

    check("held: key session follows Option", triggerHeld(.key, optionDown: true, leftButtonDown: false)
          && !triggerHeld(.key, optionDown: false, leftButtonDown: true))
    check("held: orb session follows the left button", triggerHeld(.pointer, optionDown: false, leftButtonDown: true)
          && !triggerHeld(.pointer, optionDown: true, leftButtonDown: false))

    func decodes(_ code: Int64, _ flags: UInt64, _ key: OptionKey, _ down: Bool, _ bare: Bool) -> Bool {
        guard let d = decodeOption(keyCode: code, flags: flags) else { return false }
        return d.key == key && d.down == down && d.bare == bare
    }
    check("decode: left down", decodes(58, 0x80120, .left, true, true))
    check("decode: right down", decodes(61, 0x80140, .right, true, true))
    check("decode: left up", decodes(58, 0x100, .left, false, true))
    check("decode: down with Shift is not bare", decodes(58, 0xA0122, .left, true, false))
    check("decode: left up while right is held", decodes(58, 0x80140, .left, false, true))
    check("decode: right up while left is held", decodes(61, 0x80120, .right, false, true))
    check("decode: down with Command is not bare", decodes(58, 0x180120, .left, true, false))
    check("decode: down with Control is not bare", decodes(58, 0xC0120, .left, true, false))
    check("decode: down with Fn is not bare", decodes(58, 0x880120, .left, true, false))
    check("decode: non-Option keycode is nil", decodeOption(keyCode: 56, flags: 0x20102) == nil)

    let wav = wavData(samples: [0, 1, -1, 32767, -32768], sampleRate: sampleRate)
    let expected: [UInt8] = [
        0x52, 0x49, 0x46, 0x46, 46, 0, 0, 0, 0x57, 0x41, 0x56, 0x45,
        0x66, 0x6D, 0x74, 0x20, 16, 0, 0, 0, 1, 0, 1, 0,
        0x80, 0x3E, 0, 0, 0x00, 0x7D, 0, 0, 2, 0, 16, 0,
        0x64, 0x61, 0x74, 0x61, 10, 0, 0, 0,
        0, 0, 1, 0, 0xFF, 0xFF, 0xFF, 0x7F, 0x00, 0x80,
    ]
    check("wav: 44-byte header + data, exact bytes", Array(wav) == expected)
    check("wav: empty sample array is a bare 44-byte header", wavData(samples: [], sampleRate: sampleRate).count == 44)

    check("words: empty", wordCount("") == 0)
    check("words: whitespace only", wordCount("  \n\t ") == 0)
    check("words: extra whitespace", wordCount("  hello   there  ") == 2)
    check("words: newlines and tabs", wordCount("one\ntwo\tthree\n") == 3)

    check("sanitise: interior newline", sanitise("one\ntwo") == "one two")
    check("sanitise: carriage return", sanitise("one\rtwo") == "one two")
    check("sanitise: tab", sanitise("one\ttwo") == "one two")
    check("sanitise: escape sequence", sanitise("a\u{1B}[201~b") == "a [201~b")
    check("sanitise: U+2028", sanitise("one\u{2028}two") == "one two")
    check("sanitise: U+202E", sanitise("one\u{202E}two") == "one two")
    check("sanitise: capped at 4000", sanitise(String(repeating: "a", count: 5000)).count == 4000)
    check("sanitise: plain text unchanged", sanitise("Hello there, sir.") == "Hello there, sir.")
    check("sanitise: accents and apostrophes kept", sanitise("Café, naïve — it's Zoë’s") == "Café, naïve — it's Zoë’s")

    func parse(_ status: Int, _ s: String) -> TranscribeResult { parseTranscription(status: status, body: Data(s.utf8)) }
    check("parse: text", parse(200, #"{"text": " Hello there. ", "duration_s": 1.2, "no_speech": false}"#) == .text("Hello there."))
    check("parse: text is sanitised", parse(200, #"{"text": "rm -rf x\ny", "no_speech": false}"#) == .text("rm -rf x y"))
    check("parse: no_speech", parse(200, #"{"text": "", "duration_s": 1.0, "no_speech": true}"#) == .noSpeech)
    check("parse: no_speech with text", parse(200, #"{"text": "x", "no_speech": true}"#) == .noSpeech)
    check("parse: whitespace text", parse(200, #"{"text": "  \n ", "duration_s": 1.0, "no_speech": false}"#) == .noSpeech)
    check("parse: error JSON", parse(413, #"{"error": "too large"}"#) == .failed("too large"))
    check("parse: non-200 without JSON", parse(500, "oops") == .failed("HTTP 500"))
    check("parse: 500 with text is failed", parse(500, #"{"text": "x", "no_speech": false}"#) == .failed("HTTP 500"))
    check("parse: redirect is failed", parse(307, "") == .failed("HTTP 307"))
    check("parse: garbage", parse(200, "not json") == .failed("malformed response"))
    check("parse: 200 without text", parse(200, #"{"ok": true}"#) == .failed("malformed response"))
    check("transport: timeout", transportResult(URLError(.timedOut)) == .timedOut)
    check("transport: cannot connect", transportResult(URLError(.cannotConnectToHost)) == .unreachable)

    check("constants: maxReplyBytes is 256 KB", maxReplyBytes == 262_144)
    check("reply: under the cap fits", replyFits(Int64(maxReplyBytes - 1)))
    check("reply: exactly the cap fits", replyFits(Int64(maxReplyBytes)))
    check("reply: over the cap is refused", !replyFits(Int64(maxReplyBytes + 1)))
    check("reply: unknown declared length (-1) fits", replyFits(-1))

    check("focus: same app has not moved", !focusMoved(from: 501, to: 501))
    check("focus: different app has moved", focusMoved(from: 501, to: 502))
    check("focus: unknown both times has not moved", !focusMoved(from: nil, to: nil))
    check("focus: known then unknown has moved", focusMoved(from: 501, to: nil))
    check("focus: unknown then known has moved", focusMoved(from: nil, to: 501))

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

    check("keys: paste when focus stayed", mayPost(.paste, pasted: false, moved: false))
    check("keys: no paste when focus moved", !mayPost(.paste, pasted: false, moved: true))
    check("keys: Return after paste when focus stayed", mayPost(.submit, pasted: true, moved: false))
    check("keys: no Return when focus moved after paste", !mayPost(.submit, pasted: true, moved: true))
    check("keys: no Return when the paste was skipped", !mayPost(.submit, pasted: false, moved: false))

    let fm = FileManager.default
    let tmp = ProcessInfo.processInfo.environment["TMPDIR"] ?? NSTemporaryDirectory()
    let scratch = URL(fileURLWithPath: tmp).appendingPathComponent("pardon-selftest-\(UUID().uuidString)")
    check("mute: temporary directory created", (try? fm.createDirectory(at: scratch, withIntermediateDirectories: false)) != nil)
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
    try? fm.removeItem(at: scratch)
    check("mute: temporary directory removed", !fm.fileExists(atPath: scratch.path))

    runPetSelfTest(check)

    print("self-test: \(passed) passed, \(failed) failed")
    return failed == 0 ? 0 : 1
}

// MARK: - Audio capture

final class Recorder {
    let engine = AVAudioEngine()
    private let lock = NSLock()
    private var samples: [Int16] = []
    private var running = false
    private let outFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: Double(sampleRate), channels: 1, interleaved: true)!
    private var levelHandler: ((Double) -> Void)?
    // Called on the main thread with each buffer's voiceLevel; nil skips the measurement.
    var onLevel: ((Double) -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return levelHandler }
        set { lock.lock(); levelHandler = newValue; lock.unlock() }
    }

    func prepare() {
        _ = engine.inputNode
        engine.prepare()
    }

    func start() -> Bool {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0,
              let converter = AVAudioConverter(from: format, to: outFormat) else { return false }
        lock.lock(); samples = []; lock.unlock()
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.append(buffer, converter)
        }
        do { try engine.start() } catch { input.removeTap(onBus: 0); return false }
        running = true
        return true
    }

    private func append(_ buffer: AVAudioPCMBuffer, _ converter: AVAudioConverter) {
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * outFormat.sampleRate / buffer.format.sampleRate) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: capacity) else { return }
        var fed = false
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, inputStatus in
            if fed { inputStatus.pointee = .noDataNow; return nil }
            fed = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, let channel = out.int16ChannelData else { return }
        let converted = UnsafeBufferPointer(start: channel[0], count: Int(out.frameLength))
        lock.lock()
        samples.append(contentsOf: converted)
        let onLevel = levelHandler
        lock.unlock()
        if let onLevel = onLevel {
            let level = voiceLevel(converted)
            DispatchQueue.main.async { onLevel(level) }
        }
    }

    func stop() -> [Int16] {
        if running {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            running = false
            engine.prepare()
        }
        lock.lock(); defer { samples = []; lock.unlock() }
        return samples
    }
}

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

// MARK: - App

let serverURL = URL(string: "http://127.0.0.1:8881")!
let bundleID = "io.github.abandisch.pardon"
// "PARD": our own synthetic events carry it and the tap ignores them.
let pardonEventTag: Int64 = 0x5041_5244
// ANSI "V" position: used when the current layout has no Unicode data or no key types "v".
let pasteKeyCode: CGKeyCode = 9
let returnKeyCode: CGKeyCode = 36
let pasteDelay: TimeInterval = 0.1
let returnDelay: TimeInterval = 0.15
// Target apps read the pasteboard asynchronously after Cmd-V.
let restoreDelay: TimeInterval = 1.0
let healthInterval: TimeInterval = 10
let permissionInterval: TimeInterval = 2
let keyCheckInterval: TimeInterval = 1
let transcribeTimeout: TimeInterval = 120
let healthTimeout: TimeInterval = 2

enum DefaultsKey: String { case mode, side, autoSubmit, muteKokoro, showOrb, orbOrigin, character }
enum Cue: String, CaseIterable { case start = "Tink", sent = "Pop", nothingHeard = "Purr", error = "Basso" }
enum Health { case ready, needsAccessibility, hotkeyUnavailable, micPending, micDenied, serverDown }

func now() -> TimeInterval { ProcessInfo.processInfo.systemUptime }

// Not final: ReplyCollector subclasses it.
class RedirectRefuser: NSObject, URLSessionTaskDelegate {
    // A 3xx then surfaces as a failed response; the audio is never re-sent elsewhere.
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

// Per-task delegate for /transcribe. A per-task delegate does not get the session delegate's
// redirect handling, so it inherits the refusal.
final class ReplyCollector: RedirectRefuser, URLSessionDataDelegate {
    private var body = Data()
    private var tooLarge = false
    private let done: (TranscribeResult) -> Void

    init(done: @escaping (TranscribeResult) -> Void) {
        self.done = done
        super.init()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        tooLarge = !replyFits(response.expectedContentLength)
        completionHandler(tooLarge ? .cancel : .allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard !tooLarge, replyFits(Int64(body.count + data.count)) else {
            tooLarge = true
            return dataTask.cancel()
        }
        body.append(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let status = (task.response as? HTTPURLResponse)?.statusCode ?? 0
        if tooLarge { return done(.failed("Speech server reply too large")) }
        done(error.map(transportResult) ?? parseTranscription(status: status, body: body))
    }
}

// Must run on the main thread (Text Input Sources).
func currentPasteKeyCode() -> CGKeyCode {
    guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
          let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return pasteKeyCode }
    let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue()
    guard let bytes = CFDataGetBytePtr(data) else { return pasteKeyCode }
    let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
    // No dead keys: each code is translated on its own, never as part of a sequence.
    func translate(_ code: CGKeyCode, modifiers: UInt32) -> String? {
        var deadKeys: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let status = UCKeyTranslate(layout, code, UInt16(kUCKeyActionDown), modifiers, UInt32(LMGetKbdType()),
                                    OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKeys, chars.count, &length, &chars)
        return status == noErr && length > 0 ? String(utf16CodeUnits: chars, count: length) : nil
    }
    return withExtendedLifetime(source) {
        pasteKey(command: { translate($0, modifiers: UInt32(cmdKey >> 8) & 0xFF) },
                 plain: { translate($0, modifiers: 0) })
    }
}

// Every path that leaves recording or busy ends in endSession() or abortSession().
final class AppController: NSObject, NSApplicationDelegate, NSMenuDelegate {
    enum UIState { case idle, listening, transcribing }

    let defaults = UserDefaults.standard
    let recorder = Recorder()
    let mute = KokoroMute()
    var machine = HotkeyMachine()
    var uiState = UIState.idle
    var serverUp: Bool?
    var lastError: String?
    var lastTranscript: String?
    var targetPID: pid_t?
    var sessionID = 0
    var keyCheck: Timer?
    var tap: CFMachPort?
    var tapSource: CFRunLoopSource?
    var statusItem: NSStatusItem!
    var statusLine: NSMenuItem?
    var shown = ""
    var sounds: [Cue: NSSound] = [:]
    var orb: OrbWindow?
    // Persists until the next session's start cue.
    var orbOutcome = OrbOutcome.none
    let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.urlCache = nil
        c.httpCookieStorage = nil
        c.httpShouldSetCookies = false
        c.urlCredentialStorage = nil
        // Audio must not be routed through a system proxy.
        c.connectionProxyDictionary = [:]
        c.waitsForConnectivity = false
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.timeoutIntervalForRequest = transcribeTimeout
        c.timeoutIntervalForResource = 150
        return URLSession(configuration: c, delegate: RedirectRefuser(), delegateQueue: nil)
    }()

    var mode: ModeSetting { ModeSetting(rawValue: defaults.string(forKey: DefaultsKey.mode.rawValue) ?? "") ?? .hold }
    var side: SideSetting { SideSetting(rawValue: defaults.string(forKey: DefaultsKey.side.rawValue) ?? "") ?? .right }
    var micAuthorized: Bool { AVCaptureDevice.authorizationStatus(for: .audio) == .authorized }
    var optionPhysicallyDown: Bool { CGEventSource.flagsState(.combinedSessionState).contains(.maskAlternate) }
    var triggerPhysicallyDown: Bool {
        triggerHeld(machine.trigger, optionDown: optionPhysicallyDown,
                    leftButtonDown: CGEventSource.buttonState(.combinedSessionState, button: .left))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        defaults.register(defaults: [DefaultsKey.mode.rawValue: ModeSetting.hold.rawValue,
                                     DefaultsKey.side.rawValue: SideSetting.right.rawValue,
                                     DefaultsKey.autoSubmit.rawValue: false, DefaultsKey.muteKokoro.rawValue: true,
                                     DefaultsKey.showOrb.rawValue: true])
        machine = HotkeyMachine(mode: mode, side: side)
        mute.release()
        for cue in Cue.allCases { sounds[cue] = NSSound(named: cue.rawValue) }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu
        let orb = OrbWindow(defaults: defaults, menu: menu)
        orb.onPress = { [weak self] in self?.orbPressed() }
        orb.onRelease = { [weak self] in self?.orbReleased() }
        orb.onDrag = { [weak self] in self?.machine.pointerCancel() }
        orb.isRecording = { [weak self] in self?.machine.isRecording ?? false }
        self.orb = orb
        orb.setShown(defaults.bool(forKey: DefaultsKey.showOrb.rawValue))

        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: recorder.engine,
                                               queue: .main) { [weak self] _ in
            guard let self = self, self.uiState == .listening else { return }
            self.cancelRecording(error: "Audio device changed")
        }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.abortSession() }
        }
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.apple.screenIsLocked"),
                                                            object: nil, queue: .main) { [weak self] _ in
            self?.abortSession()
        }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: recorder.prepare()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    if granted { self.recorder.prepare() }
                    self.refreshUI()
                }
            }
        default: break
        }
        let prompt = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(prompt)

        let permissionTimer = Timer.scheduledTimer(withTimeInterval: permissionInterval, repeats: true) { [weak self] _ in
            self?.checkTap()
        }
        permissionTimer.tolerance = 0.5
        let healthTimer = Timer.scheduledTimer(withTimeInterval: healthInterval, repeats: true) { [weak self] _ in
            self?.checkHealth()
        }
        healthTimer.tolerance = 2
        checkTap()
        checkHealth()
        refreshUI()
    }

    func applicationWillTerminate(_ notification: Notification) {
        mute.release()
    }

    // MARK: Event tap

    func checkTap() {
        if AXIsProcessTrusted() {
            if let tap = tap {
                if !CGEvent.tapIsEnabled(tap: tap) { CGEvent.tapEnable(tap: tap, enable: true) }
            } else {
                createTap()
            }
        } else if tap != nil {
            removeTap()
            abortSession()
        }
        refreshUI()
    }

    func createTap() {
        let types: [CGEventType] = [.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        // Must stay minimal, return the event unmodified, and never read characters.
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
            let controller = Unmanaged<AppController>.fromOpaque(refcon).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = controller.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                DispatchQueue.main.async { controller.abortSession() }
            } else if event.getIntegerValueField(.eventSourceUserData) != pardonEventTag {
                let code = event.getIntegerValueField(.keyboardEventKeycode)
                let flags = event.flags
                let location = event.location
                let t = now()
                DispatchQueue.main.async { controller.handle(type, code, flags, location, t) }
            }
            return Unmanaged.passUnretained(event)
        }
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                           eventsOfInterest: mask, callback: callback,
                                           userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        tap = port
        tapSource = source
    }

    func removeTap() {
        guard let port = tap else { return }
        CGEvent.tapEnable(tap: port, enable: false)
        if let source = tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        CFMachPortInvalidate(port)
        tap = nil
        tapSource = nil
    }

    func handle(_ type: CGEventType, _ code: Int64, _ flags: CGEventFlags, _ location: CGPoint, _ t: TimeInterval) {
        // The tap sees a press on the orb before the orb does; it is not a chord.
        if isOrbPress(type: type, onOrb: orb?.contains(location) == true) { return }
        guard type == .flagsChanged, let option = decodeOption(keyCode: code, flags: flags.rawValue) else {
            return feed(machine.otherInput(at: t))
        }
        feed(option.down ? machine.optionDown(option.key, bare: option.bare, at: t) : machine.optionUp(option.key, at: t))
    }

    // Without the tap a paste could not be posted, so the orb does nothing.
    func orbPressed() {
        guard tap != nil else { return }
        feed(machine.pointerDown(at: now()))
    }

    func orbReleased() {
        feed(machine.pointerUp(at: now()))
    }

    // Stale ticks are safe only because tick re-checks the phase.
    func feed(_ out: HotkeyOutput) {
        if let deadline = out.deadline {
            DispatchQueue.main.asyncAfter(deadline: .now() + max(0, deadline - now())) { [weak self] in
                guard let self = self else { return }
                if case .armed = self.machine.phase, !self.triggerPhysicallyDown {
                    return self.feed(self.machine.releaseAll(at: now()))
                }
                self.feed(self.machine.tick(at: now()))
            }
        }
        switch out.action {
        case .none: break
        case .startRecording: startRecording()
        case .stopAndSend: stopAndSend()
        case .cancel: cancelRecording(error: nil)
        }
    }

    // MARK: Session

    func startRecording() {
        sessionID += 1
        guard micAuthorized else { return cancelRecording(error: "Microphone could not start") }
        play(.start)
        if defaults.bool(forKey: DefaultsKey.muteKokoro.rawValue) { mute.engage() }
        syncLevelMeter()
        guard recorder.start() else { return cancelRecording(error: "Microphone could not start") }
        uiState = .listening
        if machine.mode == .hold {
            keyCheck = Timer.scheduledTimer(withTimeInterval: keyCheckInterval, repeats: true) { [weak self] _ in
                guard let self = self, case .recording = self.machine.phase, !self.triggerPhysicallyDown else { return }
                self.feed(self.machine.releaseAll(at: now()))
            }
        }
        refreshUI()
    }

    func syncLevelMeter() {
        recorder.onLevel = orb?.isShown == true ? { [weak self] level in self?.orb?.setLevel(level) } : nil
    }

    func stopKeyCheck() {
        keyCheck?.invalidate()
        keyCheck = nil
    }

    func stopAndSend() {
        stopKeyCheck()
        let samples = recorder.stop()
        targetPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        uiState = .transcribing
        refreshUI()
        guard !samples.isEmpty else { play(.nothingHeard); return endSession() }
        let id = sessionID
        var request = URLRequest(url: serverURL.appendingPathComponent("transcribe"), timeoutInterval: transcribeTimeout)
        request.httpMethod = "POST"
        request.setValue("audio/wav", forHTTPHeaderField: "Content-Type")
        request.httpBody = wavData(samples: samples, sampleRate: sampleRate)
        let task = session.dataTask(with: request)
        task.delegate = ReplyCollector { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self, id == self.sessionID else { return }
                self.received(result)
            }
        }
        task.resume()
    }

    func received(_ result: TranscribeResult) {
        switch result {
        case .text(let text): serverUp = true; deliver(text)
        case .noSpeech: serverUp = true; play(.nothingHeard); endSession()
        case .failed(let reason): serverUp = true; cancelRecording(error: String(sanitise(reason).prefix(80)))
        case .timedOut: cancelRecording(error: "Timed out waiting for the speech server")
        case .unreachable: serverUp = false; cancelRecording(error: "Speech server not reachable")
        }
    }

    func cancelRecording(error: String?) {
        _ = recorder.stop()
        if let error = error {
            lastError = error
            play(.error)
        }
        endSession()
    }

    func endSession() {
        stopKeyCheck()
        mute.release()
        machine.finished()
        if !triggerPhysicallyDown { _ = machine.releaseAll(at: now()) }
        uiState = .idle
        refreshUI()
    }

    func abortSession() {
        sessionID += 1
        stopKeyCheck()
        _ = recorder.stop()
        mute.release()
        machine.reset()
        uiState = .idle
        refreshUI()
    }

    // MARK: Deliver

    func writeTranscript(_ text: String, to pb: NSPasteboard) {
        pb.prepareForNewContents(with: .currentHostOnly)
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        // Clipboard managers that honour this marker skip the transcript.
        item.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        pb.writeObjects([item])
    }

    func deliver(_ text: String) {
        let id = sessionID
        let target = targetPID
        let focusError = "Focus changed; use Copy last transcript"
        func moved() -> Bool { focusMoved(from: target, to: NSWorkspace.shared.frontmostApplication?.processIdentifier) }
        lastTranscript = text
        guard !moved() else { return cancelRecording(error: focusError) }
        let pb = NSPasteboard.general
        let saved: [NSPasteboardItem] = (pb.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }
        writeTranscript(text, to: pb)
        let ours = pb.changeCount
        let submit = defaults.bool(forKey: DefaultsKey.autoSubmit.rawValue) && wordCount(text) >= 3

        var pasted = false
        DispatchQueue.main.asyncAfter(deadline: .now() + pasteDelay) {
            guard id == self.sessionID else { return }
            guard mayPost(.paste, pasted: pasted, moved: moved()) else {
                self.lastError = focusError
                return self.play(.error)
            }
            self.postKey(currentPasteKeyCode(), flags: .maskCommand)
            pasted = true
            self.lastError = nil
            self.play(.sent)
        }
        if submit {
            DispatchQueue.main.asyncAfter(deadline: .now() + pasteDelay + returnDelay) {
                guard id == self.sessionID, mayPost(.submit, pasted: pasted, moved: moved()) else { return }
                self.postKey(returnKeyCode, flags: [])
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + pasteDelay + restoreDelay) {
            if pb.changeCount == ours {
                pb.clearContents()
                if !saved.isEmpty { pb.writeObjects(saved) }
            }
            guard id == self.sessionID else { return }
            self.endSession()
        }
    }

    func postKey(_ key: CGKeyCode, flags: CGEventFlags) {
        // Private state: physically held modifiers (the Option key) must not leak into Cmd-V.
        let source = CGEventSource(stateID: .privateState)
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down) else { continue }
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: pardonEventTag)
            event.post(tap: .cghidEventTap)
        }
    }

    // MARK: Server health

    func checkHealth() {
        guard uiState == .idle else { return }
        let request = URLRequest(url: serverURL.appendingPathComponent("health"), timeoutInterval: healthTimeout)
        session.dataTask(with: request) { [weak self] _, response, _ in
            let ok = (response as? HTTPURLResponse)?.statusCode == 200
            DispatchQueue.main.async {
                self?.serverUp = ok
                self?.refreshUI()
            }
        }.resume()
    }

    // MARK: UI

    // Also sets the orb's outcome, so this must stay ahead of any early return.
    func play(_ cue: Cue) {
        orbOutcome = OrbOutcome(cue)
        updateOrb(health)
        guard let sound = sounds[cue] else { return }
        sound.stop()
        sound.play()
    }

    var health: Health {
        if !AXIsProcessTrusted() { return .needsAccessibility }
        if tap == nil { return .hotkeyUnavailable }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: break
        case .notDetermined: return .micPending
        default: return .micDenied
        }
        return serverUp == false ? .serverDown : .ready
    }

    func statusText(_ health: Health) -> String {
        switch uiState {
        case .listening: return "Listening…"
        case .transcribing: return "Transcribing…"
        case .idle:
            switch health {
            case .ready: return lastError.map { "Ready — last attempt failed: \($0)" } ?? "Ready"
            case .needsAccessibility: return "Grant Accessibility in System Settings"
            case .hotkeyUnavailable: return "Hotkey unavailable — switch Pardon off and on in Accessibility"
            case .micPending: return "Waiting for microphone permission"
            case .micDenied: return "Microphone access denied"
            case .serverDown: return "Speech server not running — make run-stt"
            }
        }
    }

    func updateOrb(_ health: Health) {
        orb?.update(orbLook(ui: uiState, health: health, outcome: orbOutcome), label: "Pardon: \(statusText(health))")
    }

    func refreshUI() {
        guard let button = statusItem?.button else { return }
        let health = self.health
        updateOrb(health)
        let text = statusText(health)
        let symbol: String
        switch uiState {
        case .listening: symbol = "mic.fill"
        case .transcribing: symbol = "ellipsis.circle"
        case .idle: symbol = health == .ready ? "mic" : "mic.slash"
        }
        guard "\(symbol)|\(text)" != shown else { return }
        shown = "\(symbol)|\(text)"
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Pardon: \(text)") {
            image.isTemplate = true
            button.image = image
            button.title = ""
        } else {
            button.image = nil
            button.title = uiState == .idle ? (health == .ready ? "P" : "P!") : (uiState == .listening ? "P●" : "P…")
        }
        statusLine?.title = text
    }

    func menuWillOpen(_ menu: NSMenu) {
        checkHealth()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let health = self.health
        let status = NSMenuItem(title: statusText(health), action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        statusLine = status
        let pane = "x-apple.systempreferences:com.apple.preference.security?"
        switch health {
        case .needsAccessibility, .hotkeyUnavailable:
            add(menu, "Open Accessibility Settings…", #selector(openSettings(_:)), on: false, rep: pane + "Privacy_Accessibility")
        case .micDenied:
            add(menu, "Open Microphone Settings…", #selector(openSettings(_:)), on: false, rep: pane + "Privacy_Microphone")
        default: break
        }
        add(menu, "Copy last transcript", #selector(copyLastTranscript(_:)), on: false, rep: "").isEnabled = lastTranscript != nil
        menu.addItem(.separator())
        add(menu, "Hold to talk", #selector(setMode(_:)), on: mode == .hold, rep: ModeSetting.hold.rawValue)
        add(menu, "Tap to toggle", #selector(setMode(_:)), on: mode == .tap, rep: ModeSetting.tap.rawValue)
        menu.addItem(.separator())
        let header = NSMenuItem(title: "Option key", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        for s in SideSetting.allCases {
            add(menu, s.rawValue.capitalized, #selector(setSide(_:)), on: side == s, rep: s.rawValue).indentationLevel = 1
        }
        menu.addItem(.separator())
        add(menu, "Auto-submit (Return)", #selector(toggleDefault(_:)),
            on: defaults.bool(forKey: DefaultsKey.autoSubmit.rawValue), rep: DefaultsKey.autoSubmit.rawValue)
        add(menu, "Mute Kokoro while recording", #selector(toggleDefault(_:)),
            on: defaults.bool(forKey: DefaultsKey.muteKokoro.rawValue), rep: DefaultsKey.muteKokoro.rawValue)
        add(menu, "Show pet", #selector(toggleDefault(_:)),
            on: defaults.bool(forKey: DefaultsKey.showOrb.rawValue), rep: DefaultsKey.showOrb.rawValue)
        let characters = NSMenu()
        characters.autoenablesItems = false
        let active = petCharacter(named: defaults.string(forKey: DefaultsKey.character.rawValue)).displayName
        for c in petCharacters {
            add(characters, c.displayName, #selector(setCharacter(_:)), on: c.displayName == active, rep: c.displayName)
        }
        let character = NSMenuItem(title: "Pet", action: nil, keyEquivalent: "")
        character.submenu = characters
        // A hidden orb has nothing to redraw.
        character.isEnabled = defaults.bool(forKey: DefaultsKey.showOrb.rawValue)
        menu.addItem(character)
        let loginStatus = SMAppService.mainApp.status
        let login = add(menu, loginStatus == .requiresApproval ? "Open at Login (approve in System Settings)" : "Open at Login",
                        #selector(toggleLogin(_:)), on: loginStatus == .enabled, rep: "")
        if loginStatus == .requiresApproval { login.state = .mixed }
        menu.addItem(.separator())
        let info = Bundle.main.infoDictionary
        let version = (info?["PardonBuild"] as? String) ?? (info?["CFBundleShortVersionString"] as? String) ?? "unknown"
        let about = NSMenuItem(title: "Pardon \(version)", action: nil, keyEquivalent: "")
        about.isEnabled = false
        menu.addItem(about)
        menu.addItem(NSMenuItem(title: "Quit Pardon", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @discardableResult
    func add(_ menu: NSMenu, _ title: String, _ action: Selector, on: Bool, rep: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.state = on ? .on : .off
        item.representedObject = rep
        menu.addItem(item)
        return item
    }

    @objc func openSettings(_ sender: NSMenuItem) {
        guard let url = (sender.representedObject as? String).flatMap(URL.init(string:)) else { return }
        NSWorkspace.shared.open(url)
    }

    @objc func copyLastTranscript(_ sender: NSMenuItem) {
        guard let text = lastTranscript else { return }
        writeTranscript(text, to: NSPasteboard.general)
    }

    @objc func setMode(_ sender: NSMenuItem) {
        defaults.set(sender.representedObject as? String, forKey: DefaultsKey.mode.rawValue)
        abortSession()
        machine.mode = mode
    }

    @objc func setSide(_ sender: NSMenuItem) {
        defaults.set(sender.representedObject as? String, forKey: DefaultsKey.side.rawValue)
        abortSession()
        machine.side = side
    }

    @objc func toggleDefault(_ sender: NSMenuItem) {
        guard let key = (sender.representedObject as? String).flatMap(DefaultsKey.init(rawValue:)) else { return }
        defaults.set(!defaults.bool(forKey: key.rawValue), forKey: key.rawValue)
        guard key == .showOrb else { return }
        let visible = defaults.bool(forKey: key.rawValue)
        // A hidden orb could not end its own session: the key ignores it.
        if !visible, machine.pointerSessionLive { abortSession() }
        orb?.setShown(visible)
        syncLevelMeter()
        refreshUI()
    }

    // Only the drawing changes: a session in progress carries on.
    @objc func setCharacter(_ sender: NSMenuItem) {
        let name = sender.representedObject as? String
        guard name != petCharacter(named: defaults.string(forKey: DefaultsKey.character.rawValue)).displayName else { return }
        defaults.set(name, forKey: DefaultsKey.character.rawValue)
        orb?.reloadCharacter()
    }

    @objc func toggleLogin(_ sender: NSMenuItem) {
        let service = SMAppService.mainApp
        switch service.status {
        case .notRegistered, .notFound:
            do {
                try service.register()
                if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
            } catch {
                SMAppService.openSystemSettingsLoginItems()
            }
        case .requiresApproval:
            SMAppService.openSystemSettingsLoginItems()
        default:
            try? service.unregister()
        }
    }
}
