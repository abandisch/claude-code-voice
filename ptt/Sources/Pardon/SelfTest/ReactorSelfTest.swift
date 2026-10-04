import AppKit
import QuartzCore

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

    let side = petPanelSide
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
    let allLooks: [PetLook] = [.idle, .listening, .transcribing, .sent, .nothingHeard, .error, .needsPermission]
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

    func spinsCapped() -> Bool {
        capped(reactor.segments.animation(forKey: "spin")) && capped(reactor.outer.animation(forKey: "counterSpin"))
    }
    for look in [PetLook.idle, .sent, .nothingHeard] {
        reactor.apply(look, level: 0, reduceMotion: false)
        check("idle rate: reactor \(look) spins and pulse are capped, the pulse's parts too",
              spinsCapped() && cappedGroup(reactor.heart.animation(forKey: "pulse")))
    }
    reactor.apply(.error, level: 0, reduceMotion: false)
    check("idle rate: reactor error spins are capped", spinsCapped() && named() == ["spin", "counterSpin"])
    reactor.apply(.sent, level: 0, reduceMotion: false)
    let rippled = reactor.wave.animation(forKey: "wave")
    reactor.apply(.nothingHeard, level: 0, reduceMotion: false)
    check("idle rate: reactor wave and dim run at the display's rate", uncapped(rippled) && uncapped(reactor.stage.animation(forKey: "dim")))
    reactor.apply(.listening, level: 0, reduceMotion: false)
    check("idle rate: reactor listening spins run at the display's rate",
          uncapped(reactor.segments.animation(forKey: "spin")) && uncapped(reactor.outer.animation(forKey: "counterSpin")))
    reactor.apply(.transcribing, level: 0, reduceMotion: false)
    check("idle rate: reactor chase and transcribing counter-spin run at the display's rate",
          uncapped(reactor.chaser.animation(forKey: "chase")) && uncapped(reactor.outer.animation(forKey: "counterSpin")))

    func keyset() -> Set<String> { Set(layers(root).flatMap { $0.animationKeys() ?? [] }) }
    reactor.apply(.idle, level: 0, reduceMotion: false)
    reactor.animatesWhenIdle = false
    reactor.apply(.idle, level: 0, reduceMotion: false)
    check("animate when idle: turning it off restyles the same look, reactor idle is still", keyset().isEmpty)
    reactor.apply(.sent, level: 0, reduceMotion: false)
    check("animate when idle: off, reactor sent only ripples", keyset() == ["wave"])
    reactor.apply(.nothingHeard, level: 0, reduceMotion: false)
    check("animate when idle: off, reactor nothing heard only dims", keyset() == ["dim"])
    reactor.apply(.error, level: 0, reduceMotion: false)
    check("animate when idle: off, reactor error is still", keyset().isEmpty)
    reactor.apply(.listening, level: 0, reduceMotion: false)
    check("animate when idle: off, reactor listening still spins at the display's rate", keyset() == ["spin", "counterSpin"]
          && uncapped(reactor.segments.animation(forKey: "spin")) && uncapped(reactor.outer.animation(forKey: "counterSpin")))
    reactor.apply(.transcribing, level: 0, reduceMotion: false)
    check("animate when idle: off, reactor transcribing still chases and counter-spins", keyset() == ["chase", "counterSpin"]
          && uncapped(reactor.chaser.animation(forKey: "chase")) && uncapped(reactor.outer.animation(forKey: "counterSpin")))
    reactor.apply(.idle, level: 0, reduceMotion: false)
    let offIdle = keyset().isEmpty
    reactor.animatesWhenIdle = true
    reactor.apply(.idle, level: 0, reduceMotion: false)
    check("animate when idle: turning it back on restyles the same look, reactor idle spins and pulses, capped",
          offIdle && keyset() == ["spin", "counterSpin", "pulse"] && spinsCapped() && cappedGroup(reactor.heart.animation(forKey: "pulse")))
    check("animate when idle: Reduce Motion stills every reactor look either way", [false, true].allSatisfy { on in
        reactor.animatesWhenIdle = on
        return allLooks.allSatisfy { look in
            reactor.apply(look, level: 1, reduceMotion: true)
            return keyset().isEmpty
        }
    })
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    reactor.segments.transform = CATransform3DMakeRotation(0.7, 0, 0, 1)
    reactor.outer.transform = CATransform3DMakeRotation(-0.4, 0, 0, 1)
    CATransaction.commit()
    reactor.animatesWhenIdle = false
    reactor.apply(.idle, level: 0, reduceMotion: false)
    check("animate when idle: off, reactor idle leaves the rings at their angle",
          abs(rotation(reactor.segments) - 0.7) < 0.05 && abs(rotation(reactor.outer) + 0.4) < 0.05)
    reactor.animatesWhenIdle = true

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
            (!paints(l) || reach(l, in: top) <= petDiameter / 2 + 1e-6)
                && (l.animationKeys() ?? []).flatMap { scales(l.animation(forKey: $0)) }.allSatisfy { $0 <= 1 }
        }
    }
    let probe = CALayer()
    probe.frame = CGRect(x: 0, y: 0, width: side, height: side)
    let halo = CALayer()
    halo.frame = CGRect(x: petGlowMargin, y: petGlowMargin, width: petDiameter, height: petDiameter)
    halo.backgroundColor = CGColor(gray: 1, alpha: 1)
    halo.cornerRadius = petDiameter / 2
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
    let square = CGRect(x: petGlowMargin, y: petGlowMargin, width: petDiameter, height: petDiameter)
    check("inside: the check catches square corners that fit the square but not the circle",
          square.contains(halo.frame) && !staysInside(probe))
    halo.cornerRadius = petDiameter / 2
    let rim = CAShapeLayer()
    rim.frame = halo.frame
    rim.path = CGPath(ellipseIn: CGRect(x: 0.5, y: 0.5, width: petDiameter - 1, height: petDiameter - 1), transform: nil)
    rim.lineWidth = 1
    probe.addSublayer(rim)
    let snug = staysInside(probe)
    rim.lineWidth = 2
    check("inside: the check catches a ring whose stroke crosses the rim", snug && !staysInside(probe))
    rim.lineWidth = 1
    let sheen = CAGradientLayer()
    sheen.frame = halo.frame
    sheen.cornerRadius = petDiameter / 2
    probe.addSublayer(sheen)
    let unmasked = staysInside(probe)
    sheen.masksToBounds = true
    check("inside: the check counts a gradient's rounding only when it masks", !unmasked && staysInside(probe))
    let fresh = ArcReactor()
    let drawn = fresh.makeLayer(size: CGSize(width: side, height: side))
    for look in [PetLook.idle, .sent, .nothingHeard, .transcribing, .error, .needsPermission, .listening] {
        fresh.apply(.listening, level: 1, reduceMotion: false)
        fresh.apply(look, level: 1, reduceMotion: false)
        check("inside: reactor \(look) paints only inside the circle", staysInside(drawn))
    }
    fresh.apply(.listening, level: 1, reduceMotion: true)
    check("inside: reactor listening under Reduce Motion paints only inside the circle", staysInside(drawn))
}
