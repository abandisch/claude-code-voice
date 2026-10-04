import QuartzCore
import Testing
@testable import PardonKit

@Suite struct PetCharacterTests {
    @Test func registry() {
        check("characters: Orb is registered first", petCharacters.first?.displayName == "Orb")
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
    }

    @Test func layerTree() {
        let side = petPanelSide
        let pet = petCharacters[0].init()
        let layer = pet.makeLayer(size: CGSize(width: side, height: side))
        for look in [PetLook.idle, .listening, .transcribing, .sent, .nothingHeard, .error, .needsPermission] {
            pet.apply(look, level: 0.5, reduceMotion: false)
            pet.apply(look, level: 0.5, reduceMotion: true)
        }
        check("characters: Orb builds a layer tree of the panel's size", layer.bounds.size == CGSize(width: side, height: side)
              && layer.sublayers?.first?.sublayers?.count == 4)
    }

    @Test func clamp() {
        check("clampUnit: below 0 is 0", clampUnit(-0.5) == 0)
        check("clampUnit: above 1 is 1", clampUnit(1.5) == 1)
        check("clampUnit: in range passes through", clampUnit(0) == 0 && clampUnit(0.25) == 0.25 && clampUnit(1) == 1)
        check("clampUnit: NaN passes through", clampUnit(.nan).isNaN)
    }
}
