import Testing
@testable import PardonKit

@Suite struct PetLookTests {
    @Test func look() {
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
    }

    @Test func outcome() {
        check("outcome: start clears", PetOutcome(.start) == .none)
        check("outcome: sent", PetOutcome(.sent) == .sent)
        check("outcome: nothing heard", PetOutcome(.nothingHeard) == .nothingHeard)
        check("outcome: error", PetOutcome(.error) == .error)
    }

    @Test func decay() {
        var decay = OutcomeDecay()
        let older = decay.next()
        check("decay: the newest outcome's decay clears it", decay.isCurrent(older))
        let newer = decay.next()
        check("decay: a stale decay is ignored", !decay.isCurrent(older) && decay.isCurrent(newer))
        check("decay: about ten seconds", OutcomeDecay.seconds == 10)
    }
}
