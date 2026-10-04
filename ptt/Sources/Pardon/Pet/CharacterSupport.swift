import CoreGraphics

typealias RGB = (r: CGFloat, g: CGFloat, b: CGFloat)

func cg(_ c: RGB, _ alpha: CGFloat = 1) -> CGColor { CGColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: alpha) }

func mix(_ a: RGB, _ b: RGB, _ t: CGFloat) -> RGB {
    (a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t)
}

// Unlike smoothLevel's unit, NaN passes through.
func clampUnit(_ x: Double) -> Double { min(max(x, 0), 1) }
