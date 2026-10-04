import CoreGraphics
import Testing
@testable import PardonKit

@Suite struct PetColorTests {
    @Test func cgColor() {
        let c: PetColor.RGB = (0.2, 0.4, 0.6)
        check("colour: default alpha is 1", PetColor.cgColor(c).alpha == 1)
        check("colour: explicit alpha is honoured", PetColor.cgColor(c, 0.55).alpha == 0.55)
        check("colour: components pass through in order", PetColor.cgColor((0.25, 0.5, 0.75)).components == [0.25, 0.5, 0.75, 1])
    }

    @Test func mix() {
        let a: PetColor.RGB = (0, 0.5, 1), b: PetColor.RGB = (1, 0.25, 0)
        func same(_ x: PetColor.RGB, _ y: PetColor.RGB) -> Bool { x.r == y.r && x.g == y.g && x.b == y.b }
        check("mix: t = 0 is the first colour", same(PetColor.mix(a, b, 0), a))
        check("mix: t = 1 is the second colour", same(PetColor.mix(a, b, 1), b))
        check("mix: t = 0.5 is the midpoint", same(PetColor.mix(a, b, 0.5), (0.5, 0.375, 0.5)))
    }
}
