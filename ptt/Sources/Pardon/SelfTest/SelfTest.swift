import CoreGraphics
import Foundation

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
    _ = m.pointerCancel()
    check("pointer: drag cancels an armed press silently", m.phase == .idle && m.tick(at: 0.3) == none)
    check("pointer: release after a drag yields nothing", m.pointerUp(at: 0.5) == none && m.phase == .idle)
    check("pointer: press after a drag arms again", m.pointerDown(at: 1).deadline == 1 + arm)
    m = HotkeyMachine()
    _ = m.optionDown(.right, bare: true, at: 0)
    _ = m.pointerCancel()
    check("pointer: cancel leaves a key session armed", m.phase == .armed(0))
    check("pointer: cancel of a key session yields nothing", m.pointerCancel() == none)
    m = HotkeyMachine()
    _ = m.pointerDown(at: 0)
    check("pointer drag: cancel of an armed press yields no action", m.pointerCancel() == none && m.phase == .idle)
    m = HotkeyMachine()
    _ = m.pointerDown(at: 0); _ = m.tick(at: 0.3)
    check("pointer drag: own hold recording is cancellable", m.pointerRecordingCancellable)
    check("pointer drag: cancels it silently", m.pointerCancel() == HotkeyOutput(action: .cancel) && m.phase == .idle)
    check("pointer drag: stale tick after the cancel yields nothing", m.tick(at: 0.3 + HotkeyMachine.maxSeconds) == none)
    m.finished()
    check("pointer drag: the later release yields nothing", m.pointerUp(at: 1) == none && m.phase == .idle)
    check("pointer drag: a fresh press arms again", m.pointerDown(at: 2) == HotkeyOutput(deadline: 2 + arm))
    m = HotkeyMachine()
    _ = m.pointerDown(at: 0); _ = m.tick(at: 0.3); _ = m.pointerDown(at: 1)
    check("pointer drag: a recording from a lost-release press is not cancellable", !m.pointerRecordingCancellable
          && m.pointerCancel() == none && m.phase == .recording(0.3))
    m = HotkeyMachine()
    _ = m.optionDown(.right, bare: true, at: 0); _ = m.tick(at: 0.3); _ = m.pointerDown(at: 1)
    check("pointer drag: a key recording is not cancellable", !m.pointerRecordingCancellable
          && m.pointerCancel() == none && m.phase == .recording(0.3))
    m = HotkeyMachine(mode: .tap)
    _ = m.pointerDown(at: 0); _ = m.pointerUp(at: 0.1); _ = m.pointerDown(at: 1)
    check("pointer drag: a tap stop click is not cancellable", !m.pointerRecordingCancellable
          && m.pointerCancel() == none && m.phase == .recording(0.1))
    m = HotkeyMachine()
    _ = m.pointerDown(at: 0); _ = m.tick(at: 0.3); _ = m.pointerUp(at: 1)
    check("pointer drag: busy after release is not cancellable", !m.pointerRecordingCancellable && m.phase == .busy)

    m = HotkeyMachine(mode: .tap)
    _ = m.pointerDown(at: 0)
    check("pointer tap: click starts recording", m.pointerUp(at: 0.3) == start && m.trigger == .pointer)
    _ = m.pointerDown(at: 5)
    check("pointer tap: click while recording stops and sends", m.pointerUp(at: 5.2) == HotkeyOutput(action: .stopAndSend))
    m = HotkeyMachine(mode: .tap)
    _ = m.pointerDown(at: 0)
    check("pointer tap: long press is not a click", m.pointerUp(at: 0.5) == none && m.phase == .idle)
    _ = m.pointerDown(at: 1); _ = m.pointerCancel()
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
