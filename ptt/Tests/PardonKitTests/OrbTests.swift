import QuartzCore
import Testing
@testable import PardonKit

@Suite struct OrbTests {
    @Test func motion() {
        let side = petPanelSide
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
    }
}
