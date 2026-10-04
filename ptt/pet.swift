// The orb: Pardon's floating push-to-talk button, and the character library that draws it.
import AppKit
import QuartzCore

// MARK: - Pure pieces (exercised by --self-test)

enum OrbLook: Equatable { case idle, listening, transcribing, sent, nothingHeard, error, needsPermission }

enum OrbOutcome: Equatable {
    case none, sent, nothingHeard, error

    init(_ cue: Cue) {
        switch cue {
        case .start: self = .none
        case .sent: self = .sent
        case .nothingHeard: self = .nothingHeard
        case .error: self = .error
        }
    }
}

// Listening wins, then transcribing until an outcome ends it, then permissions, then the server, then the outcome.
func orbLook(ui: AppController.UIState, health: Health, outcome: OrbOutcome) -> OrbLook {
    if ui == .listening { return .listening }
    if ui == .transcribing, outcome == .none { return .transcribing }
    switch health {
    case .needsAccessibility, .hotkeyUnavailable, .micPending, .micDenied: return .needsPermission
    case .serverDown: return .error
    case .ready: break
    }
    switch outcome {
    case .none: return .idle
    case .sent: return .sent
    case .nothingHeard: return .nothingHeard
    case .error: return .error
    }
}

// RMS in dBFS onto 0...1: -50 dB (a quiet room) is 0, -10 dB (loud, close speech) is 1.
func voiceLevel<S: Sequence>(_ samples: S) -> Double where S.Element == Int16 {
    var sum = 0.0
    var count = 0
    for s in samples {
        let x = Double(s) / 32768
        sum += x * x
        count += 1
    }
    guard count > 0, sum > 0 else { return 0 }
    return min(max((10 * log10(sum / Double(count)) + 50) / 40, 0), 1)
}

let levelAttack = 0.6
let levelRelease = 0.15

// Anything that is not a finite number counts as silence.
func smoothLevel(_ previous: Double, toward input: Double) -> Double {
    func unit(_ x: Double) -> Double { x.isFinite ? min(max(x, 0), 1) : 0 }
    let p = unit(previous), x = unit(input)
    return p + (x - p) * (x > p ? levelAttack : levelRelease)
}

struct OrbGesture {
    static let dragThreshold: CGFloat = 4
    enum Kind: Equatable { case none, press, drag }

    private(set) var kind = Kind.none
    private(set) var origin = CGPoint.zero
    private var locked = false

    mutating func down(at p: CGPoint) {
        kind = .press
        origin = p
        locked = false
    }

    // True once, when the press becomes a drag. A press that has seen recording never drags.
    mutating func moved(to p: CGPoint, recording: Bool) -> Bool {
        guard kind == .press else { return false }
        if recording { locked = true }
        guard !locked, hypot(p.x - origin.x, p.y - origin.y) > Self.dragThreshold else { return false }
        kind = .drag
        return true
    }

    mutating func up() -> Kind {
        defer { kind = .none }
        return kind
    }
}

let orbDiameter: CGFloat = 56
// The panel is the circle plus this on every side, for the glow.
let orbGlowMargin: CGFloat = 8
let orbPanelSide = orbDiameter + 2 * orbGlowMargin
let orbScreenMargin: CGFloat = 24

// circle is in AppKit screen coordinates (bottom-left origin); point is a CGEvent location (top-left).
func orbHit(_ point: CGPoint, circle: CGRect, primaryHeight: CGFloat) -> Bool {
    let dx = point.x - circle.midX, dy = (primaryHeight - point.y) - circle.midY
    let r = min(circle.width, circle.height) / 2
    return dx * dx + dy * dy <= r * r
}

// Only a left press on the orb is the orb's own; any other click still counts as other input.
func isOrbPress(type: CGEventType, onOrb: @autoclosure () -> Bool) -> Bool {
    type == .leftMouseDown && onOrb()
}

// The screen holding most of the frame, else the nearest one; the frame is moved fully inside it.
func clampOrb(_ frame: CGRect, into screens: [CGRect]) -> CGRect {
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

func defaultOrbOrigin(in visible: CGRect, side: CGFloat) -> CGPoint {
    CGPoint(x: visible.maxX - side - orbScreenMargin, y: visible.minY + orbScreenMargin)
}

// Anything but two finite numbers means the default position.
func savedOrbOrigin(_ value: Any?) -> CGPoint? {
    guard let a = value as? [Double], a.count == 2, a.allSatisfy(\.isFinite) else { return nil }
    return CGPoint(x: a[0], y: a[1])
}

// MARK: - Characters

protocol PetCharacter: AnyObject {
    static var displayName: String { get }
    init()
    // Fills size; the clickable circle is orbDiameter wide at the centre.
    func makeLayer(size: CGSize) -> CALayer
    // Called on every look change and level update; level is 0 unless listening; reduceMotion means static looks only.
    func apply(_ look: OrbLook, level: Double, reduceMotion: Bool)
}

let petCharacters: [PetCharacter.Type] = [Orb.self, ArcReactor.self]
let defaultPetCharacter: PetCharacter.Type = ArcReactor.self

// Nil or an unknown name, such as a removed character's, means the default.
func petCharacter(named name: String?) -> PetCharacter.Type {
    petCharacters.first { $0.displayName == name } ?? defaultPetCharacter
}

final class Orb: PetCharacter {
    static let displayName = "Orb"
    private typealias RGB = (r: CGFloat, g: CGFloat, b: CGFloat)
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
    private var look: OrbLook?
    private var reduceMotion = false

    private static func cg(_ c: RGB) -> CGColor { CGColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1) }

    private static func mix(_ a: RGB, _ b: RGB, _ t: CGFloat) -> RGB {
        (a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t)
    }

    func makeLayer(size: CGSize) -> CALayer {
        let root = CALayer()
        root.frame = CGRect(origin: .zero, size: size)
        stage.frame = root.bounds
        root.addSublayer(stage)
        let circle = CGRect(x: (size.width - orbDiameter) / 2, y: (size.height - orbDiameter) / 2,
                            width: orbDiameter, height: orbDiameter)
        for layer in [glow, body, shimmer, flash] {
            layer.frame = circle
            layer.cornerRadius = orbDiameter / 2
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

    func apply(_ look: OrbLook, level: Double, reduceMotion: Bool) {
        if look != self.look || reduceMotion != self.reduceMotion {
            self.look = look
            self.reduceMotion = reduceMotion
            restyle(look)
        }
        if look == .listening, !reduceMotion { listen(CGFloat(min(max(level, 0), 1))) }
    }

    private func restyle(_ look: OrbLook) {
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
        body.colors = [Self.cg(palette.centre), Self.cg(palette.edge)]
        glow.backgroundColor = Self.cg(palette.edge)
        glow.shadowColor = Self.cg(palette.edge)
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
        let edge = Self.mix(Self.blue.edge, Self.white, level * 0.6)
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.1)
        stage.transform = CATransform3DMakeScale(scale, scale, 1)
        body.colors = [Self.cg(Self.mix(Self.blue.centre, Self.white, level)), Self.cg(edge)]
        glow.shadowColor = Self.cg(edge)
        glow.shadowOpacity = Float(0.6 + 0.4 * level)
        CATransaction.commit()
    }
}

// MARK: - Window

final class OrbPanel: NSPanel {
    // Never key or main: the paste goes to the frontmost app, and a focus change refuses it.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class OrbView: NSView {
    weak var owner: OrbWindow?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let p = convert(point, from: superview)
        return hypot(p.x - bounds.midX, p.y - bounds.midY) <= orbDiameter / 2 ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { owner?.showMenu(event) } else { owner?.pressed() }
    }

    override func mouseDragged(with event: NSEvent) { owner?.dragged() }
    override func mouseUp(with event: NSEvent) { owner?.released() }
    override func rightMouseDown(with event: NSEvent) { owner?.showMenu(event) }
}

final class OrbWindow {
    var onPress: () -> Void = {}
    var onRelease: () -> Void = {}
    var onDrag: () -> Void = {}
    var isRecording: () -> Bool = { false }
    private let defaults: UserDefaults
    private let menu: NSMenu
    private let view: OrbView
    private let panel: OrbPanel
    private var character: PetCharacter?
    private var gesture = OrbGesture()
    private var pressOrigin = NSPoint.zero
    private var look = OrbLook.idle
    private var level = 0.0

    var isShown: Bool { character != nil }

    init(defaults: UserDefaults, menu: NSMenu) {
        self.defaults = defaults
        self.menu = menu
        view = OrbView(frame: NSRect(x: 0, y: 0, width: orbPanelSide, height: orbPanelSide))
        panel = OrbPanel(contentRect: view.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.contentView = view
        view.owner = self
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.button)
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in self?.place() }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                                                          object: nil, queue: .main) { [weak self] _ in self?.render() }
        NotificationCenter.default.addObserver(forName: NSWindow.didChangeBackingPropertiesNotification,
                                               object: panel, queue: .main) { [weak self] _ in self?.matchBacking() }
    }

    private var activeCharacter: PetCharacter.Type { petCharacter(named: defaults.string(forKey: DefaultsKey.character.rawValue)) }

    // Hidden means ordered out with no animations; showing builds a fresh character.
    func setShown(_ on: Bool) {
        guard on != isShown else { return }
        if on {
            let c = activeCharacter.init()
            view.layer = c.makeLayer(size: view.bounds.size)
            view.wantsLayer = true
            character = c
            place()
            render()
            panel.orderFrontRegardless()
        } else {
            setPressed(false)
            character = nil
            stopAnimations(view.layer)
            panel.orderOut(nil)
        }
    }

    // Same panel, place, look and session; only the layer tree is new, so it is not pressed.
    func reloadCharacter() {
        guard isShown else { return }
        stopAnimations(view.layer)
        let c = activeCharacter.init()
        view.layer = c.makeLayer(size: view.bounds.size)
        character = c
        matchBacking()
        render()
    }

    private func stopAnimations(_ layer: CALayer?) {
        layer?.removeAllAnimations()
        layer?.sublayers?.forEach { stopAnimations($0) }
    }

    // The primary screen, not the focused one, so an undragged orb stays put.
    private func place() {
        let primary = NSScreen.screens.first?.visibleFrame ?? .zero
        let origin = savedOrbOrigin(defaults.object(forKey: DefaultsKey.orbOrigin.rawValue))
            ?? defaultOrbOrigin(in: primary, side: orbPanelSide)
        let frame = NSRect(origin: origin, size: NSSize(width: orbPanelSide, height: orbPanelSide))
        panel.setFrameOrigin(clampOrb(frame, into: NSScreen.screens.map(\.visibleFrame)).origin)
        matchBacking()
    }

    // Hand-built layers default to 1x and would blur on Retina.
    private func matchBacking() {
        let scale = panel.screen != nil ? panel.backingScaleFactor : (NSScreen.screens.first?.backingScaleFactor ?? 1)
        func apply(_ layer: CALayer?) {
            layer?.contentsScale = scale
            layer?.sublayers?.forEach { apply($0) }
        }
        apply(view.layer)
    }

    // Scales the root layer only; the character animates its sublayers.
    private func setPressed(_ on: Bool) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.08)
        CATransaction.setDisableActions(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        view.layer?.transform = on ? CATransform3DMakeScale(0.94, 0.94, 1) : CATransform3DIdentity
        CATransaction.commit()
    }

    func update(_ look: OrbLook, label: String) {
        if view.accessibilityLabel() != label { view.setAccessibilityLabel(label) }
        if look != self.look {
            self.look = look
            level = 0
        }
        render()
    }

    func setLevel(_ raw: Double) {
        guard isShown, look == .listening else { return }
        level = smoothLevel(level, toward: raw)
        render()
    }

    private func render() {
        character?.apply(look, level: level, reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    func contains(_ location: CGPoint) -> Bool {
        guard isShown, let primary = NSScreen.screens.first else { return false }
        return orbHit(location, circle: panel.frame.insetBy(dx: orbGlowMargin, dy: orbGlowMargin),
                      primaryHeight: primary.frame.height)
    }

    fileprivate func pressed() {
        gesture.down(at: NSEvent.mouseLocation)
        pressOrigin = panel.frame.origin
        setPressed(true)
        onPress()
    }

    fileprivate func dragged() {
        let p = NSEvent.mouseLocation
        if gesture.moved(to: p, recording: isRecording()) {
            setPressed(false)
            onDrag()
        }
        guard gesture.kind == .drag else { return }
        panel.setFrameOrigin(NSPoint(x: pressOrigin.x + p.x - gesture.origin.x, y: pressOrigin.y + p.y - gesture.origin.y))
    }

    fileprivate func released() {
        setPressed(false)
        let kind = gesture.up()
        guard kind != .none else { return }
        if kind == .drag {
            defaults.set([Double(panel.frame.minX), Double(panel.frame.minY)], forKey: DefaultsKey.orbOrigin.rawValue)
            place()
        }
        onRelease()
    }

    // The status item's menu: menuNeedsUpdate rebuilds it.
    fileprivate func showMenu(_ event: NSEvent) {
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }
}

// MARK: - Self-test

func runPetSelfTest(_ check: (String, Bool) -> Void) {
    check("look: listening wins over everything", orbLook(ui: .listening, health: .needsAccessibility, outcome: .error) == .listening)
    check("look: transcribing", orbLook(ui: .transcribing, health: .ready, outcome: .none) == .transcribing)
    check("look: transcribing wins over server down", orbLook(ui: .transcribing, health: .serverDown, outcome: .none) == .transcribing)
    check("look: sent shows while still transcribing", orbLook(ui: .transcribing, health: .ready, outcome: .sent) == .sent)
    check("look: idle", orbLook(ui: .idle, health: .ready, outcome: .none) == .idle)
    check("look: Accessibility missing", orbLook(ui: .idle, health: .needsAccessibility, outcome: .none) == .needsPermission)
    check("look: hotkey unavailable", orbLook(ui: .idle, health: .hotkeyUnavailable, outcome: .none) == .needsPermission)
    check("look: microphone pending", orbLook(ui: .idle, health: .micPending, outcome: .none) == .needsPermission)
    check("look: microphone denied", orbLook(ui: .idle, health: .micDenied, outcome: .none) == .needsPermission)
    check("look: server down", orbLook(ui: .idle, health: .serverDown, outcome: .none) == .error)
    check("look: error outcome", orbLook(ui: .idle, health: .ready, outcome: .error) == .error)
    check("look: sent", orbLook(ui: .idle, health: .ready, outcome: .sent) == .sent)
    check("look: nothing heard", orbLook(ui: .idle, health: .ready, outcome: .nothingHeard) == .nothingHeard)
    check("look: permission wins over an outcome", orbLook(ui: .idle, health: .micDenied, outcome: .error) == .needsPermission)
    check("look: server down wins over sent", orbLook(ui: .idle, health: .serverDown, outcome: .sent) == .error)
    check("look: listening while ready", orbLook(ui: .listening, health: .ready, outcome: .none) == .listening)
    check("look: listening wins over server down", orbLook(ui: .listening, health: .serverDown, outcome: .none) == .listening)
    check("look: listening wins over a sent outcome", orbLook(ui: .listening, health: .ready, outcome: .sent) == .listening)
    check("look: listening wins over nothing heard", orbLook(ui: .listening, health: .ready, outcome: .nothingHeard) == .listening)
    check("look: transcribing wins over every permission", [Health.needsAccessibility, .hotkeyUnavailable, .micPending, .micDenied]
          .allSatisfy { orbLook(ui: .transcribing, health: $0, outcome: .none) == .transcribing })
    check("look: nothing heard ends transcribing", orbLook(ui: .transcribing, health: .ready, outcome: .nothingHeard) == .nothingHeard)
    check("look: error ends transcribing", orbLook(ui: .transcribing, health: .ready, outcome: .error) == .error)
    check("look: permission wins over sent", orbLook(ui: .idle, health: .needsAccessibility, outcome: .sent) == .needsPermission)
    check("look: permission wins over nothing heard", orbLook(ui: .idle, health: .micPending, outcome: .nothingHeard) == .needsPermission)
    check("look: server down wins over nothing heard", orbLook(ui: .idle, health: .serverDown, outcome: .nothingHeard) == .error)
    check("outcome: start clears", OrbOutcome(.start) == .none)
    check("outcome: sent", OrbOutcome(.sent) == .sent)
    check("outcome: nothing heard", OrbOutcome(.nothingHeard) == .nothingHeard)
    check("outcome: error", OrbOutcome(.error) == .error)

    func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }
    check("level: empty buffer is 0", voiceLevel([Int16]()) == 0)
    check("level: silence is 0", voiceLevel([Int16](repeating: 0, count: 64)) == 0)
    check("level: full scale is 1", voiceLevel([Int16.max, Int16.min, Int16.max, Int16.min]) == 1)
    check("level: -30 dBFS is mid-scale", abs(voiceLevel([Int16](repeating: 1036, count: 64)) - 0.5) < 0.01)
    check("level: below -50 dBFS is 0", voiceLevel([Int16](repeating: 10, count: 64)) == 0)
    check("level: -40 dBFS is a quarter", abs(voiceLevel([Int16](repeating: 328, count: 64)) - 0.25) < 0.01)
    check("level: -10 dBFS reaches the top", voiceLevel([Int16](repeating: 10363, count: 64)) == 1
          && voiceLevel([Int16](repeating: 10362, count: 64)) >= 0.99)
    check("level: just above -50 dBFS is small but positive", (0..<0.01).contains(voiceLevel([Int16](repeating: 104, count: 64)))
          && voiceLevel([Int16](repeating: 104, count: 64)) > 0)
    check("level: RMS, not peak or mean", abs(voiceLevel([Int16](repeating: 0, count: 32) + [Int16](repeating: 1465, count: 32)) - 0.5) < 0.01)
    check("smooth: fast attack", near(smoothLevel(0, toward: 1), levelAttack))
    check("smooth: slower release", near(smoothLevel(1, toward: 0), 1 - levelRelease) && levelRelease < levelAttack)
    check("smooth: input above 1 is capped", near(smoothLevel(0.5, toward: 7), 0.5 + 0.5 * levelAttack))
    check("smooth: NaN input counts as silence", near(smoothLevel(0.5, toward: .nan), 0.5 - 0.5 * levelRelease))
    check("smooth: negative input counts as silence", near(smoothLevel(0.5, toward: -3), 0.5 - 0.5 * levelRelease))
    check("smooth: infinite input counts as silence", near(smoothLevel(0.5, toward: .infinity), 0.5 - 0.5 * levelRelease))
    check("smooth: NaN previous starts from 0", near(smoothLevel(.nan, toward: 0.5), 0.5 * levelAttack))
    check("smooth: previous above 1 starts from 1", near(smoothLevel(5, toward: 0.5), 1 - 0.5 * levelRelease))
    check("smooth: negative previous starts from 0", near(smoothLevel(-2, toward: 0.5), 0.5 * levelAttack))

    var g = OrbGesture()
    g.down(at: CGPoint(x: 100, y: 100))
    check("gesture: still press is a press", g.up() == .press && g.kind == .none)
    check("gesture: move before a press does nothing", !g.moved(to: CGPoint(x: 500, y: 500), recording: false) && g.kind == .none)
    g.down(at: CGPoint(x: 100, y: 100))
    check("gesture: exactly the threshold is still a press", !g.moved(to: CGPoint(x: 104, y: 100), recording: false) && g.kind == .press)
    check("gesture: past the threshold becomes a drag", g.moved(to: CGPoint(x: 103, y: 103), recording: false) && g.kind == .drag)
    check("gesture: a drag is reported once", !g.moved(to: CGPoint(x: 150, y: 150), recording: false))
    check("gesture: release ends a drag", g.up() == .drag && g.kind == .none)
    g.down(at: CGPoint(x: 100, y: 100))
    check("gesture: drag the other way", g.moved(to: CGPoint(x: 95, y: 100), recording: false))
    g.down(at: CGPoint(x: 100, y: 100))
    check("gesture: movement while recording is ignored", !g.moved(to: CGPoint(x: 200, y: 100), recording: true) && g.kind == .press)
    check("gesture: a press that saw recording never drags", !g.moved(to: CGPoint(x: 300, y: 100), recording: false))
    check("gesture: release after recording is a press", g.up() == .press)
    g.down(at: CGPoint(x: 100, y: 100))
    check("gesture: a new press clears the recording lock", g.moved(to: CGPoint(x: 110, y: 100), recording: false))
    _ = g.up()
    g.down(at: CGPoint(x: 100, y: 100))
    check("gesture: a small move while recording locks", !g.moved(to: CGPoint(x: 101, y: 100), recording: true)
          && !g.moved(to: CGPoint(x: 300, y: 100), recording: false) && g.kind == .press)
    _ = g.up()
    var fresh = OrbGesture()
    check("gesture: release without a press is nothing", fresh.up() == .none)
    g.down(at: .zero)
    check("gesture: diagonal 4.10 is a drag", g.moved(to: CGPoint(x: 2.9, y: 2.9), recording: false))
    _ = g.up()
    g.down(at: .zero)
    check("gesture: diagonal 3.96 is a press", !g.moved(to: CGPoint(x: 2.8, y: 2.8), recording: false) && g.kind == .press)

    let circle = CGRect(x: 100, y: 100, width: 56, height: 56)
    check("hit: centre", orbHit(CGPoint(x: 128, y: 1000 - 128), circle: circle, primaryHeight: 1000))
    check("hit: on the edge", orbHit(CGPoint(x: 156, y: 1000 - 128), circle: circle, primaryHeight: 1000))
    check("hit: just outside the edge", !orbHit(CGPoint(x: 156.5, y: 1000 - 128), circle: circle, primaryHeight: 1000))
    check("hit: square corner is outside", !orbHit(CGPoint(x: 101, y: 1000 - 101), circle: circle, primaryHeight: 1000))
    check("hit: y is flipped", !orbHit(CGPoint(x: 128, y: 120), circle: circle, primaryHeight: 1000)
          && orbHit(CGPoint(x: 128, y: 880), circle: circle, primaryHeight: 1000))
    check("hit: top and bottom edges", orbHit(CGPoint(x: 128, y: 844), circle: circle, primaryHeight: 1000)
          && orbHit(CGPoint(x: 128, y: 900), circle: circle, primaryHeight: 1000)
          && !orbHit(CGPoint(x: 128, y: 843.5), circle: circle, primaryHeight: 1000)
          && !orbHit(CGPoint(x: 128, y: 900.5), circle: circle, primaryHeight: 1000))
    let lowerLeft = CGRect(x: -300, y: -500, width: 56, height: 56)
    check("hit: display below and left of the primary", orbHit(CGPoint(x: -272, y: 1472), circle: lowerLeft, primaryHeight: 1000)
          && orbHit(CGPoint(x: -244, y: 1472), circle: lowerLeft, primaryHeight: 1000)
          && !orbHit(CGPoint(x: -243.5, y: 1472), circle: lowerLeft, primaryHeight: 1000)
          && !orbHit(CGPoint(x: -272, y: 528), circle: lowerLeft, primaryHeight: 1000))

    check("press: left down on the orb", isOrbPress(type: .leftMouseDown, onOrb: true))
    check("press: left down elsewhere", !isOrbPress(type: .leftMouseDown, onOrb: false))
    check("press: right down on the orb", !isOrbPress(type: .rightMouseDown, onOrb: true))
    check("press: other button on the orb", !isOrbPress(type: .otherMouseDown, onOrb: true))
    check("press: key down", !isOrbPress(type: .keyDown, onOrb: true))

    let side = orbPanelSide
    let main = CGRect(x: 0, y: 0, width: 1440, height: 875)
    let second = CGRect(x: 1440, y: -200, width: 1920, height: 1055)
    func clamped(_ x: CGFloat, _ y: CGFloat, _ screens: [CGRect]) -> CGPoint {
        clampOrb(CGRect(x: x, y: y, width: side, height: side), into: screens).origin
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
          defaultOrbOrigin(in: CGRect(x: 0, y: 70, width: 1440, height: 805), side: side) == CGPoint(x: 1440 - side - 24, y: 94))
    let above = CGRect(x: 0, y: 875, width: 1440, height: 900)
    check("clamp: above a stacked pair picks the upper screen", clamped(500, 2000, [main, above]) == CGPoint(x: 500, y: 1775 - side))
    check("clamp: below a stacked pair picks the lower screen", clamped(500, -500, [main, above]) == CGPoint(x: 500, y: 0))
    let exact = CGRect(x: 10, y: 20, width: side, height: side)
    check("clamp: exact fit", clamped(10, 20, [exact]) == CGPoint(x: 10, y: 20) && clamped(12, 25, [exact]) == CGPoint(x: 10, y: 20))
    check("place: default on an offset visible frame",
          defaultOrbOrigin(in: CGRect(x: 1440, y: -130, width: 1920, height: 985), side: side) == CGPoint(x: 3360 - side - 24, y: -106))
    check("saved: two finite numbers", savedOrbOrigin([10.0, 20.0]) == CGPoint(x: 10, y: 20))
    check("saved: missing", savedOrbOrigin(nil) == nil)
    check("saved: wrong count", savedOrbOrigin([10.0]) == nil && savedOrbOrigin([1.0, 2.0, 3.0]) == nil)
    check("saved: NaN", savedOrbOrigin([Double.nan, 20.0]) == nil)
    check("saved: infinity", savedOrbOrigin([10.0, -Double.infinity]) == nil)
    check("saved: not numbers", savedOrbOrigin(["a", "b"]) == nil)

    check("characters: Orb is registered first", petCharacters.first?.displayName == "Orb")
    let pet = petCharacters[0].init()
    let layer = pet.makeLayer(size: CGSize(width: side, height: side))
    for look in [OrbLook.idle, .listening, .transcribing, .sent, .nothingHeard, .error, .needsPermission] {
        pet.apply(look, level: 0.5, reduceMotion: false)
        pet.apply(look, level: 0.5, reduceMotion: true)
    }
    check("characters: Orb builds a layer tree of the panel's size", layer.bounds.size == CGSize(width: side, height: side)
          && layer.sublayers?.first?.sublayers?.count == 4)

    func keys(_ l: CALayer) -> [String] { (l.animationKeys() ?? []) + (l.sublayers ?? []).flatMap(keys) }
    func named(_ l: CALayer) -> [String] { keys(l).filter { ["breath", "swirl", "once"].contains($0) } }
    let orb = Orb()
    let root = orb.makeLayer(size: CGSize(width: side, height: side))
    let stage = root.sublayers?.first ?? CALayer()
    let parts = stage.sublayers ?? []
    check("motion: idle breathes", stage.animationKeys()?.contains("breath") == true)
    orb.apply(.idle, level: 0, reduceMotion: true)
    check("motion: Reduce Motion idle is still", keys(root).isEmpty)
    orb.apply(.listening, level: 0.5, reduceMotion: false)
    check("motion: listening has no character animation", named(root).isEmpty)
    orb.apply(.transcribing, level: 0, reduceMotion: false)
    check("motion: transcribing swirls", parts.count == 4 && parts[2].animationKeys()?.contains("swirl") == true)
    orb.apply(.sent, level: 0, reduceMotion: false)
    check("motion: sent flashes once", parts.count == 4 && parts[3].animationKeys()?.contains("once") == true)
    orb.apply(.needsPermission, level: 0, reduceMotion: false)
    check("motion: needs permission is still", keys(root).isEmpty)

    let names = petCharacters.map { $0.displayName }
    check("characters: two, with unique names", names.count == 2 && Set(names).count == names.count)
    check("characters: Arc reactor is registered second", names.last == "Arc reactor")
    check("character: none saved means the Arc reactor", petCharacter(named: nil).displayName == "Arc reactor")
    check("character: an unknown name means the Arc reactor", ["Clippy", "", "orb"].allSatisfy {
        petCharacter(named: $0).displayName == "Arc reactor"
    })
    check("character: Orb", petCharacter(named: "Orb").displayName == "Orb")
    check("character: Arc reactor", petCharacter(named: "Arc reactor").displayName == "Arc reactor")
    check("character: the default is registered and is the Arc reactor", defaultPetCharacter.displayName == "Arc reactor"
          && names.contains(defaultPetCharacter.displayName))

    runReactorSelfTest(check)
}
