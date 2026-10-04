import CoreGraphics
import Testing
@testable import PardonKit

@Suite struct PetGestureTests {
    @Test func pressAndDrag() {
        var g = PetGesture()
        g.down(at: CGPoint(x: 100, y: 100))
        check("gesture: still press is a press", g.up() == .press && g.kind == .none)
        check("gesture: move before a press does nothing", !g.moved(to: CGPoint(x: 500, y: 500), recording: false) && g.kind == .none)
        g.down(at: CGPoint(x: 100, y: 100))
        check("gesture: exactly the threshold is still a press", !g.moved(to: CGPoint(x: 104, y: 100), recording: false) && g.kind == .press)
        check("gesture: past the threshold becomes a drag", g.moved(to: CGPoint(x: 103, y: 103), recording: false) && g.kind == .drag)
        check("gesture: a drag is reported once", !g.moved(to: CGPoint(x: 150, y: 150), recording: false))
        check("gesture: release ends a drag", g.up() == .drag && g.kind == .none)
        g.down(at: CGPoint(x: 100, y: 100))
        check("gesture: drag the other way", g.moved(to: CGPoint(x: 95, y: 100), recording: false))
        g.down(at: CGPoint(x: 100, y: 100))
        check("gesture: movement while recording is ignored", !g.moved(to: CGPoint(x: 200, y: 100), recording: true) && g.kind == .press)
        check("gesture: a press that saw recording never drags", !g.moved(to: CGPoint(x: 300, y: 100), recording: false))
        check("gesture: release after recording is a press", g.up() == .press)
        g.down(at: CGPoint(x: 100, y: 100))
        check("gesture: a new press clears the recording lock", g.moved(to: CGPoint(x: 110, y: 100), recording: false))
        _ = g.up()
        g.down(at: CGPoint(x: 100, y: 100))
        check("gesture: a small move while recording locks", !g.moved(to: CGPoint(x: 101, y: 100), recording: true)
              && !g.moved(to: CGPoint(x: 300, y: 100), recording: false) && g.kind == .press)
        _ = g.up()
        var fresh = PetGesture()
        check("gesture: release without a press is nothing", fresh.up() == .none)
        g.down(at: .zero)
        check("gesture: diagonal 4.10 is a drag", g.moved(to: CGPoint(x: 2.9, y: 2.9), recording: false))
        _ = g.up()
        g.down(at: .zero)
        check("gesture: diagonal 3.96 is a press", !g.moved(to: CGPoint(x: 2.8, y: 2.8), recording: false) && g.kind == .press)
    }

    @Test func recordingDrag() {
        let o = CGPoint(x: 100, y: 100), grace = PetGesture.recordingDragGrace
        check("gesture: recording drag needs 10 pt within 1.5 s", PetGesture.recordingDragThreshold == 10 && grace == 1.5)
        var g = PetGesture()
        g.down(at: o, time: 0)
        check("gesture: own recording, exactly 10 pt is still a press",
              !g.moved(to: CGPoint(x: 110, y: 100), recording: true, cancellable: true, at: 0.5) && g.kind == .press)
        check("gesture: own recording, past 10 pt within grace becomes a drag",
              g.moved(to: CGPoint(x: 110.5, y: 100), recording: true, cancellable: true, at: 0.5) && g.kind == .drag)
        check("gesture: a recording drag is reported once",
              !g.moved(to: CGPoint(x: 200, y: 100), recording: false, cancellable: false, at: 0.6) && g.up() == .drag)
        g.down(at: o, time: 10)
        check("gesture: own recording, exactly the grace period still drags",
              g.moved(to: CGPoint(x: 120, y: 100), recording: true, cancellable: true, at: 10 + grace))
        _ = g.up()
        g.down(at: o, time: 10)
        check("gesture: own recording, just past the grace period is ignored",
              !g.moved(to: CGPoint(x: 120, y: 100), recording: true, cancellable: true, at: 10 + grace + 0.01)
              && g.up() == .press)
        g.down(at: o, time: 0)
        check("gesture: small move in grace, large move after it, stays a press",
              !g.moved(to: CGPoint(x: 105, y: 100), recording: true, cancellable: true, at: 0.5)
              && !g.moved(to: CGPoint(x: 200, y: 100), recording: true, cancellable: true, at: 2) && g.up() == .press)
        g.down(at: o, time: 0)
        check("gesture: recording it may not cancel never drags, even in grace",
              !g.moved(to: CGPoint(x: 200, y: 100), recording: true, cancellable: false, at: 0.3)
              && !g.moved(to: CGPoint(x: 300, y: 100), recording: true, cancellable: true, at: 0.4) && g.up() == .press)
        g.down(at: o, time: 0)
        check("gesture: recording ended in grace, no drag",
              !g.moved(to: CGPoint(x: 101, y: 100), recording: true, cancellable: true, at: 0.3)
              && !g.moved(to: CGPoint(x: 200, y: 100), recording: false, cancellable: false, at: 0.8) && g.up() == .press)
        g.down(at: o, time: 0)
        check("gesture: before recording, 4 pt rule with no time limit",
              !g.moved(to: CGPoint(x: 104, y: 100), recording: false, cancellable: false, at: 5)
              && g.moved(to: CGPoint(x: 105, y: 100), recording: false, cancellable: false, at: 5))
        _ = g.up()
        g.down(at: o, time: 0)
        _ = g.moved(to: CGPoint(x: 101, y: 100), recording: true, cancellable: false, at: 0.3)
        g.down(at: o, time: 5)
        check("gesture: a new press clears the lock and the press time",
              g.moved(to: CGPoint(x: 112, y: 100), recording: true, cancellable: true, at: 5.5))
        _ = g.up()
        g.down(at: o, time: 0)
        _ = g.moved(to: CGPoint(x: 101, y: 100), recording: true, cancellable: true, at: 0.3)
        g.down(at: o, time: 1)
        check("gesture: a new press forgets the recording it saw",
              g.moved(to: CGPoint(x: 105, y: 100), recording: false, cancellable: false, at: 1.1))
        _ = g.up()
    }
}
