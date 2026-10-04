import AppKit
import QuartzCore

// MARK: - Self-test

func capped(_ a: CAAnimation?) -> Bool { a?.preferredFrameRateRange == petIdleFrameRate }
func cappedGroup(_ a: CAAnimation?) -> Bool {
    let children = (a as? CAAnimationGroup)?.animations ?? []
    return capped(a) && children.count == 2 && children.allSatisfy(capped)
}
func uncapped(_ a: CAAnimation?) -> Bool {
    guard let a = a else { return false }
    return ([a] + ((a as? CAAnimationGroup)?.animations ?? [])).allSatisfy { $0.preferredFrameRateRange == .default }
}

func runPetSelfTest(_ check: (String, Bool) -> Void) {
    check("look: listening wins over everything", petLook(ui: .listening, health: .needsAccessibility, outcome: .error) == .listening)
    check("look: transcribing", petLook(ui: .transcribing, health: .ready, outcome: .none) == .transcribing)
    check("look: transcribing wins over server down", petLook(ui: .transcribing, health: .serverDown, outcome: .none) == .transcribing)
    check("look: sent shows while still transcribing", petLook(ui: .transcribing, health: .ready, outcome: .sent) == .sent)
    check("look: idle", petLook(ui: .idle, health: .ready, outcome: .none) == .idle)
    check("look: Accessibility missing", petLook(ui: .idle, health: .needsAccessibility, outcome: .none) == .needsPermission)
    check("look: hotkey unavailable", petLook(ui: .idle, health: .hotkeyUnavailable, outcome: .none) == .needsPermission)
    check("look: microphone pending", petLook(ui: .idle, health: .micPending, outcome: .none) == .needsPermission)
    check("look: microphone denied", petLook(ui: .idle, health: .micDenied, outcome: .none) == .needsPermission)
    check("look: server down", petLook(ui: .idle, health: .serverDown, outcome: .none) == .error)
    check("look: error outcome", petLook(ui: .idle, health: .ready, outcome: .error) == .error)
    check("look: sent", petLook(ui: .idle, health: .ready, outcome: .sent) == .sent)
    check("look: nothing heard", petLook(ui: .idle, health: .ready, outcome: .nothingHeard) == .nothingHeard)
    check("look: permission wins over an outcome", petLook(ui: .idle, health: .micDenied, outcome: .error) == .needsPermission)
    check("look: server down wins over sent", petLook(ui: .idle, health: .serverDown, outcome: .sent) == .error)
    check("look: listening while ready", petLook(ui: .listening, health: .ready, outcome: .none) == .listening)
    check("look: listening wins over server down", petLook(ui: .listening, health: .serverDown, outcome: .none) == .listening)
    check("look: listening wins over a sent outcome", petLook(ui: .listening, health: .ready, outcome: .sent) == .listening)
    check("look: listening wins over nothing heard", petLook(ui: .listening, health: .ready, outcome: .nothingHeard) == .listening)
    check("look: transcribing wins over every permission", [Health.needsAccessibility, .hotkeyUnavailable, .micPending, .micDenied]
          .allSatisfy { petLook(ui: .transcribing, health: $0, outcome: .none) == .transcribing })
    check("look: nothing heard ends transcribing", petLook(ui: .transcribing, health: .ready, outcome: .nothingHeard) == .nothingHeard)
    check("look: error ends transcribing", petLook(ui: .transcribing, health: .ready, outcome: .error) == .error)
    check("look: permission wins over sent", petLook(ui: .idle, health: .needsAccessibility, outcome: .sent) == .needsPermission)
    check("look: permission wins over nothing heard", petLook(ui: .idle, health: .micPending, outcome: .nothingHeard) == .needsPermission)
    check("look: server down wins over nothing heard", petLook(ui: .idle, health: .serverDown, outcome: .nothingHeard) == .error)
    check("outcome: start clears", PetOutcome(.start) == .none)
    check("outcome: sent", PetOutcome(.sent) == .sent)
    check("outcome: nothing heard", PetOutcome(.nothingHeard) == .nothingHeard)
    check("outcome: error", PetOutcome(.error) == .error)

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

    var g = PetGesture()
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
    var fresh = PetGesture()
    check("gesture: release without a press is nothing", fresh.up() == .none)
    g.down(at: .zero)
    check("gesture: diagonal 4.10 is a drag", g.moved(to: CGPoint(x: 2.9, y: 2.9), recording: false))
    _ = g.up()
    g.down(at: .zero)
    check("gesture: diagonal 3.96 is a press", !g.moved(to: CGPoint(x: 2.8, y: 2.8), recording: false) && g.kind == .press)

    let o = CGPoint(x: 100, y: 100), grace = PetGesture.recordingDragGrace
    check("gesture: recording drag needs 10 pt within 1.5 s", PetGesture.recordingDragThreshold == 10 && grace == 1.5)
    g = PetGesture()
    g.down(at: o, time: 0)
    check("gesture: own recording, exactly 10 pt is still a press",
          !g.moved(to: CGPoint(x: 110, y: 100), recording: true, cancellable: true, at: 0.5) && g.kind == .press)
    check("gesture: own recording, past 10 pt within grace becomes a drag",
          g.moved(to: CGPoint(x: 110.5, y: 100), recording: true, cancellable: true, at: 0.5) && g.kind == .drag)
    check("gesture: a recording drag is reported once",
          !g.moved(to: CGPoint(x: 200, y: 100), recording: false, cancellable: false, at: 0.6) && g.up() == .drag)
    g.down(at: o, time: 10)
    check("gesture: own recording, exactly the grace period still drags",
          g.moved(to: CGPoint(x: 120, y: 100), recording: true, cancellable: true, at: 10 + grace))
    _ = g.up()
    g.down(at: o, time: 10)
    check("gesture: own recording, just past the grace period is ignored",
          !g.moved(to: CGPoint(x: 120, y: 100), recording: true, cancellable: true, at: 10 + grace + 0.01)
          && g.up() == .press)
    g.down(at: o, time: 0)
    check("gesture: small move in grace, large move after it, stays a press",
          !g.moved(to: CGPoint(x: 105, y: 100), recording: true, cancellable: true, at: 0.5)
          && !g.moved(to: CGPoint(x: 200, y: 100), recording: true, cancellable: true, at: 2) && g.up() == .press)
    g.down(at: o, time: 0)
    check("gesture: recording it may not cancel never drags, even in grace",
          !g.moved(to: CGPoint(x: 200, y: 100), recording: true, cancellable: false, at: 0.3)
          && !g.moved(to: CGPoint(x: 300, y: 100), recording: true, cancellable: true, at: 0.4) && g.up() == .press)
    g.down(at: o, time: 0)
    check("gesture: recording ended in grace, no drag",
          !g.moved(to: CGPoint(x: 101, y: 100), recording: true, cancellable: true, at: 0.3)
          && !g.moved(to: CGPoint(x: 200, y: 100), recording: false, cancellable: false, at: 0.8) && g.up() == .press)
    g.down(at: o, time: 0)
    check("gesture: before recording, 4 pt rule with no time limit",
          !g.moved(to: CGPoint(x: 104, y: 100), recording: false, cancellable: false, at: 5)
          && g.moved(to: CGPoint(x: 105, y: 100), recording: false, cancellable: false, at: 5))
    _ = g.up()
    g.down(at: o, time: 0)
    _ = g.moved(to: CGPoint(x: 101, y: 100), recording: true, cancellable: false, at: 0.3)
    g.down(at: o, time: 5)
    check("gesture: a new press clears the lock and the press time",
          g.moved(to: CGPoint(x: 112, y: 100), recording: true, cancellable: true, at: 5.5))
    _ = g.up()
    g.down(at: o, time: 0)
    _ = g.moved(to: CGPoint(x: 101, y: 100), recording: true, cancellable: true, at: 0.3)
    g.down(at: o, time: 1)
    check("gesture: a new press forgets the recording it saw",
          g.moved(to: CGPoint(x: 105, y: 100), recording: false, cancellable: false, at: 1.1))
    _ = g.up()

    var decay = OutcomeDecay()
    let older = decay.next()
    check("decay: the newest outcome's decay clears it", decay.isCurrent(older))
    let newer = decay.next()
    check("decay: a stale decay is ignored", !decay.isCurrent(older) && decay.isCurrent(newer))
    check("decay: about ten seconds", OutcomeDecay.seconds == 10)

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

    check("press: left down on the orb", isPetPress(type: .leftMouseDown, onPet: true))
    check("press: left down elsewhere", !isPetPress(type: .leftMouseDown, onPet: false))
    check("press: right down on the orb", !isPetPress(type: .rightMouseDown, onPet: true))
    check("press: other button on the orb", !isPetPress(type: .otherMouseDown, onPet: true))
    check("press: key down", !isPetPress(type: .keyDown, onPet: true))

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
    check("saved: two finite numbers", savedPetOrigin([10.0, 20.0]) == CGPoint(x: 10, y: 20))
    check("saved: missing", savedPetOrigin(nil) == nil)
    check("saved: wrong count", savedPetOrigin([10.0]) == nil && savedPetOrigin([1.0, 2.0, 3.0]) == nil)
    check("saved: NaN", savedPetOrigin([Double.nan, 20.0]) == nil)
    check("saved: infinity", savedPetOrigin([10.0, -Double.infinity]) == nil)
    check("saved: not numbers", savedPetOrigin(["a", "b"]) == nil)

    check("characters: Orb is registered first", petCharacters.first?.displayName == "Orb")
    let pet = petCharacters[0].init()
    let layer = pet.makeLayer(size: CGSize(width: side, height: side))
    for look in [PetLook.idle, .listening, .transcribing, .sent, .nothingHeard, .error, .needsPermission] {
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

    check("idle rate: 30 frames a second, no fewer than 24", petIdleFrameRate.minimum == 24 && petIdleFrameRate.maximum == 30
          && petIdleFrameRate.preferred == 30)
    for look in [PetLook.idle, .sent, .nothingHeard, .error] {
        orb.apply(look, level: 0, reduceMotion: false)
        check("idle rate: Orb \(look) breath is capped, its parts too", cappedGroup(stage.animation(forKey: "breath")))
    }
    orb.apply(.sent, level: 0, reduceMotion: false)
    let flashed = parts.count == 4 ? parts[3].animation(forKey: "once") : nil
    orb.apply(.nothingHeard, level: 0, reduceMotion: false)
    check("idle rate: Orb flash and fade run at the display's rate", uncapped(flashed) && uncapped(stage.animation(forKey: "once")))
    orb.apply(.transcribing, level: 0, reduceMotion: false)
    check("idle rate: Orb swirl runs at the display's rate", parts.count == 4 && uncapped(parts[2].animation(forKey: "swirl")))

    let looks: [PetLook] = [.idle, .listening, .transcribing, .sent, .nothingHeard, .error, .needsPermission]
    orb.apply(.idle, level: 0, reduceMotion: false)
    orb.animatesWhenIdle = false
    orb.apply(.idle, level: 0, reduceMotion: false)
    check("animate when idle: turning it off restyles the same look, Orb idle is still", keys(root).isEmpty)
    orb.apply(.sent, level: 0, reduceMotion: false)
    check("animate when idle: off, Orb sent still flashes once, without breath",
          named(root) == ["once"] && parts.count == 4 && parts[3].animation(forKey: "once") != nil)
    orb.apply(.nothingHeard, level: 0, reduceMotion: false)
    check("animate when idle: off, Orb nothing heard still fades, without breath",
          named(root) == ["once"] && stage.animation(forKey: "once") != nil)
    orb.apply(.error, level: 0, reduceMotion: false)
    check("animate when idle: off, Orb error is still", keys(root).isEmpty)
    orb.apply(.transcribing, level: 0, reduceMotion: false)
    check("animate when idle: off, Orb transcribing still swirls", parts.count == 4 && uncapped(parts[2].animation(forKey: "swirl")))
    orb.apply(.idle, level: 0, reduceMotion: false)
    let offIdle = keys(root).isEmpty
    orb.animatesWhenIdle = true
    orb.apply(.idle, level: 0, reduceMotion: false)
    check("animate when idle: turning it back on restyles the same look, Orb idle breathes, capped",
          offIdle && cappedGroup(stage.animation(forKey: "breath")))
    check("animate when idle: Reduce Motion stills every Orb look either way", [false, true].allSatisfy { on in
        orb.animatesWhenIdle = on
        return looks.allSatisfy { look in
            orb.apply(look, level: 1, reduceMotion: true)
            return keys(root).isEmpty
        }
    })

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
