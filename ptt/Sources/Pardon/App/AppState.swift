enum Cue: String, CaseIterable { case start = "Tink", sent = "Pop", nothingHeard = "Purr", error = "Basso" }
enum Health { case ready, needsAccessibility, hotkeyUnavailable, micPending, micDenied, serverDown }
enum UIState { case idle, listening, transcribing }
