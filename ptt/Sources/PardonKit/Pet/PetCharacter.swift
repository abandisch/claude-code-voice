import QuartzCore

// MARK: - Characters

protocol PetCharacter: AnyObject {
    static var displayName: String { get }
    init()
    // Fills size; the clickable circle is petDiameter wide at the centre.
    func makeLayer(size: CGSize) -> CALayer
    // False stills the idle, sent, nothing heard and error looks' repeating motion; a change restyles on the next apply.
    var animatesWhenIdle: Bool { get set }
    // Called on every look change and level update; level is 0 unless listening; reduceMotion means static looks only.
    func apply(_ look: PetLook, level: Double, reduceMotion: Bool)
}

// Measured: full rate doubles the window server's work for no visible gain.
let petIdleFrameRate = CAFrameRateRange(minimum: 24, maximum: 30, preferred: 30)

func capIdleFrameRate(_ a: CAAnimation) {
    a.preferredFrameRateRange = petIdleFrameRate
    (a as? CAAnimationGroup)?.animations?.forEach(capIdleFrameRate)
}

// Unlike smoothLevel's unit, NaN passes through.
func clampUnit(_ x: Double) -> Double { min(max(x, 0), 1) }

let petCharacters: [PetCharacter.Type] = [Orb.self, ArcReactor.self]
let defaultPetCharacter: PetCharacter.Type = ArcReactor.self

// Nil or an unknown name, such as a removed character's, means the default.
func petCharacter(named name: String?) -> PetCharacter.Type {
    petCharacters.first { $0.displayName == name } ?? defaultPetCharacter
}
