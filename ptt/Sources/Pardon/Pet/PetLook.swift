import Foundation

// MARK: - Pure pieces (exercised by --self-test)

enum PetLook: Equatable { case idle, listening, transcribing, sent, nothingHeard, error, needsPermission }

enum PetOutcome: Equatable {
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

// Each outcome gets a generation; a decay scheduled for an older one must not clear a newer outcome.
struct OutcomeDecay {
    static let seconds: TimeInterval = 10
    private(set) var generation = 0

    mutating func next() -> Int {
        generation += 1
        return generation
    }

    func isCurrent(_ g: Int) -> Bool { g == generation }
}

// Listening wins, then transcribing until an outcome ends it, then permissions, then the server, then the outcome.
func petLook(ui: UIState, health: Health, outcome: PetOutcome) -> PetLook {
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
