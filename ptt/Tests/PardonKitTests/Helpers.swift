import QuartzCore
@testable import PardonKit

func capped(_ a: CAAnimation?) -> Bool { a?.preferredFrameRateRange == petIdleFrameRate }
func cappedGroup(_ a: CAAnimation?) -> Bool {
    let children = (a as? CAAnimationGroup)?.animations ?? []
    return capped(a) && children.count == 2 && children.allSatisfy(capped)
}
func uncapped(_ a: CAAnimation?) -> Bool {
    guard let a = a else { return false }
    return ([a] + ((a as? CAAnimationGroup)?.animations ?? [])).allSatisfy { $0.preferredFrameRateRange == .default }
}

func keys(_ l: CALayer) -> [String] { (l.animationKeys() ?? []) + (l.sublayers ?? []).flatMap(keys) }
func named(_ l: CALayer) -> [String] { keys(l).filter { ["breath", "swirl", "once"].contains($0) } }
func layers(_ l: CALayer) -> [CALayer] { [l] + (l.sublayers ?? []).flatMap(layers) }

// Model geometry against the circle itself, corner radii, shadows and stroke widths included; rendered pixels are not testable headless.
func paints(_ l: CALayer) -> Bool {
    l is CAShapeLayer || l is CAGradientLayer || (l.backgroundColor?.alpha ?? 0) > 0 || l.borderWidth > 0 || l.shadowOpacity > 0
}
// Farthest painted point from the centre: a rounded rect's reach is its inset corners plus the rounding.
func reach(_ l: CALayer, in top: CALayer) -> CGFloat {
    let centre = CGPoint(x: petPanelSide / 2, y: petPanelSide / 2)
    var rect = l.bounds, round: CGFloat = 0, stroke: CGFloat = 0
    if let s = l as? CAShapeLayer, let p = s.path {
        rect = p.boundingBoxOfPath
        round = abs(rect.width - rect.height) < 1e-6 ? rect.width / 2 : 0
        stroke = s.lineWidth / 2
    } else if l.masksToBounds || !(l is CAGradientLayer || l.contents != nil) {
        round = min(l.cornerRadius, rect.width / 2, rect.height / 2)
    }
    let o = l.convert(CGPoint.zero, to: top), x = l.convert(CGPoint(x: 1, y: 0), to: top)
    let unit = hypot(x.x - o.x, x.y - o.y)
    let core = rect.insetBy(dx: round, dy: round)
    let corners = [CGPoint(x: core.minX, y: core.minY), CGPoint(x: core.maxX, y: core.minY),
                   CGPoint(x: core.minX, y: core.maxY), CGPoint(x: core.maxX, y: core.maxY)]
    let far = corners.map { p -> CGFloat in let q = l.convert(p, to: top); return hypot(q.x - centre.x, q.y - centre.y) }.max() ?? 0
    let shadow = l.shadowOpacity > 0 ? l.shadowRadius + max(abs(l.shadowOffset.width), abs(l.shadowOffset.height)) : 0
    return far + (round + stroke) * unit + shadow
}
func scales(_ a: CAAnimation?) -> [Double] {
    if let g = a as? CAAnimationGroup { return (g.animations ?? []).flatMap(scales) }
    guard let b = a as? CABasicAnimation, b.keyPath?.hasPrefix("transform.scale") == true else { return [] }
    return [b.fromValue, b.toValue].compactMap { $0 as? Double }
}
func staysInside(_ top: CALayer) -> Bool {
    layers(top).allSatisfy { l in
        (!paints(l) || reach(l, in: top) <= petDiameter / 2 + 1e-6)
            && (l.animationKeys() ?? []).flatMap { scales(l.animation(forKey: $0)) }.allSatisfy { $0 <= 1 }
    }
}
