import CoreGraphics

let petDiameter: CGFloat = 56
// The panel is the circle plus this on every side, for the glow.
let petGlowMargin: CGFloat = 8
let petPanelSide = petDiameter + 2 * petGlowMargin
let petScreenMargin: CGFloat = 24

// circle is in AppKit screen coordinates (bottom-left origin); point is a CGEvent location (top-left).
func petHit(_ point: CGPoint, circle: CGRect, primaryHeight: CGFloat) -> Bool {
    let dx = point.x - circle.midX, dy = (primaryHeight - point.y) - circle.midY
    let r = min(circle.width, circle.height) / 2
    return dx * dx + dy * dy <= r * r
}

// Only a left press on the pet is the pet's own; any other click still counts as other input.
func isPetPress(type: CGEventType, onPet: @autoclosure () -> Bool) -> Bool {
    type == .leftMouseDown && onPet()
}

// The screen holding most of the frame, else the nearest one; the frame is moved fully inside it.
func clampPet(_ frame: CGRect, into screens: [CGRect]) -> CGRect {
    func overlap(_ s: CGRect) -> CGFloat {
        let i = s.intersection(frame)
        return i.isNull ? 0 : i.width * i.height
    }
    func distance(_ s: CGRect) -> CGFloat {
        let dx = max(s.minX - frame.midX, 0, frame.midX - s.maxX)
        let dy = max(s.minY - frame.midY, 0, frame.midY - s.maxY)
        return dx * dx + dy * dy
    }
    guard let most = screens.max(by: { overlap($0) < overlap($1) }) else { return frame }
    let s = overlap(most) > 0 ? most : (screens.min(by: { distance($0) < distance($1) }) ?? most)
    var r = frame
    r.origin.x = max(s.minX, min(frame.minX, s.maxX - frame.width))
    r.origin.y = max(s.minY, min(frame.minY, s.maxY - frame.height))
    return r
}

func defaultPetOrigin(in visible: CGRect, side: CGFloat) -> CGPoint {
    CGPoint(x: visible.maxX - side - petScreenMargin, y: visible.minY + petScreenMargin)
}

// Anything but two finite numbers means the default position.
func savedPetOrigin(_ value: Any?) -> CGPoint? {
    guard let a = value as? [Double], a.count == 2, a.allSatisfy(\.isFinite) else { return nil }
    return CGPoint(x: a[0], y: a[1])
}
