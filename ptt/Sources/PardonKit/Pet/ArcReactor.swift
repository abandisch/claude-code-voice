// The arc reactor: the pet's default character, concentric rings drawn with Core Animation layers.
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
    private typealias Palette = (ring: PetColor.RGB, hot: PetColor.RGB)
    private static let cyan: Palette = ((0.55, 0.92, 1.0), (0.97, 1.0, 1.0))
    private static let amber: Palette = ((1.0, 0.45, 0.2), (1.0, 0.86, 0.7))
    private static let grey: Palette = ((0.6, 0.62, 0.65), (0.86, 0.87, 0.88))
    private static let white: PetColor.RGB = (1, 1, 1)
    private static let plate = CGColor(srgbRed: 0.02, green: 0.06, blue: 0.11, alpha: 0.85)

    let stage = CALayer()
    private let backplate = CALayer()
    let outer = CAShapeLayer()
    let segments = CAShapeLayer()
    let chaser = CAShapeLayer()
    let inner = CAShapeLayer()
    let heart = CALayer()
    private let glow = CAGradientLayer()
    let core = CAGradientLayer()
    let wave = CAShapeLayer()
    private var palette = ArcReactor.cyan
    private var look: PetLook?
    private var reduceMotion = false
    var animatesWhenIdle = true { didSet { if animatesWhenIdle != oldValue { look = nil } } }
    private var shownLevel: CGFloat?

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
        let circle = CGRect(x: (size.width - petDiameter) / 2, y: (size.height - petDiameter) / 2,
                            width: petDiameter, height: petDiameter)
        backplate.frame = circle
        backplate.cornerRadius = petDiameter / 2
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

    func apply(_ look: PetLook, level: Double, reduceMotion: Bool) {
        if look != self.look || reduceMotion != self.reduceMotion {
            self.look = look
            self.reduceMotion = reduceMotion
            restyle(look)
        }
        if look == .listening, !reduceMotion { listen(CGFloat(clampUnit(level))) }
    }

    private func restyle(_ look: PetLook) {
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
        backplate.borderColor = PetColor.cgColor(palette.ring, 0.8)
        outer.strokeColor = PetColor.cgColor(palette.ring, 0.75)
        inner.strokeColor = PetColor.cgColor(palette.ring, 0.9)
        wave.strokeColor = PetColor.cgColor(palette.ring, 1)
        wave.opacity = 0
        chaser.strokeColor = PetColor.cgColor(PetColor.mix(palette.ring, Self.white, 0.6), 1)
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
            guard animatesWhenIdle else { break }
            spin(segments, "spin", period: 40, clockwise: true, from: angles[0], capped: true)
            spin(outer, "counterSpin", period: 60, clockwise: false, from: angles[1], capped: true)
        case .needsPermission: break
        }
    }

    private func idle(_ angles: [Double]) {
        guard animatesWhenIdle else { return }
        spin(segments, "spin", period: 20, clockwise: true, from: angles[0], capped: true)
        spin(outer, "counterSpin", period: 30, clockwise: false, from: angles[1], capped: true)
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
        capIdleFrameRate(group)
        heart.add(group, forKey: "pulse")
    }

    // These layers are not flipped: a negative angle turns clockwise on screen.
    private func spin(_ layer: CALayer, _ key: String, period: CFTimeInterval, clockwise: Bool, from angle: Double, capped: Bool = false) {
        let a = CABasicAnimation(keyPath: "transform.rotation.z")
        a.fromValue = angle
        a.toValue = angle + (clockwise ? -2 : 2) * Double.pi
        a.duration = period
        a.repeatCount = .infinity
        if capped { capIdleFrameRate(a) }
        layer.add(a, forKey: key)
    }

    private func shade(_ level: CGFloat) {
        segments.strokeColor = PetColor.cgColor(PetColor.mix(palette.ring, Self.white, 0.6 * level), 1)
        core.colors = [PetColor.cgColor(palette.hot, 1), PetColor.cgColor(PetColor.mix(palette.ring, Self.white, level), 1)]
        glow.colors = [PetColor.cgColor(PetColor.mix(palette.ring, Self.white, 0.3 * level), 0.55), PetColor.cgColor(palette.ring, 0)]
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
