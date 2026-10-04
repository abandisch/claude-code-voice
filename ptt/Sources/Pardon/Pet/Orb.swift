import QuartzCore

final class Orb: PetCharacter {
    static let displayName = "Orb"
    private typealias Palette = (centre: RGB, edge: RGB)
    private static let blue: Palette = ((0.62, 0.80, 1.0), (0.22, 0.48, 0.96))
    private static let white: RGB = (0.97, 0.98, 1.0)
    private static let amber: Palette = ((1.0, 0.72, 0.45), (0.92, 0.36, 0.18))
    private static let grey: Palette = ((0.72, 0.72, 0.74), (0.45, 0.45, 0.48))

    private let stage = CALayer()
    private let glow = CALayer()
    private let body = CAGradientLayer()
    private let shimmer = CAGradientLayer()
    private let flash = CALayer()
    private var look: PetLook?
    private var reduceMotion = false
    // Clearing look forces the next apply past the same-look guard.
    var animatesWhenIdle = true { didSet { if animatesWhenIdle != oldValue { look = nil } } }

    func makeLayer(size: CGSize) -> CALayer {
        let root = CALayer()
        root.frame = CGRect(origin: .zero, size: size)
        stage.frame = root.bounds
        root.addSublayer(stage)
        let circle = CGRect(x: (size.width - petDiameter) / 2, y: (size.height - petDiameter) / 2,
                            width: petDiameter, height: petDiameter)
        for layer in [glow, body, shimmer, flash] {
            layer.frame = circle
            layer.cornerRadius = petDiameter / 2
            stage.addSublayer(layer)
        }
        glow.shadowOffset = .zero
        glow.shadowRadius = 5
        glow.shadowPath = CGPath(ellipseIn: glow.bounds, transform: nil)
        body.type = .radial
        body.startPoint = CGPoint(x: 0.42, y: 0.58)
        body.endPoint = CGPoint(x: 1, y: 1)
        body.masksToBounds = true
        // Keeps the orb visible on a background of its own colour.
        body.borderWidth = 1
        body.borderColor = CGColor(gray: 1, alpha: 0.35)
        shimmer.type = .conic
        shimmer.startPoint = CGPoint(x: 0.5, y: 0.5)
        shimmer.endPoint = CGPoint(x: 0.5, y: 1)
        let clear = CGColor(gray: 1, alpha: 0), bright = CGColor(gray: 1, alpha: 0.6)
        shimmer.colors = [clear, bright, clear, bright, clear]
        shimmer.masksToBounds = true
        flash.backgroundColor = CGColor(gray: 1, alpha: 1)
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
        let palette: Palette
        let opacity: Float
        let glowOpacity: Float
        switch look {
        case .listening: palette = Self.blue; opacity = 1; glowOpacity = 0.8
        case .transcribing: palette = Self.blue; opacity = 0.9; glowOpacity = 0.6
        case .error: palette = Self.amber; opacity = 0.8; glowOpacity = 0.5
        case .needsPermission: palette = Self.grey; opacity = 0.45; glowOpacity = 0
        case .idle, .sent, .nothingHeard: palette = Self.blue; opacity = 0.45; glowOpacity = 0.3
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in [stage, glow, body, shimmer, flash] { layer.removeAllAnimations() }
        stage.transform = CATransform3DIdentity
        stage.opacity = opacity
        body.colors = [cg(palette.centre), cg(palette.edge)]
        glow.backgroundColor = cg(palette.edge)
        glow.shadowColor = cg(palette.edge)
        glow.shadowOpacity = glowOpacity
        shimmer.opacity = look == .transcribing ? 0.7 : 0
        flash.opacity = 0
        CATransaction.commit()
        guard !reduceMotion else { return }
        switch look {
        case .idle, .error: breathe(around: opacity, after: 0)
        case .sent:
            breathe(around: opacity, after: 0)
            once(flash, "opacity", from: 0.9, to: 0, duration: 0.35)
        case .nothingHeard:
            once(stage, "opacity", from: 0.9, to: Double(opacity), duration: 0.8)
            breathe(around: opacity, after: 0.8)
        case .transcribing:
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = 0
            spin.toValue = -2 * Double.pi
            spin.duration = 1.4
            spin.repeatCount = .infinity
            shimmer.add(spin, forKey: "swirl")
        case .listening, .needsPermission: break
        }
    }

    // One cycle about every 4 s.
    private func breathe(around opacity: Float, after delay: CFTimeInterval) {
        guard animatesWhenIdle else { return }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = opacity - 0.12
        fade.toValue = min(opacity + 0.12, 1)
        let swell = CABasicAnimation(keyPath: "transform.scale")
        swell.fromValue = 0.97
        swell.toValue = 1.03
        let group = CAAnimationGroup()
        group.animations = [fade, swell]
        group.duration = 2
        group.autoreverses = true
        group.repeatCount = .infinity
        group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        if delay > 0 { group.beginTime = CACurrentMediaTime() + delay }
        capIdleFrameRate(group)
        stage.add(group, forKey: "breath")
    }

    private func once(_ layer: CALayer, _ keyPath: String, from: Double, to: Double, duration: CFTimeInterval) {
        let a = CABasicAnimation(keyPath: keyPath)
        a.fromValue = from
        a.toValue = to
        a.duration = duration
        a.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(a, forKey: "once")
    }

    private func listen(_ level: CGFloat) {
        let scale = 1 + 0.12 * level
        let edge = mix(Self.blue.edge, Self.white, level * 0.6)
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.1)
        stage.transform = CATransform3DMakeScale(scale, scale, 1)
        body.colors = [cg(mix(Self.blue.centre, Self.white, level)), cg(edge)]
        glow.shadowColor = cg(edge)
        glow.shadowOpacity = Float(0.6 + 0.4 * level)
        CATransaction.commit()
    }
}
