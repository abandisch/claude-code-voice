import CoreGraphics
import Foundation

struct PetGesture {
    static let dragThreshold: CGFloat = 4
    // A hold recording this press started gives way to a drag only past this distance, within this time of the press.
    static let recordingDragThreshold: CGFloat = 10
    static let recordingDragGrace: TimeInterval = 1.5
    enum Kind: Equatable { case none, press, drag }

    private(set) var kind = Kind.none
    private(set) var origin = CGPoint.zero
    private var pressTime: TimeInterval = 0
    private var sawRecording = false
    private var locked = false

    // The time and cancellable defaults are for the pure-logic checks; the window always passes the clock and the flag.
    mutating func down(at p: CGPoint, time: TimeInterval = 0) {
        kind = .press
        origin = p
        pressTime = time
        sawRecording = false
        locked = false
    }

    // True once, when the press becomes a drag; a press that has seen a recording it may not cancel never drags.
    mutating func moved(to p: CGPoint, recording: Bool, cancellable: Bool = false, at t: TimeInterval = 0) -> Bool {
        guard kind == .press else { return false }
        if recording {
            sawRecording = true
            if !cancellable { locked = true }
        }
        guard !locked else { return false }
        let distance = hypot(p.x - origin.x, p.y - origin.y)
        if sawRecording {
            guard recording, t - pressTime <= Self.recordingDragGrace, distance > Self.recordingDragThreshold else { return false }
        } else {
            guard distance > Self.dragThreshold else { return false }
        }
        kind = .drag
        return true
    }

    mutating func up() -> Kind {
        defer { kind = .none }
        return kind
    }
}
