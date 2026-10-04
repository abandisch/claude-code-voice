// The arc reactor: the orb's default character, concentric rings drawn with Core Animation layers.
import AppKit
import QuartzCore

let reactorSegments = 10
let reactorSegmentRadius: CGFloat = 18
let reactorSegmentFill: CGFloat = 0.7
let reactorOuterRadius: CGFloat = 24
let reactorOuterGaps = 3
let reactorOuterFill: CGFloat = 0.88
let reactorChaseLit = 3

// A block and a gap; count of them tile the circle of this radius exactly, so the ring has no seam.
func reactorDashes(radius: CGFloat, count: Int, fill: CGFloat) -> [CGFloat] {
    let period = 2 * .pi * radius / CGFloat(count)
    return [period * fill, period * (1 - fill)]
}

// lit blocks on the segment grid, then one gap for the rest of the lap.
func reactorChaseDashes(radius: CGFloat, count: Int, fill: CGFloat, lit: Int) -> [CGFloat] {
    let d = reactorDashes(radius: radius, count: count, fill: fill)
    return Array(repeating: d, count: lit - 1).flatMap { $0 } + [d[0], d[1] + CGFloat(count - lit) * (d[0] + d[1])]
}

final class ArcReactor: PetCharacter {
    static let displayName = "Arc reactor"
    private typealias RGB = (r: CGFloat, g: CGFloat, b: CGFloat)
    private typealias Palette = (ring: RGB, hot: RGB)
    private static let cyan: Palette = ((0.55, 0.92, 1.0), (0.97, 1.0, 1.0))
    private static let amber: Palette = ((1.0, 0.45, 0.2), (1.0, 0.86, 0.7))
    private static let grey: Palette = ((0.6, 0.62, 0.65), (0.86, 0.87, 0.88))
    private static let white: RGB = (1, 1, 1)
    private static let plate = CGColor(srgbRed: 0.02, green: 0.06, blue: 0.11, alpha: 0.85)

    fileprivate let stage = CALayer()
    private let backplate = CALayer()
    fileprivate let outer = CAShapeLayer()
    fileprivate let segments = CAShapeLayer()
    fileprivate let chaser = CAShapeLayer()
    fileprivate let inner = CAShapeLayer()
    fileprivate let heart = CALayer()
    private let glow = CAGradientLayer()
    fileprivate let core = CAGradientLayer()
    fileprivate let wave = CAShapeLayer()
    private var palette = ArcReactor.cyan
    private var look: OrbLook?
    private var reduceMotion = false
    private var shownLevel: CGFloat?

    private static func cg(_ c: RGB, _ alpha: CGFloat) -> CGColor { CGColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: alpha) }

    private static func mix(_ a: RGB, _ b: RGB, _ t: CGFloat) -> RGB {
        (a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t)
    }

    // The frame is the whole circle, so a ring turns about the circle's centre.
    private static func ring(_ layer: CAShapeLayer, in circle: CGRect, radius: CGFloat, width: CGFloat, dashes: [CGFloat]?) {
        layer.frame = circle
        let c = CGPoint(x: circle.width / 2, y: circle.height / 2)
        layer.path = CGPath(ellipseIn: CGRect(x: c.x - radius, y: c.y - radius, width: 2 * radius, height: 2 * radius), transform: nil)
        layer.fillColor = nil
        layer.lineWidth = width
        layer.lineDashPattern = dashes?.map { NSNumber(value: Double($0)) }
    }

    private static func disc(_ layer: CAGradientLayer, side: CGFloat, in box: CGRect) {
        layer.frame = CGRect(x: box.midX - side / 2, y: box.midY - side / 2, width: side, height: side)
        layer.type = .radial
        layer.startPoint = CGPoint(x: 0.5, y: 0.5)
        layer.endPoint = CGPoint(x: 1, y: 1)
    }

    func makeLayer(size: CGSize) -> CALayer {
        let root = CALayer()
        root.frame = CGRect(origin: .zero, size: size)
        stage.frame = root.bounds
        root.addSublayer(stage)
        let circle = CGRect(x: (size.width - orbDiameter) / 2, y: (size.height - orbDiameter) / 2,
                            width: orbDiameter, height: orbDiameter)
        backplate.frame = circle
        backplate.cornerRadius = orbDiameter / 2
        backplate.backgroundColor = Self.plate
        backplate.borderWidth = 1
        Self.ring(outer, in: circle, radius: reactorOuterRadius, width: 1.5,
                  dashes: reactorDashes(radius: reactorOuterRadius, count: reactorOuterGaps, fill: reactorOuterFill))
        Self.ring(segments, in: circle, radius: reactorSegmentRadius, width: 6,
                  dashes: reactorDashes(radius: reactorSegmentRadius, count: reactorSegments, fill: reactorSegmentFill))
        Self.ring(chaser, in: circle, radius: reactorSegmentRadius, width: 6,
                  dashes: reactorChaseDashes(radius: reactorSegmentRadius, count: reactorSegments, fill: reactorSegmentFill,
                                             lit: reactorChaseLit))
        Self.ring(inner, in: circle, radius: 11, width: 1.5, dashes: nil)
        // Grows from the core to just inside the rim.
        Self.ring(wave, in: circle, radius: 26, width: 1.5, dashes: nil)
        heart.frame = circle
        Self.disc(glow, side: 34, in: heart.bounds)
        Self.disc(core, side: 14, in: heart.bounds)
        core.cornerRadius = 7
        core.masksToBounds = true
        heart.addSublayer(glow)
        heart.addSublayer(core)
        for layer in [backplate, outer, segments, chaser, inner, heart, wave] { stage.addSublayer(layer) }
        restyle(.idle)
        look = .idle
        return root
    }

    func apply(_ look: OrbLook, level: Double, reduceMotion: Bool) {
        if look != self.look || reduceMotion != self.reduceMotion {
            self.look = look
            self.reduceMotion = reduceMotion
            restyle(look)
        }
        if look == .listening, !reduceMotion { listen(CGFloat(min(max(level, 0), 1))) }
    }

    private func restyle(_ look: OrbLook) {
        // Rings never snap: each keeps the angle it is shown at, as its model and as any spin's start.
        let angles = [segments, outer].map {
            (($0.presentation() ?? $0).value(forKeyPath: "transform.rotation.z") as? NSNumber)?.doubleValue ?? 0
        }
        let opacity: Float
        switch look {
        case .listening: palette = Self.cyan; opacity = 1
        case .transcribing: palette = Self.cyan; opacity = 0.95
        case .error: palette = Self.amber; opacity = 0.85
        case .needsPermission: palette = Self.grey; opacity = 0.5
        case .idle, .sent, .nothingHeard: palette = Self.cyan; opacity = 0.9
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in [stage, backplate, outer, segments, chaser, inner, heart, glow, core, wave] { layer.removeAllAnimations() }
        shownLevel = nil
        segments.transform = CATransform3DMakeRotation(CGFloat(angles[0]), 0, 0, 1)
        // The lit blocks sit on the dim grid.
        chaser.transform = segments.transform
        outer.transform = CATransform3DMakeRotation(CGFloat(angles[1]), 0, 0, 1)
        stage.opacity = opacity
        backplate.borderColor = Self.cg(palette.ring, 0.8)
        outer.strokeColor = Self.cg(palette.ring, 0.75)
        inner.strokeColor = Self.cg(palette.ring, 0.9)
        wave.strokeColor = Self.cg(palette.ring, 1)
        wave.opacity = 0
        chaser.strokeColor = Self.cg(Self.mix(palette.ring, Self.white, 0.6), 1)
        chaser.opacity = look == .transcribing ? 1 : 0
        segments.opacity = look == .transcribing ? 0.35 : 0.85
        core.transform = CATransform3DIdentity
        glow.opacity = 0.8
        shade(0)
        // Without motion, listening is told apart by a steady bright core instead.
        if look == .listening, reduceMotion {
            core.transform = CATransform3DMakeScale(1.25, 1.25, 1)
            glow.opacity = 1
            segments.opacity = 1
            shade(1)
        }
        CATransaction.commit()
        guard !reduceMotion else { return }
        switch look {
        case .idle: idle(angles)
        case .sent:
            idle(angles)
            let grow = CABasicAnimation(keyPath: "transform.scale")
            grow.fromValue = 7.0 / 26
            grow.toValue = 1.0
            grow.duration = 0.6
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.9
            fade.toValue = 0.0
            fade.duration = 0.6
            let group = CAAnimationGroup()
            group.animations = [grow, fade]
            group.duration = 0.6
            group.timingFunction = CAMediaTimingFunction(name: .easeOut)
            wave.add(group, forKey: "wave")
        case .nothingHeard:
            idle(angles)
            let dim = CABasicAnimation(keyPath: "opacity")
            dim.fromValue = 0.35
            dim.toValue = Double(opacity)
            dim.duration = 0.8
            dim.timingFunction = CAMediaTimingFunction(name: .easeOut)
            stage.add(dim, forKey: "dim")
        case .listening:
            spin(segments, "spin", period: 3, clockwise: true, from: angles[0])
            spin(outer, "counterSpin", period: 5, clockwise: false, from: angles[1])
        case .transcribing:
            let period = Double(2 * .pi * reactorSegmentRadius) / Double(reactorSegments)
            let steps = CAKeyframeAnimation(keyPath: "lineDashPhase")
            // The ellipse path runs anticlockwise in these unflipped layers; a rising phase moves dashes back along it, so clockwise.
            steps.values = (0..<reactorSegments).map { Double($0) * period }
            steps.calculationMode = .discrete
            steps.duration = 1.2
            steps.repeatCount = .infinity
            chaser.add(steps, forKey: "chase")
            spin(outer, "counterSpin", period: 5, clockwise: false, from: angles[1])
        case .error:
            spin(segments, "spin", period: 40, clockwise: true, from: angles[0])
            spin(outer, "counterSpin", period: 60, clockwise: false, from: angles[1])
        case .needsPermission: break
        }
    }

    private func idle(_ angles: [Double]) {
        spin(segments, "spin", period: 20, clockwise: true, from: angles[0])
        spin(outer, "counterSpin", period: 30, clockwise: false, from: angles[1])
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.75
        fade.toValue = 1.0
        fade.duration = 1.5
        let swell = CABasicAnimation(keyPath: "transform.scale")
        swell.fromValue = 0.9
        swell.toValue = 1.0
        swell.duration = 1.5
        let group = CAAnimationGroup()
        group.animations = [fade, swell]
        group.duration = 1.5
        group.autoreverses = true
        group.repeatCount = .infinity
        group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        heart.add(group, forKey: "pulse")
    }

    // These layers are not flipped: a negative angle turns clockwise on screen.
    private func spin(_ layer: CALayer, _ key: String, period: CFTimeInterval, clockwise: Bool, from angle: Double) {
        let a = CABasicAnimation(keyPath: "transform.rotation.z")
        a.fromValue = angle
        a.toValue = angle + (clockwise ? -2 : 2) * Double.pi
        a.duration = period
        a.repeatCount = .infinity
        layer.add(a, forKey: key)
    }

    private func shade(_ level: CGFloat) {
        segments.strokeColor = Self.cg(Self.mix(palette.ring, Self.white, 0.6 * level), 1)
        core.colors = [Self.cg(palette.hot, 1), Self.cg(Self.mix(palette.ring, Self.white, level), 1)]
        glow.colors = [Self.cg(Self.mix(palette.ring, Self.white, 0.3 * level), 0.55), Self.cg(palette.ring, 0)]
    }

    // The core at full voice is still inside the inner ring.
    private func listen(_ level: CGFloat) {
        if let shown = shownLevel, abs(level - shown) < 0.01 { return }
        shownLevel = level
        let scale = 1 + 0.35 * level
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.1)
        core.transform = CATransform3DMakeScale(scale, scale, 1)
        glow.opacity = Float(0.6 + 0.4 * level)
        segments.opacity = Float(0.75 + 0.25 * level)
        shade(level)
        CATransaction.commit()
    }
}

// MARK: - Self-test

func runReactorSelfTest(_ check: (String, Bool) -> Void) {
    func near(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 1e-9 }
    let lap = 2 * .pi * reactorSegmentRadius
    let seg = reactorDashes(radius: reactorSegmentRadius, count: reactorSegments, fill: reactorSegmentFill)
    check("dashes: segment blocks and gaps tile the circle", seg.count == 2 && near((seg[0] + seg[1]) * CGFloat(reactorSegments), lap))
    check("dashes: ten segment blocks", reactorSegments == 10 && Int((lap / (seg[0] + seg[1])).rounded()) == 10
          && seg.allSatisfy { $0 > 0 })
    let out = reactorDashes(radius: reactorOuterRadius, count: reactorOuterGaps, fill: reactorOuterFill)
    check("dashes: outer ring has three equal gaps", reactorOuterGaps == 3 && out.count == 2 && out.allSatisfy { $0 > 0 }
          && near(3 * (out[0] + out[1]), 2 * .pi * reactorOuterRadius))
    let chase = reactorChaseDashes(radius: reactorSegmentRadius, count: reactorSegments, fill: reactorSegmentFill, lit: reactorChaseLit)
    check("dashes: the chase is lit blocks on the segment grid, one lap long", chase.count == 2 * reactorChaseLit
          && near(chase.reduce(0, +), lap) && near(chase[0], seg[0]) && near(chase[1], seg[1]))
    check("dashes: every chase entry is a segment block or gap, the last gap closing the lap", chase.count == 2 * reactorChaseLit
          && (0..<reactorChaseLit).allSatisfy { near(chase[2 * $0], seg[0]) && ($0 == reactorChaseLit - 1 || near(chase[2 * $0 + 1], seg[1])) }
          && near(chase[2 * reactorChaseLit - 1], seg[1] + CGFloat(reactorSegments - reactorChaseLit) * (seg[0] + seg[1])))
    var ends: [CGPoint] = []
    CGPath(ellipseIn: CGRect(x: -1, y: -1, width: 2, height: 2), transform: nil).applyWithBlock { e in
        switch e.pointee.type {
        case .moveToPoint: ends.append(e.pointee.points[0])
        case .addCurveToPoint: ends.append(e.pointee.points[2])
        default: break
        }
    }
    // The chase's direction rests on this.
    check("dashes: a ring path starts at three o'clock and runs anticlockwise, y up", ends.count >= 2
          && near(ends[0].x, 1) && near(ends[0].y, 0) && ends[1].y > 0.5)

    let side = orbPanelSide
    let reactor = ArcReactor()
    let root = reactor.makeLayer(size: CGSize(width: side, height: side))
    func layers(_ l: CALayer) -> [CALayer] { [l] + (l.sublayers ?? []).flatMap(layers) }
    check("reactor: builds a layer tree of the panel's size", root.bounds.size == CGSize(width: side, height: side)
          && (root.sublayers?.first?.sublayers?.count ?? 0) > 0)
    let centre = CGPoint(x: side / 2, y: side / 2)
    func centred(_ p: CGPoint) -> Bool { abs(p.x - centre.x) < 1e-6 && abs(p.y - centre.y) < 1e-6 }
    check("reactor: every layer and ring path is concentric with the circle", layers(root).allSatisfy { l in
        let path = (l as? CAShapeLayer)?.path?.boundingBoxOfPath ?? l.bounds
        return l.anchorPoint == CGPoint(x: 0.5, y: 0.5) && centred(l.convert(CGPoint(x: l.bounds.midX, y: l.bounds.midY), to: root))
            && centred(l.convert(CGPoint(x: path.midX, y: path.midY), to: root))
    })
    check("reactor: the stage holds exactly seven layers", reactor.stage.sublayers?.count == 7)
    func radius(_ l: CAShapeLayer) -> CGFloat { (l.path?.boundingBoxOfPath.width ?? 0) / 2 }
    func dashed(_ l: CAShapeLayer, _ want: [CGFloat]) -> Bool {
        let have = l.lineDashPattern?.map { CGFloat($0.doubleValue) } ?? []
        return have.count == want.count && zip(have, want).allSatisfy { abs($0 - $1) < 1e-6 }
    }
    check("reactor: each dashed ring's pattern is the one for its own radius",
          dashed(reactor.outer, reactorDashes(radius: radius(reactor.outer), count: reactorOuterGaps, fill: reactorOuterFill))
          && dashed(reactor.segments, reactorDashes(radius: radius(reactor.segments), count: reactorSegments, fill: reactorSegmentFill))
          && dashed(reactor.chaser, reactorChaseDashes(radius: radius(reactor.chaser), count: reactorSegments,
                                                       fill: reactorSegmentFill, lit: reactorChaseLit))
          && reactor.inner.lineDashPattern == nil && reactor.wave.lineDashPattern == nil)

    let names: Set = ["spin", "counterSpin", "pulse", "chase", "wave", "dim"]
    func named() -> Set<String> { Set(layers(root).flatMap { $0.animationKeys() ?? [] }).intersection(names) }
    func anim(_ key: String) -> CAAnimation? { layers(root).lazy.compactMap { $0.animation(forKey: key) }.first }
    func turn(_ key: String) -> Double {
        guard let a = anim(key) as? CABasicAnimation else { return 0 }
        return ((a.toValue as? Double) ?? 0) - ((a.fromValue as? Double) ?? 0)
    }
    check("reactor motion: idle spins, counter-spins and pulses", named() == ["spin", "counterSpin", "pulse"])
    let idleSpin = anim("spin")?.duration ?? 0, idleCounter = anim("counterSpin")?.duration ?? 0
    check("reactor motion: segments turn clockwise, the outer ring the other way", turn("spin") < 0 && turn("counterSpin") > 0
          && abs(abs(turn("spin")) - 2 * .pi) < 1e-9)
    check("reactor motion: the spin is on the segment ring, the counter-spin on the outer ring, the pulse on the heart",
          reactor.segments.animation(forKey: "spin") != nil && reactor.outer.animation(forKey: "counterSpin") != nil
          && reactor.heart.animation(forKey: "pulse") != nil)
    func repeats(_ a: CAAnimation?) -> Bool { a == nil || a!.repeatCount != 0 || a!.autoreverses }
    let idleStroke = reactor.outer.strokeColor
    reactor.apply(.listening, level: 0, reduceMotion: false)
    check("reactor motion: listening spins faster and does not pulse", named() == ["spin", "counterSpin"]
          && (anim("spin")?.duration ?? .infinity) < idleSpin && (anim("counterSpin")?.duration ?? .infinity) < idleCounter)
    check("reactor listening: silence leaves the core unscaled", reactor.core.transform.m11 == 1)
    reactor.apply(.listening, level: 1, reduceMotion: false)
    check("reactor listening: the core grows with the voice", reactor.core.transform.m11 > 1.3)
    let loud = reactor.core.transform.m11
    reactor.apply(.listening, level: 0.995, reduceMotion: false)
    let held = reactor.core.transform.m11 == loud
    reactor.apply(.listening, level: 0.5, reduceMotion: false)
    check("reactor listening: a level change under 0.01 is skipped, a larger one is not", held && reactor.core.transform.m11 < loud)
    reactor.apply(.transcribing, level: 0, reduceMotion: false)
    check("reactor motion: transcribing chases instead of spinning", named() == ["chase", "counterSpin"]
          && (anim("chase") as? CAKeyframeAnimation)?.values?.count == reactorSegments)
    let phases = ((anim("chase") as? CAKeyframeAnimation)?.values ?? []).compactMap { ($0 as? NSNumber)?.doubleValue }
    let period = Double(lap) / Double(reactorSegments)
    check("reactor motion: the chase steps one segment at a time, phase rising, so clockwise",
          phases.count == reactorSegments && phases.first == 0 && zip(phases, phases.dropFirst()).allSatisfy { abs($1 - $0 - period) < 1e-9 })
    reactor.apply(.sent, level: 0, reduceMotion: false)
    check("reactor motion: sent sends a wave, then idles", named() == ["wave", "spin", "counterSpin", "pulse"])
    check("reactor motion: the wave runs once", !repeats(anim("wave")))
    reactor.apply(.nothingHeard, level: 0, reduceMotion: false)
    check("reactor motion: nothing heard dims, then idles", named() == ["dim", "spin", "counterSpin", "pulse"])
    check("reactor motion: the dim runs once", !repeats(anim("dim")))
    reactor.apply(.error, level: 0, reduceMotion: false)
    check("reactor motion: error turns slower than idle", named() == ["spin", "counterSpin"] && (anim("spin")?.duration ?? 0) > idleSpin)
    let errorStroke = reactor.outer.strokeColor
    reactor.apply(.needsPermission, level: 0, reduceMotion: false)
    check("reactor motion: needs permission is still", layers(root).allSatisfy { ($0.animationKeys() ?? []).isEmpty })
    check("reactor: error and needs permission are coloured apart from idle", idleStroke != errorStroke
          && idleStroke != reactor.outer.strokeColor && errorStroke != reactor.outer.strokeColor)
    let allLooks: [OrbLook] = [.idle, .listening, .transcribing, .sent, .nothingHeard, .error, .needsPermission]
    check("reactor motion: Reduce Motion stills every look",
          allLooks.allSatisfy { look in
              reactor.apply(look, level: 1, reduceMotion: true)
              return layers(root).allSatisfy { ($0.animationKeys() ?? []).isEmpty }
          })
    reactor.apply(.idle, level: 0, reduceMotion: true)
    let stillScale = reactor.core.transform.m11, stillStroke = reactor.segments.strokeColor, stillOpacity = reactor.segments.opacity
    reactor.apply(.listening, level: 0, reduceMotion: true)
    check("reactor: under Reduce Motion, listening shows a larger core and a brighter segment ring, still",
          reactor.core.transform.m11 > stillScale + 0.1 && (reactor.segments.strokeColor != stillStroke || reactor.segments.opacity > stillOpacity)
          && layers(root).allSatisfy { ($0.animationKeys() ?? []).isEmpty })
    check("reactor: the chase shows only while transcribing", allLooks.allSatisfy { look in
        reactor.apply(look, level: 0, reduceMotion: false)
        return reactor.chaser.opacity == (look == .transcribing ? 1 : 0)
    })

    func rotation(_ l: CALayer) -> Double { (l.value(forKeyPath: "transform.rotation.z") as? NSNumber)?.doubleValue ?? .nan }
    reactor.apply(.needsPermission, level: 0, reduceMotion: false)
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    reactor.segments.transform = CATransform3DMakeRotation(0.7, 0, 0, 1)
    CATransaction.commit()
    reactor.apply(.idle, level: 0, reduceMotion: false)
    let carried = (anim("spin") as? CABasicAnimation)?.fromValue as? Double
    check("reactor motion: a spin starts from the ring's own angle", carried != nil && abs(carried! - rotation(reactor.segments)) < 1e-9
          && abs(carried! - 0.7) < 0.05)
    reactor.apply(.transcribing, level: 0, reduceMotion: false)
    check("reactor: the chase sits on the dim grid", rotation(reactor.chaser) == rotation(reactor.segments))
    check("reactor: transcribing leaves the segment ring where it was", abs(rotation(reactor.segments) - 0.7) < 0.05)
    reactor.apply(.transcribing, level: 0, reduceMotion: true)
    reactor.apply(.idle, level: 0, reduceMotion: true)
    check("reactor: Reduce Motion and leaving transcribing leave the ring where it was",
          abs(rotation(reactor.segments) - 0.7) < 0.05 && rotation(reactor.chaser) == rotation(reactor.segments))

    // Model geometry against the circle itself, corner radii, shadows and stroke widths included; rendered pixels are not testable headless.
    func paints(_ l: CALayer) -> Bool {
        l is CAShapeLayer || l is CAGradientLayer || (l.backgroundColor?.alpha ?? 0) > 0 || l.borderWidth > 0 || l.shadowOpacity > 0
    }
    // Farthest painted point from the centre: a rounded rect's reach is its inset corners plus the rounding.
    func reach(_ l: CALayer, in top: CALayer) -> CGFloat {
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
            (!paints(l) || reach(l, in: top) <= orbDiameter / 2 + 1e-6)
                && (l.animationKeys() ?? []).flatMap { scales(l.animation(forKey: $0)) }.allSatisfy { $0 <= 1 }
        }
    }
    let probe = CALayer()
    probe.frame = CGRect(x: 0, y: 0, width: side, height: side)
    let halo = CALayer()
    halo.frame = CGRect(x: orbGlowMargin, y: orbGlowMargin, width: orbDiameter, height: orbDiameter)
    halo.backgroundColor = CGColor(gray: 1, alpha: 1)
    halo.cornerRadius = orbDiameter / 2
    halo.shadowOpacity = 0.3
    halo.shadowRadius = 5
    probe.addSublayer(halo)
    check("inside: the check catches a glow outside the circle", !staysInside(probe))
    halo.shadowOpacity = 0
    let clean = staysInside(probe)
    let swell = CABasicAnimation(keyPath: "transform.scale")
    swell.fromValue = 0.97
    swell.toValue = 1.03
    halo.add(swell, forKey: "breath")
    check("inside: the check catches a swell above full size", clean && !staysInside(probe))
    halo.removeAllAnimations()
    halo.cornerRadius = 0
    let square = CGRect(x: orbGlowMargin, y: orbGlowMargin, width: orbDiameter, height: orbDiameter)
    check("inside: the check catches square corners that fit the square but not the circle",
          square.contains(halo.frame) && !staysInside(probe))
    halo.cornerRadius = orbDiameter / 2
    let rim = CAShapeLayer()
    rim.frame = halo.frame
    rim.path = CGPath(ellipseIn: CGRect(x: 0.5, y: 0.5, width: orbDiameter - 1, height: orbDiameter - 1), transform: nil)
    rim.lineWidth = 1
    probe.addSublayer(rim)
    let snug = staysInside(probe)
    rim.lineWidth = 2
    check("inside: the check catches a ring whose stroke crosses the rim", snug && !staysInside(probe))
    rim.lineWidth = 1
    let sheen = CAGradientLayer()
    sheen.frame = halo.frame
    sheen.cornerRadius = orbDiameter / 2
    probe.addSublayer(sheen)
    let unmasked = staysInside(probe)
    sheen.masksToBounds = true
    check("inside: the check counts a gradient's rounding only when it masks", !unmasked && staysInside(probe))
    let fresh = ArcReactor()
    let drawn = fresh.makeLayer(size: CGSize(width: side, height: side))
    for look in [OrbLook.idle, .sent, .nothingHeard, .transcribing, .error, .needsPermission, .listening] {
        fresh.apply(.listening, level: 1, reduceMotion: false)
        fresh.apply(look, level: 1, reduceMotion: false)
        check("inside: reactor \(look) paints only inside the circle", staysInside(drawn))
    }
    fresh.apply(.listening, level: 1, reduceMotion: true)
    check("inside: reactor listening under Reduce Motion paints only inside the circle", staysInside(drawn))
}
