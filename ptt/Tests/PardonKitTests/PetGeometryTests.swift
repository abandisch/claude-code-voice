import CoreGraphics
import Testing
@testable import PardonKit

@Suite struct PetGeometryTests {
    @Test func hit() {
        let circle = CGRect(x: 100, y: 100, width: 56, height: 56)
        check("hit: centre", petHit(CGPoint(x: 128, y: 1000 - 128), circle: circle, primaryHeight: 1000))
        check("hit: on the edge", petHit(CGPoint(x: 156, y: 1000 - 128), circle: circle, primaryHeight: 1000))
        check("hit: just outside the edge", !petHit(CGPoint(x: 156.5, y: 1000 - 128), circle: circle, primaryHeight: 1000))
        check("hit: square corner is outside", !petHit(CGPoint(x: 101, y: 1000 - 101), circle: circle, primaryHeight: 1000))
        check("hit: y is flipped", !petHit(CGPoint(x: 128, y: 120), circle: circle, primaryHeight: 1000)
              && petHit(CGPoint(x: 128, y: 880), circle: circle, primaryHeight: 1000))
        check("hit: top and bottom edges", petHit(CGPoint(x: 128, y: 844), circle: circle, primaryHeight: 1000)
              && petHit(CGPoint(x: 128, y: 900), circle: circle, primaryHeight: 1000)
              && !petHit(CGPoint(x: 128, y: 843.5), circle: circle, primaryHeight: 1000)
              && !petHit(CGPoint(x: 128, y: 900.5), circle: circle, primaryHeight: 1000))
        let lowerLeft = CGRect(x: -300, y: -500, width: 56, height: 56)
        check("hit: display below and left of the primary", petHit(CGPoint(x: -272, y: 1472), circle: lowerLeft, primaryHeight: 1000)
              && petHit(CGPoint(x: -244, y: 1472), circle: lowerLeft, primaryHeight: 1000)
              && !petHit(CGPoint(x: -243.5, y: 1472), circle: lowerLeft, primaryHeight: 1000)
              && !petHit(CGPoint(x: -272, y: 528), circle: lowerLeft, primaryHeight: 1000))
    }

    @Test func press() {
        check("press: left down on the orb", isPetPress(type: .leftMouseDown, onPet: true))
        check("press: left down elsewhere", !isPetPress(type: .leftMouseDown, onPet: false))
        check("press: right down on the orb", !isPetPress(type: .rightMouseDown, onPet: true))
        check("press: other button on the orb", !isPetPress(type: .otherMouseDown, onPet: true))
        check("press: key down", !isPetPress(type: .keyDown, onPet: true))
    }

    @Test func placement() {
        let side = petPanelSide
        let main = CGRect(x: 0, y: 0, width: 1440, height: 875)
        let second = CGRect(x: 1440, y: -200, width: 1920, height: 1055)
        func clamped(_ x: CGFloat, _ y: CGFloat, _ screens: [CGRect]) -> CGPoint {
            clampPet(CGRect(x: x, y: y, width: side, height: side), into: screens).origin
        }
        check("clamp: inside is unchanged", clamped(500, 400, [main]) == CGPoint(x: 500, y: 400))
        check("clamp: left edge", clamped(-30, 400, [main]) == CGPoint(x: 0, y: 400))
        check("clamp: right edge", clamped(1400, 400, [main]) == CGPoint(x: 1440 - side, y: 400))
        check("clamp: bottom edge", clamped(500, -10, [main]) == CGPoint(x: 500, y: 0))
        check("clamp: top edge", clamped(500, 870, [main]) == CGPoint(x: 500, y: 875 - side))
        check("clamp: screen smaller than the orb", clamped(5, 5, [CGRect(x: 10, y: 20, width: 40, height: 40)]) == CGPoint(x: 10, y: 20))
        check("clamp: inside the second screen is unchanged", clamped(2000, -100, [main, second]) == CGPoint(x: 2000, y: -100))
        check("clamp: off the second screen's right edge", clamped(3400, 300, [main, second]) == CGPoint(x: 3360 - side, y: 300))
        check("clamp: straddling picks the larger overlap", clamped(1420, 300, [main, second]) == CGPoint(x: 1440, y: 300))
        check("clamp: off every screen picks the nearest", clamped(-500, 300, [main, second]) == CGPoint(x: 0, y: 300))
        check("clamp: no screens leaves it alone", clamped(-500, 300, []) == CGPoint(x: -500, y: 300))
        check("place: default is bottom-right of the visible frame",
              defaultPetOrigin(in: CGRect(x: 0, y: 70, width: 1440, height: 805), side: side) == CGPoint(x: 1440 - side - 24, y: 94))
        let above = CGRect(x: 0, y: 875, width: 1440, height: 900)
        check("clamp: above a stacked pair picks the upper screen", clamped(500, 2000, [main, above]) == CGPoint(x: 500, y: 1775 - side))
        check("clamp: below a stacked pair picks the lower screen", clamped(500, -500, [main, above]) == CGPoint(x: 500, y: 0))
        let exact = CGRect(x: 10, y: 20, width: side, height: side)
        check("clamp: exact fit", clamped(10, 20, [exact]) == CGPoint(x: 10, y: 20) && clamped(12, 25, [exact]) == CGPoint(x: 10, y: 20))
        check("place: default on an offset visible frame",
              defaultPetOrigin(in: CGRect(x: 1440, y: -130, width: 1920, height: 985), side: side) == CGPoint(x: 3360 - side - 24, y: -106))
    }

    @Test func saved() {
        check("saved: two finite numbers", savedPetOrigin([10.0, 20.0]) == CGPoint(x: 10, y: 20))
        check("saved: missing", savedPetOrigin(nil) == nil)
        check("saved: wrong count", savedPetOrigin([10.0]) == nil && savedPetOrigin([1.0, 2.0, 3.0]) == nil)
        check("saved: NaN", savedPetOrigin([Double.nan, 20.0]) == nil)
        check("saved: infinity", savedPetOrigin([10.0, -Double.infinity]) == nil)
        check("saved: not numbers", savedPetOrigin(["a", "b"]) == nil)
    }
}
