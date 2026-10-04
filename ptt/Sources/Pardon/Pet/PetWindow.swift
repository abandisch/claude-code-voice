// The pet: Pardon's floating push-to-talk button, as a panel, its view and the window that owns both.
import AppKit
import QuartzCore

// MARK: - Window

final class PetPanel: NSPanel {
    // Never key or main: the paste goes to the frontmost app, and a focus change refuses it.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class PetView: NSView {
    weak var owner: PetWindow?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let p = convert(point, from: superview)
        return hypot(p.x - bounds.midX, p.y - bounds.midY) <= petDiameter / 2 ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { owner?.showMenu(event) } else { owner?.pressed() }
    }

    override func mouseDragged(with event: NSEvent) { owner?.dragged() }
    override func mouseUp(with event: NSEvent) { owner?.released() }
    override func rightMouseDown(with event: NSEvent) { owner?.showMenu(event) }
}

final class PetWindow {
    var onPress: () -> Void = {}
    var onRelease: () -> Void = {}
    var onDrag: () -> Void = {}
    var isRecording: () -> Bool = { false }
    var canCancelRecording: () -> Bool = { false }
    private let defaults: UserDefaults
    private let menu: NSMenu
    private let view: PetView
    private let panel: PetPanel
    private var character: PetCharacter?
    private var gesture = PetGesture()
    private var pressOrigin = NSPoint.zero
    private var look = PetLook.idle
    private var level = 0.0

    var isShown: Bool { character != nil }

    init(defaults: UserDefaults, menu: NSMenu) {
        self.defaults = defaults
        self.menu = menu
        view = PetView(frame: NSRect(x: 0, y: 0, width: petPanelSide, height: petPanelSide))
        panel = PetPanel(contentRect: view.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
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

    // The primary screen, not the focused one, so an undragged pet stays put.
    private func place() {
        let primary = NSScreen.screens.first?.visibleFrame ?? .zero
        let origin = savedPetOrigin(defaults.object(forKey: DefaultsKey.orbOrigin.rawValue))
            ?? defaultPetOrigin(in: primary, side: petPanelSide)
        let frame = NSRect(origin: origin, size: NSSize(width: petPanelSide, height: petPanelSide))
        panel.setFrameOrigin(clampPet(frame, into: NSScreen.screens.map(\.visibleFrame)).origin)
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

    func update(_ look: PetLook, label: String) {
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
        character?.animatesWhenIdle = defaults.bool(forKey: DefaultsKey.animateIdle.rawValue)
        character?.apply(look, level: level, reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    func contains(_ location: CGPoint) -> Bool {
        guard isShown, let primary = NSScreen.screens.first else { return false }
        return petHit(location, circle: panel.frame.insetBy(dx: petGlowMargin, dy: petGlowMargin),
                      primaryHeight: primary.frame.height)
    }

    fileprivate func pressed() {
        gesture.down(at: NSEvent.mouseLocation, time: now())
        pressOrigin = panel.frame.origin
        setPressed(true)
        onPress()
    }

    fileprivate func dragged() {
        let p = NSEvent.mouseLocation
        if gesture.moved(to: p, recording: isRecording(), cancellable: canCancelRecording(), at: now()) {
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
