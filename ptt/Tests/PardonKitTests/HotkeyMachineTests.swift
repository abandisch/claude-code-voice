import Foundation
import Testing
@testable import PardonKit

private let arm = HotkeyMachine.armDelay
private let start = HotkeyOutput(action: .startRecording, deadline: 0.3 + HotkeyMachine.maxSeconds)
private let none = HotkeyOutput()

@Suite struct HotkeyMachineTests {
    @Test func constants() {
        check("constants: maxSeconds is 118", HotkeyMachine.maxSeconds == 118)
        check("constants: armDelay is 0.25", HotkeyMachine.armDelay == 0.25)
        check("constants: tapMax is 0.4", HotkeyMachine.tapMax == 0.4)
        check("default side is right", HotkeyMachine().side == .right)
    }

    @Test func hold() {
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
    }

    @Test func side() {
        var m = HotkeyMachine(mode: .hold, side: .left)
        check("side left: right key ignored", m.optionDown(.right, bare: true, at: 0) == none && m.phase == .idle)
        check("side left: left key arms", m.optionDown(.left, bare: true, at: 1).deadline == 1 + arm)
        m = HotkeyMachine(mode: .hold, side: .right)
        check("side right: left key ignored", m.optionDown(.left, bare: true, at: 0) == none && m.phase == .idle)
        check("side right: right key arms", m.optionDown(.right, bare: true, at: 1).deadline == 1 + arm)
    }

    @Test func either() {
        var m = HotkeyMachine(side: .either)
        _ = m.optionDown(.left, bare: true, at: 0); _ = m.tick(at: 0.3)
        check("either: second key while recording does nothing", m.optionDown(.right, bare: true, at: 1) == none)
        check("either: releasing one of two keeps recording", m.optionUp(.left, at: 2) == none && m.phase == .recording(0.3))
        check("either: releasing the last stops and sends", m.optionUp(.right, at: 3) == HotkeyOutput(action: .stopAndSend))
    }

    @Test func holdNonBarePress() {
        var m = HotkeyMachine()
        check("hold: non-bare press ignored", m.optionDown(.right, bare: false, at: 0) == none && m.phase == .idle)
        check("hold: tick after non-bare press yields nothing", m.tick(at: 0.5) == none)
    }

    @Test func tap() {
        var m = HotkeyMachine(mode: .tap)
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
    }

    @Test func maxCap() {
        var m = HotkeyMachine(mode: .tap)
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
    }

    @Test func reset() {
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
    }

    @Test func releaseAll() {
        var m = HotkeyMachine()
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
    }

    @Test func pointer() {
        var m = HotkeyMachine()
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
    }

    @Test func pointerDrag() {
        var m = HotkeyMachine()
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
    }

    @Test func pointerTap() {
        var m = HotkeyMachine(mode: .tap)
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
    }

    @Test func cross() {
        var m = HotkeyMachine()
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
    }

    @Test func pointerReleaseAll() {
        var m = HotkeyMachine()
        _ = m.pointerDown(at: 0)
        check("pointer releaseAll: armed disarms", m.releaseAll(at: 0.1) == none && m.phase == .idle)
        _ = m.pointerDown(at: 1); _ = m.tick(at: 1.3)
        check("pointer releaseAll: recording stops and sends", m.releaseAll(at: 2) == HotkeyOutput(action: .stopAndSend))
        m.finished()
        check("pointer releaseAll: next press arms (no stale held flag)", m.pointerDown(at: 3) == HotkeyOutput(deadline: 3 + arm))
        m.reset()
        check("pointer reset: next press arms", m.pointerDown(at: 4) == HotkeyOutput(deadline: 4 + arm))
    }

    @Test func handover() {
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
            var m = HotkeyMachine(mode: mode)
            check("handover \(mode): orb session completes", pointerSession(&m, at: 0))
            m.finished()
            check("handover \(mode): key session after an orb session", keySession(&m, at: 10))
            m.finished()
            check("handover \(mode): orb session after a key session", pointerSession(&m, at: 20))
        }
    }

    @Test func pointerTapEdges() {
        var m = HotkeyMachine(mode: .tap)
        _ = m.pointerDown(at: 0)
        check("pointer tap: release at exactly tapMax starts", m.pointerUp(at: HotkeyMachine.tapMax).action == .startRecording)

        m = HotkeyMachine(mode: .tap)
        _ = m.pointerDown(at: 0)
        _ = m.pointerDown(at: 1)
        check("pointer tap: press after a lost release is a fresh press", m.pointerUp(at: 1.1).action == .startRecording)
        _ = m.pointerDown(at: 5)
        _ = m.pointerDown(at: 6)
        check("pointer tap: lost release while recording, next click stops", m.pointerUp(at: 6.1) == HotkeyOutput(action: .stopAndSend))
    }

    @Test func pointerBusy() {
        var m = HotkeyMachine()
        _ = m.pointerDown(at: 0); _ = m.tick(at: 0.3); _ = m.pointerUp(at: 1)
        check("pointer busy: press during busy yields nothing", m.pointerDown(at: 2) == none)
        check("pointer busy: its release yields nothing", m.pointerUp(at: 2.1) == none && m.phase == .busy)
        m.finished()
        check("pointer busy: next press after finished() arms", m.pointerDown(at: 3) == HotkeyOutput(deadline: 3 + arm))
    }

    @Test func pointerHold() {
        var m = HotkeyMachine()
        _ = m.pointerDown(at: 0)
        check("pointer hold: other input while armed disarms silently", m.otherInput(at: 0.1) == none && m.phase == .idle)
        check("pointer hold: release after that yields nothing", m.pointerUp(at: 0.2) == none)
        _ = m.pointerDown(at: 1); _ = m.tick(at: 1.3)
        check("pointer hold: other input while recording cancels", m.otherInput(at: 2) == HotkeyOutput(action: .cancel) && m.phase == .idle)
    }

    @Test func pointerTapReleaseAll() {
        var m = HotkeyMachine(mode: .tap)
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
    }

    @Test func live() {
        var m = HotkeyMachine()
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
    }

    @Test func held() {
        check("held: key session follows Option", triggerHeld(.key, optionDown: true, leftButtonDown: false)
              && !triggerHeld(.key, optionDown: false, leftButtonDown: true))
        check("held: orb session follows the left button", triggerHeld(.pointer, optionDown: false, leftButtonDown: true)
              && !triggerHeld(.pointer, optionDown: true, leftButtonDown: false))
    }
}
